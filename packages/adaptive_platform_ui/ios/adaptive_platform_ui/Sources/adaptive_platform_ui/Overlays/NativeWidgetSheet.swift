import CoreMotion
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
    private var turnReveal: DispatchWorkItem?
    private var orientationObserver: NSObjectProtocol?
    private let motion = CMMotionManager()
    private var gravity: CMAcceleration?
    private var poseHideStart: Date?
    private var poseHideSuppressed = false
    private var geometryObservation: NSKeyValueObservation?

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
        let window = SheetWindow(windowScene: scene)
        window.onWidthChange = { [weak self] in self?.hideForTurn() }
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
        controller.onTurn = { [weak self] coordinator in
            self?.hideForTurn(until: coordinator)
        }
        root.onTurn = { [weak self] coordinator in
            self?.hideForTurn(until: coordinator)
        }
        root.onWidthChange = { [weak self] in self?.hideForTurn() }
        watchTurns(in: scene)
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
            controller.isModalInPresentation = !level.dismissible
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

    // MARK: Hiding the sheets while the screen turns

    /// How long the sheets take to come back once the turn has finished.
    private static let returnDuration: TimeInterval = 0.2

    /// How long after the last turn signal the sheets come back when no
    /// transition coordinator reported the end of the turn.
    private static let turnFallback: TimeInterval = 0.6

    /// How long the sheets stay hidden for a pose that announces a turn which
    /// never comes (orientation lock, a pose UIKit does not turn to).
    private static let poseHideLimit: TimeInterval = 1.5

    /// A landscape interface hides its sheets once the phone has tilted this
    /// far towards portrait, measured from the landscape axis. UIKit turns at
    /// about 45 degrees, and only after the pose has held for a moment, so
    /// the hide reaches the render server before the picture is taken.
    private static let poseHideTilt: Double = 30

    /// The pose has returned to the landscape axis past this tilt.
    private static let poseRestoredTilt: Double = 60

    /// The view UIKit animates for a level: the drop-shadow container that
    /// holds the content, corners and grabber, or the content view alone.
    private func sheetView(of level: Level) -> UIView {
        level.controller.presentationController?.presentedView ?? level.controller.view
    }

    /// On iOS 26+ a rotation lays a picture of the old screen over the new
    /// layout and fades it. A partial sheet changes region during the turn
    /// (compact height only offers the large detent), so the picture's edge
    /// cut across it. With every sheet gone for the turn only the page lies
    /// under the picture, which turns clean; the sheets come back once the
    /// turn has finished, as Apple's own sheets do.
    ///
    /// The picture is taken by the render server as the turn begins, before
    /// anything in the process runs, so it always holds whatever was on
    /// screen. Portrait to landscape clips the partial sheet out of it (only
    /// the top 402 pt square of the old screen is kept), so hiding from the
    /// window's frame setter is early enough there. Landscape to portrait
    /// keeps the left half of the full-height landscape sheet, so the sheet
    /// must already be gone when the turn begins: the accelerometer reports
    /// the phone tilting towards portrait before UIKit turns, and
    /// [poseChanged] hides from there.
    ///
    /// The turn is signalled from several places, since each may be the first
    /// or the only one to run: the window's frame, both controllers in every
    /// sheet window, the device orientation, and the scene's geometry. Repeats
    /// are harmless.
    private func hideForTurn(until coordinator: UIViewControllerTransitionCoordinator? = nil) {
        guard levels.contains(where: { $0.presented && !$0.closed }) else { return }
        turnReveal?.cancel()
        for level in levels where level.presented && !level.closed {
            let view = sheetView(of: level)
            view.layer.removeAllAnimations()
            view.alpha = 0
            view.isHidden = true
        }
        // Commit now rather than at the end of the run loop turn, so the hide
        // is on its way to the render server at once.
        CATransaction.flush()
        let reveal = DispatchWorkItem { [weak self] in self?.revealAfterTurn() }
        turnReveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.turnFallback, execute: reveal)
        coordinator?.animate(alongsideTransition: nil) { [weak self] _ in
            self?.revealAfterTurn()
        }
    }

    private func revealAfterTurn() {
        turnReveal?.cancel()
        turnReveal = nil
        poseHideStart = nil
        for level in levels where level.presented && !level.closed {
            let view = sheetView(of: level)
            guard view.isHidden else { continue }
            view.isHidden = false
            UIView.animate(withDuration: Self.returnDuration) { view.alpha = 1 }
        }
    }

    private func watchTurns(in scene: UIWindowScene) {
        if motion.isAccelerometerAvailable, !motion.isAccelerometerActive {
            gravity = nil
            poseHideStart = nil
            poseHideSuppressed = false
            motion.accelerometerUpdateInterval = 1.0 / 60
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.poseChanged(data.acceleration)
            }
        }
        if orientationObserver == nil {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.deviceOrientationChanged()
            }
        }
        if #available(iOS 16.0, *), geometryObservation == nil {
            // Fires as the scene takes its new size, inside UIKit's layout.
            geometryObservation = scene.observe(\.effectiveGeometry, options: [.old, .new]) {
                [weak self] _, change in
                guard let old = change.oldValue, let new = change.newValue,
                      old.interfaceOrientation != new.interfaceOrientation else { return }
                self?.hideForTurn()
            }
        }
    }

    private func stopWatchingTurns() {
        turnReveal?.cancel()
        turnReveal = nil
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        gravity = nil
        poseHideStart = nil
        geometryObservation = nil
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    /// The phone is tilting away from the landscape the interface shows, so a
    /// turn to portrait is about to follow. Hide before it begins, so the
    /// picture UIKit takes of the old screen holds the page alone. Portrait
    /// needs no early hide (see [hideForTurn]), and hiding there would blink
    /// the sheet for anyone with the orientation lock on.
    ///
    /// The sheets stay hidden while the pose holds, up to [poseHideLimit];
    /// if no turn has come by then they come back and stay until the pose has
    /// returned to the landscape axis.
    private func poseChanged(_ raw: CMAcceleration) {
        var g = raw
        if let last = gravity {
            g = CMAcceleration(x: last.x * 0.6 + raw.x * 0.4,
                               y: last.y * 0.6 + raw.y * 0.4,
                               z: last.z * 0.6 + raw.z * 0.4)
        }
        gravity = g
        // Lying flat, the pose says nothing about a turn.
        guard hypot(g.x, g.y) > 0.4,
              levels.contains(where: { $0.presented && !$0.closed }),
              let scene = levels.last?.window?.windowScene else { return }
        // 0 along the portrait axis, 90 along the landscape axis.
        let tilt = atan2(abs(g.x), abs(g.y)) * 180 / .pi
        guard scene.interfaceOrientation.isLandscape else {
            poseHideSuppressed = false
            return
        }
        if poseHideSuppressed {
            if tilt > Self.poseRestoredTilt { poseHideSuppressed = false }
            return
        }
        guard tilt < Self.poseHideTilt else { return }
        let now = Date()
        if let start = poseHideStart, now.timeIntervalSince(start) > Self.poseHideLimit {
            poseHideSuppressed = true
            revealAfterTurn()
            return
        }
        if poseHideStart == nil { poseHideStart = now }
        hideForTurn()
    }

    /// The device has turned to a portrait or landscape pose the interface
    /// does not show yet, so a turn of the interface is about to follow.
    private func deviceOrientationChanged() {
        let device = UIDevice.current.orientation
        guard device.isPortrait || device.isLandscape,
              let scene = levels.last?.window?.windowScene else { return }
        if device.isLandscape != scene.interfaceOrientation.isLandscape {
            hideForTurn()
        }
    }

    private func dismiss(_ source: Level?, value: Any?, result: @escaping FlutterResult) {
        guard let level = source, level === levels.last else {
            result(FlutterError(code: "inactive", message: "Only the active sheet can dismiss itself", details: nil))
            return
        }
        guard !level.dismissing else { result(nil); return }
        level.dismissing = true
        level.startupTimeout?.cancel()
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

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let level = levels.last,
              level.controller === presentationController.presentedViewController else { return }
        finish(level, value: nil)
    }

    private func failStartup(_ level: Level) {
        level.dismissing = true
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
        if levels.isEmpty { stopWatchingTurns() }
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
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }
}

/// The sheet's window. A turn reaches the window's frame before any layout
/// pass or controller callback, so this is the earliest point in the process
/// at which the sheets can be hidden. Only the width changes with a turn; a
/// detent change leaves the window alone.
private final class SheetWindow: UIWindow {
    var onWidthChange: (() -> Void)?

    override var frame: CGRect {
        didSet { if frame.width != oldValue.width { onWidthChange?() } }
    }

    override var bounds: CGRect {
        didSet { if bounds.width != oldValue.width { onWidthChange?() } }
    }
}

private final class SheetWindowRootController: UIViewController {
    var statusBarStyle: UIStatusBarStyle = .default
    var onTurn: ((UIViewControllerTransitionCoordinator) -> Void)?
    var onWidthChange: (() -> Void)?
    private var laidOutWidth: CGFloat?
    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        if let laidOutWidth, laidOutWidth != width { onWidthChange?() }
        laidOutWidth = width
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        onTurn?(coordinator)
        super.viewWillTransition(to: size, with: coordinator)
    }
}
