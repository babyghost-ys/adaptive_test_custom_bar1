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
        var revision = 0
        var presented = false
        var ready = false
        var dismissing = false
        var closed = false
        var transitionsInFlight = 0
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
        switch args["brightness"] as? String {
        case "dark": controller.overrideUserInterfaceStyle = .dark
        case "light": controller.overrideUserInterfaceStyle = .light
        default: controller.overrideUserInterfaceStyle = .unspecified
        }
        controller.onTransition = { [weak level] coordinator in
            guard let level else { return }
            level.transitionsInFlight += 1
            let registered = coordinator.animate(alongsideTransition: nil) { [weak level] _ in
                guard let level else { return }
                level.transitionsInFlight = max(0, level.transitionsInFlight - 1)
            }
            if !registered { level.transitionsInFlight = max(0, level.transitionsInFlight - 1) }
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
        window.makeKeyAndVisible()
        presenter.present(controller, animated: true)
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
              value.isFinite, value > 0, !level.closed,
              abs(CGFloat(value) - level.fitHeight) > 0.5 else { return }
        level.fitHeight = CGFloat(value)
        if let route = level.arguments["route"] as? String { measuredHeights[route] = level.fitHeight }
        guard #available(iOS 16.0, *), level.detents == "fit", level.presented,
              let sheet = level.controller.sheetPresentationController else { return }
        level.revision += 1
        let resize = { self.setFitDetent(level, sheet: sheet) }
        if level.transitionsInFlight > 0 || level.controller.transitionCoordinator != nil {
            resize()
        } else {
            sheet.animateChanges(resize)
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
        level.window?.isHidden = true
        (levels.last?.window ?? originalHost?.view.window)?.makeKey()
        level.completion(value)
        // Wait until both channel replies leave their callbacks. Each engine
        // tears down only its own platform views and rendering surface.
        DispatchQueue.main.async {
            level.channel.setMethodCallHandler(nil)
            level.controller.onTransition = nil
            level.window?.rootViewController = nil
            level.window = nil
            level.engine.viewController = nil
            level.engine.destroyContext()
        }
    }
}

private final class SheetViewController: FlutterViewController {
    var onTransition: ((UIViewControllerTransitionCoordinator) -> Void)?

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        onTransition?(coordinator)
    }
}

private final class SheetWindowRootController: UIViewController {
    var statusBarStyle: UIStatusBarStyle = .default
    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }
}
