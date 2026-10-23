import Flutter
import UIKit

/// Real UIKit sheets (`UISheetPresentationController`) whose content is the
/// app's own Flutter widget. Sheets can be nested: a sheet may open another.
/// The engine only draws into the topmost, and its native views (switches,
/// sliders, segmented controls) follow it there, so a lower sheet is covered
/// by a snapshot of itself until the engine comes back.
///
/// When the window changes size (a rotation) while a sheet is up, those
/// snapshots, and the page's last frame, would be stretched. Once the size
/// settles, the engine is lent to the page and to each covered sheet in turn,
/// so Dart draws each again at the new size, and each is snapshotted afresh.
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
        /// How this sheet rests: `fit`, `full`, `short`, `halfAndFull`, or
        /// `fullScreen`, which covers the screen and cannot be dragged away.
        let detents: String
        /// Whether tapping outside or dragging the sheet down closes it. When
        /// false, only Dart's `dismiss` does.
        let dismissible: Bool
        /// Position in the stack, bottom is 0.
        let depth: Int
        /// Height of the "fit" detent: what Dart measured for the content.
        var fitHeight: CGFloat = 320
        /// Counts height changes, to name each new detent.
        var revision = 0
        /// The window a nested sheet is presented from. Nil for the bottom
        /// sheet, which the page presents.
        var window: UIWindow?
        init(controller: FlutterViewController, detents: String, dismissible: Bool, depth: Int) {
            self.controller = controller
            self.detents = detents
            self.dismissible = dismissible
            self.depth = depth
        }
    }

    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private weak var originalHost: FlutterViewController?

    /// The page's view controller once a sheet has been shown. The engine's
    /// own view controller is the top sheet's while one is up.
    var pageController: FlutterViewController? { originalHost }
    private weak var engine: FlutterEngine?

    /// Open sheets, bottom first.
    private var levels: [Level] = []

    /// Snapshots laid over the page or a sheet while the engine is elsewhere,
    /// by controller.
    private var stills: [ObjectIdentifier: UIView] = [:]

    /// Watches the page's size, to draw the covered layers again after it
    /// changes.
    private var resizeObserver: ResizeObserverView?
    private var pendingRedraw: DispatchWorkItem?
    private var redrawing = false
    private var redrawAgain = false

    /// Bumped when a sheet opens or closes, so a redraw in progress stops.
    private var stackGeneration = 0

    /// Controllers by depth. When a FlutterViewController is released, Flutter
    /// destroys an engine that may not run headless, so each is created once
    /// and kept for the life of the app, and reused.
    private var pool: [FlutterViewController] = []

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.channel = channel
        self.hostProvider = hostProvider
        super.init()
        for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(becameActive), name: name, object: nil
            )
        }
    }

    /// Every FlutterViewController on the engine claims the engine's native
    /// views when the app becomes active, whether or not it is the one on
    /// screen, and the last to hear of it wins. Once a nested sheet has been
    /// opened, that is a pooled controller that is not showing, and the
    /// native views of the sheet on screen vanish into it. After they have
    /// all run, hand the native views back to the engine's own controller.
    @objc private func becameActive() {
        guard !pool.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let current = self?.engine?.viewController else { return }
            Self.surfaceUpdated(current)
        }
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
        let level = Level(
            controller: pool[depth],
            detents: args["detents"] as? String ?? "fit",
            dismissible: args["dismissible"] as? Bool ?? true,
            depth: depth
        )
        level.fitHeight = CGFloat((args["height"] as? NSNumber)?.doubleValue ?? 320)

        originalHost = host
        self.engine = engine
        observeSize(of: host)
        stackGeneration += 1
        if let below = levels.last {
            freeze(below.controller)
            level.window = overlayWindow(over: below.controller.view.window ?? host.view.window)
        } else if level.detents == "fullScreen" {
            // A full-screen sheet slides over the page undimmed, so the page
            // must keep looking as it did: once the engine leaves, the
            // Flutter layers drawn above its native views (a drawer's dim
            // over the bars, say) go with it.
            freeze(host)
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
        if level.detents == "fullScreen" {
            // No grabber, no drag-to-dismiss: Dart closes it with `dismiss`.
            // Over, not instead of, the page: `.fullScreen` takes the page's
            // views out of the window and puts them back on top of anything
            // laid over it there, such as a drawer's dimmed backdrop.
            controller.modalPresentationStyle = .overFullScreen
            controller.modalPresentationCapturesStatusBarAppearance = true
            controller.isModalInPresentation = true
            controller.view.backgroundColor = .systemBackground
            presenter.present(controller, animated: true)
            return
        }
        controller.modalPresentationStyle = .pageSheet
        controller.modalPresentationCapturesStatusBarAppearance = false
        // UIKit cannot stop a tap outside without also stopping the drag, so a
        // sheet that is not dismissible keeps still and drops its grabber.
        controller.isModalInPresentation = !level.dismissible
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
            sheet.prefersGrabberVisible = level.dismissible
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            // In landscape on an iPhone a sheet would otherwise span the
            // whole screen, leaving nothing outside it to tap and no grabber.
            // Attached to the bottom edge it keeps its portrait width, with
            // the dimmed page on either side.
            sheet.prefersEdgeAttachedInCompactHeight = true
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

    /// The content's height changed: resize the sheet to it, animated. The
    /// sheet is the one at `depth`, or the top one.
    ///
    /// Invalidating the top sheet's detent would also resize the sheets under
    /// it, stretching their last frame. Swapping in a new detent of the new
    /// height, with a new name, moves only the top sheet.
    private func setHeight(_ args: [String: Any], result: @escaping FlutterResult) {
        defer { result(nil) }
        let depth = (args["depth"] as? NSNumber)?.intValue
        guard let level = depth.flatMap({ d in levels.first { $0.depth == d } }) ?? levels.last,
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
        stackGeneration += 1
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
        thaw(target)
    }

    /// Covers [controller]'s view with a picture of itself, taken before the
    /// engine and its native views move elsewhere. The picture sits over the
    /// Flutter view, not inside it: while handing over, the engine can still
    /// add its layers to the old view, on top of anything there. It takes the
    /// touches, which would otherwise reach the engine's current layer.
    private func freeze(_ controller: FlutterViewController) {
        let view = controller.view!
        guard let container = view.superview else { return }
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let still = UIImageView(image: image)
        still.frame = view.frame
        still.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        still.isUserInteractionEnabled = true
        container.insertSubview(still, aboveSubview: view)
        stills.removeValue(forKey: ObjectIdentifier(controller))?.removeFromSuperview()
        stills[ObjectIdentifier(controller)] = still
    }

    /// Removes [controller]'s snapshot once the engine has drawn into it
    /// again, so it never flashes empty in between.
    private func thaw(_ controller: FlutterViewController) {
        guard let still = stills.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            still.removeFromSuperview()
        }
    }

    /// Starts watching the page's size, once.
    private func observeSize(of host: FlutterViewController) {
        guard resizeObserver == nil else { return }
        let view = ResizeObserverView(frame: host.view.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onResize = { [weak self] in self?.sizeChanged() }
        host.view.insertSubview(view, at: 0)
        resizeObserver = view
    }

    /// Draws the covered layers again once the size has settled: a rotation
    /// resizes the window at its start and animates for a while after.
    private func sizeChanged() {
        pendingRedraw?.cancel()
        guard !levels.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in self?.redrawCovered() }
        pendingRedraw = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Lends the engine to the page and to each sheet below the top one, so
    /// Dart draws each at the window's current size, and snapshots each.
    /// The top sheet is held still meanwhile, then gets the engine back.
    private func redrawCovered() {
        guard let host = originalHost, let top = levels.last else { return }
        if redrawing {
            redrawAgain = true
            return
        }
        redrawing = true
        let generation = stackGeneration
        let covered = [(-1, host)] + levels.dropLast().map { ($0.depth, $0.controller) }
        freeze(top.controller)

        func finish() {
            redrawing = false
            if redrawAgain {
                redrawAgain = false
                redrawCovered()
            }
        }
        // A sheet opened or closed meanwhile: that already moved the engine.
        // Make Dart draw whatever is now on top, and stop.
        func abandon() {
            channel.invokeMethod("drawLayer", arguments: ["index": levels.last?.depth ?? -1])
            finish()
        }
        func step(_ i: Int) {
            guard generation == stackGeneration else { return abandon() }
            guard i < covered.count else {
                lend(top.controller, index: top.depth) { [weak self] in
                    guard let self else { return }
                    guard generation == self.stackGeneration else { return abandon() }
                    self.thaw(top.controller)
                    finish()
                }
                return
            }
            let (index, controller) = covered[i]
            stills.removeValue(forKey: ObjectIdentifier(controller))?.removeFromSuperview()
            lend(controller, index: index) { [weak self] in
                guard let self else { return }
                guard generation == self.stackGeneration else { return abandon() }
                self.freeze(controller)
                step(i + 1)
            }
        }
        step(0)
    }

    /// Gives the engine to [controller] and has Dart draw layer [index] into
    /// it: -1 for the page, otherwise the sheet at that depth.
    private func lend(
        _ controller: FlutterViewController, index: Int, then: @escaping () -> Void
    ) {
        engine?.viewController = controller
        reattach(controller)
        channel.invokeMethod("drawLayer", arguments: ["index": index]) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: then)
        }
    }

    /// Makes [target] the engine's surface and the home of its native views,
    /// through FlutterViewController's private `surfaceUpdated:`.
    private static func surfaceUpdated(_ target: FlutterViewController) {
        let selector = NSSelectorFromString("surfaceUpdated:")
        guard target.responds(to: selector) else { return }
        typealias Call = @convention(c) (AnyObject, Selector, Bool) -> Void
        let call = unsafeBitCast(target.method(for: selector), to: Call.self)
        call(target, selector, true)
    }

    /// Re-attaches a view controller's rendering surface. FlutterViewController
    /// does this when it appears; it did not go away, so ask for it directly.
    private func reattach(_ target: FlutterViewController) {
        Self.surfaceUpdated(target)
        target.viewWillAppear(false)
        target.viewDidAppear(false)
        target.view.setNeedsLayout()
        target.view.layoutIfNeeded()
    }
}

/// Draws nothing and takes no touches; reports when the view it fills changes
/// size.
private final class ResizeObserverView: UIView {
    var onResize: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        let first = lastSize == .zero
        lastSize = bounds.size
        if !first { onResize?() }
    }
}
