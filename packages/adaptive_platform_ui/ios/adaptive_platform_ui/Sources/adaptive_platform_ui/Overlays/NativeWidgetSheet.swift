import Flutter
import UIKit

/// Real UIKit sheets (`UISheetPresentationController`) whose content is the
/// app's own Flutter widget. Sheets can be nested: a sheet may open another.
/// The engine only draws into the topmost, and its native views (switches,
/// sliders, segmented controls) follow it there, so a lower sheet is covered
/// by a snapshot of itself until the engine comes back.
///
/// A nested sheet is not presented by the sheet below it. When one sheet
/// presents another, UIKit tucks the lower one behind the top one and shrinks
/// it to the top sheet's height, whatever its own detents say. So each nested
/// sheet is presented from its own transparent window above the app, and the
/// sheets below keep their size, under the new sheet's dimming.
///
/// Each sheet's content is a `FlutterViewController` on the same engine. Only
/// one view controller can drive an engine at a time, so the engine renders
/// into the topmost sheet, and everything below it shows a still frame. Dart
/// draws the topmost sheet's widget as a full-window layer, in the same
/// isolate as the rest of the app, so the widget keeps its closures, its state
/// and its blocs. When a sheet goes, the engine is handed back to whatever is
/// below it: the sheet beneath, or the page.
final class NativeWidgetSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    /// One open sheet.
    private final class Level {
        let controller: FlutterViewController
        /// How this sheet rests: `fit`, `full`, `short` or `halfAndFull`.
        let detents: String
        /// Position in the stack, bottom is 0.
        let depth: Int
        /// Height of the "fit" detent: what Dart measured for the content.
        var fitHeight: CGFloat = 320
        /// Counts height changes, to name each new detent.
        var revision = 0
        /// The window a nested sheet is presented from. Nil for the bottom
        /// sheet, which the page presents.
        var window: UIWindow?
        /// A snapshot laid over this sheet while a sheet above has the engine.
        var still: UIView?
        init(controller: FlutterViewController, detents: String, depth: Int) {
            self.controller = controller
            self.detents = detents
            self.depth = depth
        }
    }

    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private weak var originalHost: FlutterViewController?
    private weak var engine: FlutterEngine?

    /// Open sheets, bottom first.
    private var levels: [Level] = []

    /// Controllers by depth. When a FlutterViewController is released, Flutter
    /// destroys an engine that may not run headless, so each is created once
    /// and kept for the life of the app, and reused.
    private var pool: [FlutterViewController] = []

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.channel = channel
        self.hostProvider = hostProvider
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "present": present(call.arguments as? [String: Any] ?? [:], result: result)
        case "setHeight": setHeight(call.arguments as? [String: Any] ?? [:], result: result)
        case "dismiss": dismiss(result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func topPresenter(from host: UIViewController) -> UIViewController? {
        var presenter: UIViewController? = host.view.window?.rootViewController
        if presenter == nil {
            presenter = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?.rootViewController
        }
        while let next = presenter?.presentedViewController { presenter = next }
        return presenter
    }

    private func present(_ args: [String: Any], result: @escaping FlutterResult) {
        let host = originalHost ?? (hostProvider() as? FlutterViewController)
        guard let host, let presenter = topPresenter(from: host), !presenter.isBeingDismissed else {
            result(FlutterError(code: "unavailable", message: "No Flutter view to present from", details: nil))
            return
        }

        let engine: FlutterEngine = host.engine
        let depth = levels.count
        if pool.count <= depth {
            pool.append(FlutterViewController(engine: engine, nibName: nil, bundle: nil))
        }
        let level = Level(controller: pool[depth], detents: args["detents"] as? String ?? "fit", depth: depth)
        level.fitHeight = CGFloat((args["height"] as? NSNumber)?.doubleValue ?? 320)

        originalHost = host
        self.engine = engine
        if let below = levels.last {
            freeze(below)
            level.window = overlayWindow(over: below.controller.view.window ?? host.view.window)
        }
        levels.append(level)
        // The new sheet's controller takes the engine.
        engine.viewController = level.controller
        presentLevel(level, over: host)
        // Answer as soon as the engine has moved into the sheet, not when the
        // slide-up finishes: Dart switches the sheet's content on at that
        // point, so the sheet never shows what it is about to cover.
        result(nil)
    }

    /// Configures and presents [level]'s sheet over whatever is on screen.
    private func presentLevel(_ level: Level, over host: FlutterViewController) {
        guard let presenter = level.window?.rootViewController ?? topPresenter(from: host) else { return }
        let controller = level.controller
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            switch level.detents {
            case "full":
                sheet.detents = [.large()]
            case "fit":
                if #available(iOS 16.0, *) {
                    // Each level needs its own name: UIKit resolves a lower sheet from the
                    // sheet above it when both use the same detent identifier.
                    // The only detent: the sheet cannot be dragged taller than
                    // its content. Content taller than the screen is capped and
                    // scrolls.
                    let fit = UISheetPresentationController.Detent.Identifier("fit\(level.depth)")
                    sheet.detents = [
                        .custom(identifier: fit) { [weak level] context in
                            min(context.maximumDetentValue, level?.fitHeight ?? 320)
                        },
                    ]
                    sheet.selectedDetentIdentifier = fit
                } else {
                    sheet.detents = [.medium(), .large()]
                }
            case "short":
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom(identifier: UISheetPresentationController.Detent.Identifier("short\(level.depth)")) {
                        context in
                        min(context.maximumDetentValue, max(context.maximumDetentValue * 0.34, 300))
                    }]
                } else {
                    sheet.detents = [.medium()]
                }
            default:
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        controller.presentationController?.delegate = self
        controller.view.backgroundColor = .systemBackground
        presenter.present(controller, animated: true)
    }

    /// A transparent window just above [below], for a nested sheet to be
    /// presented from, so UIKit does not stack it on the sheet beneath.
    private func overlayWindow(over below: UIWindow?) -> UIWindow? {
        guard let scene = below?.windowScene else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level((below?.windowLevel.rawValue ?? 0) + 1)
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.backgroundColor = .clear
        window.makeKeyAndVisible()
        return window
    }

    /// The content's height changed: resize the top sheet to it, animated.
    ///
    /// Invalidating the top sheet's detent would also resize the sheets under
    /// it, stretching their last frame. Swapping in a new detent of the new
    /// height, with a new name, moves only the top sheet.
    private func setHeight(_ args: [String: Any], result: @escaping FlutterResult) {
        defer { result(nil) }
        guard let level = levels.last,
              let height = (args["height"] as? NSNumber)?.doubleValue,
              abs(CGFloat(height) - level.fitHeight) > 0.5 else { return }
        level.fitHeight = CGFloat(height)
        guard #available(iOS 16.0, *), level.detents == "fit",
              let sheet = level.controller.sheetPresentationController else { return }
        level.revision += 1
        let fit = UISheetPresentationController.Detent.Identifier("fit\(level.depth)_\(level.revision)")
        let target = CGFloat(height)
        sheet.animateChanges {
            sheet.detents = [
                .custom(identifier: fit) { context in min(context.maximumDetentValue, target) },
            ]
            sheet.selectedDetentIdentifier = fit
        }
    }

    /// Dismisses the top sheet.
    private func dismiss(result: @escaping FlutterResult) {
        guard let level = levels.last else {
            result(nil)
            return
        }
        level.controller.dismiss(animated: true) { [weak self] in
            self?.closed(level.controller)
            result(nil)
        }
    }

    /// The user dragged a sheet away.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        closed(presentationController.presentedViewController)
        channel.invokeMethod("dismissedByUser", arguments: nil)
    }

    /// A sheet is gone: hand the engine to whatever is now on top. The sheet
    /// controllers stay alive in [pool]; releasing one would destroy the engine.
    private func closed(_ controller: UIViewController) {
        guard let index = levels.firstIndex(where: { $0.controller === controller }) else { return }
        let gone = levels[index...]
        levels.removeSubrange(index...)
        // Windows that held nested sheets go too, top first.
        for level in gone.reversed() {
            level.window?.isHidden = true
            level.window = nil
        }
        (levels.last?.window ?? originalHost?.view.window)?.makeKey()
        guard let engine, let host = originalHost else { return }

        // The engine goes back to whatever is now on top: the sheet below, or
        // the page.
        let target: FlutterViewController? = levels.last?.controller ?? host
        guard let target else { return }
        engine.viewController = target
        reattach(target)
        if let below = levels.last { thaw(below) }
    }

    /// Covers [level]'s sheet with a picture of itself, taken before the
    /// engine and its native views move to the sheet above. The picture sits
    /// over the Flutter view, not inside it: while handing over, the engine
    /// can still add its layers to the old view, on top of anything there.
    private func freeze(_ level: Level) {
        let view = level.controller.view!
        guard let container = view.superview else { return }
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let still = UIImageView(image: image)
        still.frame = view.frame
        container.insertSubview(still, aboveSubview: view)
        level.still = still
    }

    /// Removes [level]'s snapshot once the engine has drawn into the sheet
    /// again, so the sheet never flashes empty in between.
    private func thaw(_ level: Level) {
        guard let still = level.still else { return }
        level.still = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            still.removeFromSuperview()
        }
    }

    /// Re-attaches a view controller's rendering surface. FlutterViewController
    /// does this when it appears; it did not go away, so ask for it directly.
    private func reattach(_ target: FlutterViewController) {
        let selector = NSSelectorFromString("surfaceUpdated:")
        if target.responds(to: selector) {
            typealias Call = @convention(c) (AnyObject, Selector, Bool) -> Void
            let call = unsafeBitCast(target.method(for: selector), to: Call.self)
            call(target, selector, true)
        }
        target.viewWillAppear(false)
        target.viewDidAppear(false)
        target.view.setNeedsLayout()
        target.view.layoutIfNeeded()
    }
}
