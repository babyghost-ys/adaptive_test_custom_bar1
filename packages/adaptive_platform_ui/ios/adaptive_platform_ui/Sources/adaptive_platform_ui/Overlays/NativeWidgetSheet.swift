import Flutter
import UIKit

/// Every visible sheet owns a continuously attached Flutter engine. The page
/// keeps its engine; no surfaces, viewport metrics, native controls or snapshots
/// move between controllers. Arguments and results cross engines as codec data.
final class NativeWidgetSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    private final class Level {
        let engine: FlutterEngine
        let controller: SheetViewController
        let channel: FlutterMethodChannel
        let arguments: [String: Any]
        let completion: FlutterResult
        let depth: Int
        let detents: String
        let dismissible: Bool
        var window: UIWindow?
        var fitHeight: CGFloat
        var pendingFitHeight: CGFloat?
        var revision = 0
        var presented = false
        var presenting = false
        var ready = false
        var dismissing = false
        var closed = false
        var startupTimeout: DispatchWorkItem?
        /// The sheet's UIKit animations are paused for the first half of a
        /// turn (see [NativeWidgetSheet.freezeForTurn]).
        var turning = false
        /// How far the sheet view's layer clock has been run ahead to finish
        /// paused animations at once; its `timeOffset` between turns.
        var clockOffset: CFTimeInterval = 0

        init(engine: FlutterEngine, arguments: [String: Any], depth: Int,
             completion: @escaping FlutterResult) {
            self.engine = engine
            self.arguments = arguments
            self.depth = depth
            self.completion = completion
            detents = arguments["detents"] as? String ?? "fit"
            dismissible = arguments["dismissible"] as? Bool ?? true
            fitHeight = CGFloat((arguments["height"] as? NSNumber)?.doubleValue ?? 320)
            controller = SheetViewController(engine: engine, nibName: nil, bundle: nil)
            channel = FlutterMethodChannel(name: "adaptive_platform_ui/widget_sheet",
                                           binaryMessenger: engine.binaryMessenger)
        }
    }

    private let hostProvider: () -> UIViewController?
    private weak var originalHost: FlutterViewController?
    private let engineGroup = FlutterEngineGroup(name: "adaptive.native.sheets", project: nil)
    private var levels: [Level] = []
    private var measuredHeights: [String: CGFloat] = [:]
    private var heightTransitions: Set<ObjectIdentifier> = []
    private var unqueuedHeightTransitions: Set<ObjectIdentifier> = []

    var pageController: FlutterViewController? {
        originalHost ?? hostProvider() as? FlutterViewController
    }

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.hostProvider = hostProvider
        super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        handle(call, from: nil, result: result)
    }

    private func handle(_ call: FlutterMethodCall, from source: Level?,
                        result: @escaping FlutterResult) {
        if let source, source.closed {
            result(FlutterError(code: "closed", message: "The sheet has closed", details: nil))
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "present":
            present(args, from: source, result: result)
        case "bootstrap":
            guard let source else { result(FlutterMethodNotImplemented); return }
            result(source.arguments)
            // The surface needs its real UIKit appearance and sheet metrics.
            // Waiting for a raster frame before presenting would deadlock.
            DispatchQueue.main.async { [weak self, weak source] in
                guard let self, let source, !source.closed, !source.presented else { return }
                self.presentLevel(source)
            }
        case "ready":
            guard let source else { result(FlutterMethodNotImplemented); return }
            source.ready = true
            source.startupTimeout?.cancel()
            source.startupTimeout = nil
            result(nil)
        case "setHeight":
            if let source { setHeight(args, for: source) }
            result(nil)
        case "dismiss":
            dismiss(source, value: args["value"], result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func present(_ args: [String: Any], from source: Level?,
                         result: @escaping FlutterResult) {
        guard let route = args["route"] as? String, !route.isEmpty else {
            result(FlutterError(code: "missing_route", message: "A registered sheet route is required", details: nil))
            return
        }
        // Covered engines still receive asynchronous events. Only the active
        // caller may place another workflow above the current one.
        guard source === levels.last,
              source.map({ $0.presented && $0.ready && !$0.dismissing }) ?? levels.isEmpty else {
            result(FlutterError(code: "busy", message: "Only the active sheet can present another sheet", details: nil))
            return
        }
        guard let host = pageController,
              let below = source?.window ?? host.view.window,
              let scene = below.windowScene else {
            result(FlutterError(code: "unavailable", message: "No visible Flutter page to present from", details: nil))
            return
        }
        originalHost = host
        let options = FlutterEngineGroupOptions()
        options.entrypoint = "nativeSheetMain"
        let engine = engineGroup.makeEngine(with: options)
        let level = Level(engine: engine, arguments: args, depth: levels.count, completion: result)
        if let height = measuredHeights[route] { level.fitHeight = height }
        levels.append(level)
        if let registrar = engine.registrar(forPlugin: "AdaptivePlatformUiPlugin") {
            AdaptivePlatformUiPlugin.registerSheetContent(with: registrar)
        }
        level.channel.setMethodCallHandler { [weak self, weak level] call, result in
            guard let self, let level else {
                result(FlutterError(code: "closed", message: "The sheet has closed", details: nil))
                return
            }
            self.handle(call, from: level, result: result)
        }

        // A separate transparent presenter keeps the page's view visible and
        // its real appearance lifecycle unchanged, even in compact landscape.
        // UIKit still owns the sheet, grabber, dimming and all drag gestures.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(below.windowLevel.rawValue + 1)
        window.backgroundColor = .clear
        let root = SheetWindowRootController()
        root.statusBarStyle = scene.statusBarManager?.statusBarStyle ?? .default
        root.view.backgroundColor = .clear
        window.rootViewController = root
        level.window = window
        let controller = level.controller
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = (args["backgroundColor"] as? NSNumber)
            .map { UIColor(argb: $0.intValue) } ?? .systemBackground
        // Flutter draws the sheet's new size half way through a turn; until
        // then its last frame stays unscaled at the top left of the view
        // rather than stretching to the view's new bounds.
        controller.view.contentMode = .topLeft
        switch args["brightness"] as? String {
        case "dark": controller.overrideUserInterfaceStyle = .dark
        case "light": controller.overrideUserInterfaceStyle = .light
        default: controller.overrideUserInterfaceStyle = .unspecified
        }
        controller.onTransition = { [weak self] coordinator in
            self?.observeHeightTransition(coordinator)
        }
        controller.onLayout = { [weak self] in
            self?.flushPendingHeights()
        }
        controller.onTurn = { [weak self, weak level] coordinator in
            guard let self, let level else { return }
            self.freezeForTurn(level, coordinator: coordinator)
        }
        root.onTurn = { [weak self, weak level] coordinator in
            guard let self, let level else { return }
            self.freezeForTurn(level, coordinator: coordinator)
        }
        let timeout = DispatchWorkItem { [weak self, weak level] in
            guard let self, let level, !level.ready, !level.closed, !level.dismissing else { return }
            self.failStartup(level)
        }
        level.startupTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        // The originating present call completes after dismissal, with the
        // encoded result. Its isolate retains its own page or parent draft.
    }

    private func presentLevel(_ level: Level) {
        guard let window = level.window, let presenter = window.rootViewController,
              !level.closed, !level.presented else { return }
        let controller = level.controller
        if level.detents == "fullScreen" {
            controller.modalPresentationStyle = .overFullScreen
            controller.modalPresentationCapturesStatusBarAppearance = true
            controller.isModalInPresentation = true
        } else {
            controller.modalPresentationStyle = .pageSheet
            controller.modalPresentationCapturesStatusBarAppearance = false
            // A sheet that only closes through its own controls is refused in
            // [presentationControllerShouldDismiss] rather than marked modal
            // in presentation, so UIKit presents and turns every sheet alike.
            controller.isModalInPresentation = false
            if let sheet = controller.sheetPresentationController {
                switch level.detents {
                case "full": sheet.detents = [.large()]
                case "fit":
                    if #available(iOS 16.0, *) {
                        setFitDetent(level, sheet: sheet)
                    } else {
                        sheet.detents = [.medium(), .large()]
                    }
                case "short":
                    if #available(iOS 16.0, *) {
                        sheet.detents = [.custom(identifier: .init("short\(level.depth)")) { context in
                            min(context.maximumDetentValue, max(context.maximumDetentValue * 0.34, 300))
                        }]
                    } else {
                        sheet.detents = [.medium()]
                    }
                default: sheet.detents = [.medium(), .large()]
                }
                sheet.prefersGrabberVisible = level.dismissible
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                sheet.prefersEdgeAttachedInCompactHeight = true
            }
        }
        controller.presentationController?.delegate = self
        level.presented = true
        level.presenting = true
        window.makeKeyAndVisible()
        presenter.present(controller, animated: true) { [weak self, weak level] in
            guard let self, let level else { return }
            level.presenting = false
            self.flushPendingHeights()
        }
    }

    @available(iOS 16.0, *)
    private func setFitDetent(_ level: Level, sheet: UISheetPresentationController) {
        let identifier = UISheetPresentationController.Detent.Identifier("fit\(level.depth)_\(level.revision)")
        let height = level.fitHeight
        sheet.detents = [.custom(identifier: identifier) { context in
            min(context.maximumDetentValue, height)
        }]
        sheet.selectedDetentIdentifier = identifier
    }

    private func setHeight(_ args: [String: Any], for level: Level) {
        guard let value = (args["height"] as? NSNumber)?.doubleValue,
              value.isFinite, value > 0, !level.closed, !level.dismissing else { return }
        let height = CGFloat(value)
        // A later measurement may return to the committed height during a
        // transition; discard any older pending measurement in that case.
        level.pendingFitHeight = abs(height - level.fitHeight) > 0.5 ? height : nil
        flushPendingHeights()
    }

    private func observeHeightTransition(_ coordinator: UIViewControllerTransitionCoordinator) {
        let identifier = ObjectIdentifier(coordinator as AnyObject)
        guard heightTransitions.insert(identifier).inserted else { return }
        let queued = coordinator.animate(alongsideTransition: { _ in }) { [weak self] _ in
            // Leave UIKit's transition transaction before changing detents.
            DispatchQueue.main.async {
                guard let self else { return }
                self.heightTransitions.remove(identifier)
                self.unqueuedHeightTransitions.remove(identifier)
                self.flushPendingHeights()
            }
        }
        // Apple notes the completion can still run when this returns false.
        // Keep the transition blocked until it is no longer active instead of
        // treating the return value as proof that it has finished.
        if !queued { unqueuedHeightTransitions.insert(identifier) }
    }

    private func flushPendingHeights() {
        guard levels.contains(where: { $0.pendingFitHeight != nil }) else { return }
        var coordinators: [UIViewControllerTransitionCoordinator] = []
        if let coordinator = pageController?.transitionCoordinator { coordinators.append(coordinator) }
        for level in levels {
            if let coordinator = level.controller.transitionCoordinator { coordinators.append(coordinator) }
            if let coordinator = level.window?.rootViewController?.transitionCoordinator {
                coordinators.append(coordinator)
            }
        }
        let active = Set(coordinators.map { ObjectIdentifier($0 as AnyObject) })
        // A completion may not be queued if we discover a coordinator late.
        // A later layout can release only those already absent from UIKit.
        let inactive = unqueuedHeightTransitions.subtracting(active)
        heightTransitions.subtract(inactive)
        unqueuedHeightTransitions.subtract(inactive)
        coordinators.forEach { observeHeightTransition($0) }
        guard heightTransitions.isEmpty, !levels.contains(where: { $0.presenting }) else { return }

        for level in levels where !level.closed && !level.dismissing {
            guard let height = level.pendingFitHeight else { continue }
            level.pendingFitHeight = nil
            level.fitHeight = height
            if let route = level.arguments["route"] as? String { measuredHeights[route] = height }
            guard #available(iOS 16.0, *), level.detents == "fit", level.presented,
                  let sheet = level.controller.sheetPresentationController else { continue }
            level.revision += 1
            // Keep the established per-level replacement: invalidating detents
            // previously resized the covered sheet as well.
            sheet.animateChanges { self.setFitDetent(level, sheet: sheet) }
        }
    }

    // MARK: Turning with the screen

    /// Lag after Flutter's half-way redraw before the sheet's frame follows
    /// it: the new frame reaches the screen a frame or two after the engine
    /// takes the new size.
    private static let turnSnapLag: TimeInterval = 1.0 / 30

    /// The view UIKit animates for a level: the drop-shadow container that
    /// holds the content, corners and grabber, or the content view alone.
    private func sheetView(of level: Level) -> UIView {
        level.controller.presentationController?.presentedView ?? level.controller.view
    }

    /// On iOS 26+ a rotation lays a picture of the old screen over the new
    /// layout and fades it out. Flutter (the page and this sheet) keeps its
    /// old frame for the first half of the turn, unscaled at the top left,
    /// which is where that picture shows it; UIKit, though, would move the
    /// sheet to its new frame from the first frame of the turn, so the
    /// picture's edge cut across it. The sheet's animations are paused at
    /// their start instead, so the sheet too lies where the picture shows it
    /// while the picture fades, then jump to their end at the half-way point,
    /// as Flutter's new layout arrives. Nothing is hidden or covered.
    private func freezeForTurn(_ level: Level, coordinator: UIViewControllerTransitionCoordinator) {
        guard level.presented, !level.closed, !level.dismissing, !level.presenting,
              !level.turning else { return }
        let duration = coordinator.transitionDuration
        guard duration > 0 else { return }
        let layer = sheetView(of: level).layer
        level.turning = true
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = now
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2 + Self.turnSnapLag) {
            [weak self, weak level] in
            guard let self, let level else { return }
            self.snapAfterTurn(level, duration: duration)
        }
        coordinator.animate(alongsideTransition: nil) { [weak self, weak level] _ in
            guard let self, let level else { return }
            self.snapAfterTurn(level, duration: duration)
        }
    }

    /// Runs the paused animations past their end, so the sheet takes its new
    /// frame at once. The layer clock is moved ahead rather than reset, so
    /// nothing added to the layer since is disturbed.
    private func snapAfterTurn(_ level: Level, duration: TimeInterval) {
        level.turning = false
        let layer = sheetView(of: level).layer
        guard layer.speed == 0 else { return }
        level.clockOffset += duration + 1
        layer.speed = 1
        layer.timeOffset = level.clockOffset
    }

    private func dismiss(_ source: Level?, value: Any?, result: @escaping FlutterResult) {
        guard let level = source, level === levels.last else {
            result(FlutterError(code: "inactive", message: "Only the active sheet can dismiss itself", details: nil))
            return
        }
        guard !level.dismissing else { result(nil); return }
        level.dismissing = true
        level.startupTimeout?.cancel()
        // A paused layer would never finish the dismissal animation.
        snapAfterTurn(level, duration: 0)
        let complete = { [weak self] in
            // Reply to the closing engine before destroying it.
            result(nil)
            self?.finish(level, value: value is NSNull ? nil : value)
        }
        if level.presented {
            level.controller.dismiss(animated: true, completion: complete)
        } else {
            complete()
        }
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        guard let level = levels.last,
              level.controller === presentationController.presentedViewController else { return true }
        return level.dismissible
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let level = levels.last,
              level.controller === presentationController.presentedViewController else { return }
        finish(level, value: nil)
    }

    private func failStartup(_ level: Level) {
        level.dismissing = true
        snapAfterTurn(level, duration: 0)
        let failure = FlutterError(code: "startup_timeout",
                                   message: "The sheet did not finish starting", details: level.arguments["route"])
        if level.presented {
            level.controller.dismiss(animated: false) { [weak self] in self?.finish(level, value: failure) }
        } else {
            finish(level, value: failure)
        }
    }

    private func finish(_ level: Level, value: Any?) {
        guard !level.closed, levels.last === level else { return }
        level.closed = true
        level.startupTimeout?.cancel()
        level.startupTimeout = nil
        levels.removeLast()
        flushPendingHeights()
        level.window?.isHidden = true
        (levels.last?.window ?? originalHost?.view.window)?.makeKey()
        level.completion(value)
        // Wait until both channel replies leave their callbacks. Each engine
        // tears down only its own platform views and rendering surface.
        DispatchQueue.main.async {
            level.channel.setMethodCallHandler(nil)
            level.controller.onTransition = nil
            level.controller.onLayout = nil
            level.window?.rootViewController = nil
            level.window = nil
            level.engine.viewController = nil
            level.engine.destroyContext()
        }
    }
}

private final class SheetViewController: FlutterViewController {
    var onTransition: ((UIViewControllerTransitionCoordinator) -> Void)?
    var onLayout: (() -> Void)?

    var onTurn: ((UIViewControllerTransitionCoordinator) -> Void)?

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        onTransition?(coordinator)
        onTurn?(coordinator)
        FlutterTurnPinning.pinOverlays(in: view)
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }
}

private final class SheetWindowRootController: UIViewController {
    var statusBarStyle: UIStatusBarStyle = .default
    var onTurn: ((UIViewControllerTransitionCoordinator) -> Void)?
    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        onTurn?(coordinator)
        super.viewWillTransition(to: size, with: coordinator)
    }
}
