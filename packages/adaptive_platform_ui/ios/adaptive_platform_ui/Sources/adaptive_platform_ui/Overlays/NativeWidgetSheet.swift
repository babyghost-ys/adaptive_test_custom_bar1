import Flutter
import IOSurface
import UIKit

/// Real UIKit sheets (`UISheetPresentationController`) whose content is the
/// app's own Flutter widget. Sheets can be nested: a sheet may open another.
/// The engine only draws into the topmost, and its native views (switches,
/// sliders, segmented controls) follow it there, so a lower sheet is covered
/// by a snapshot of itself until the engine comes back.
///
/// When the window changes size (a rotation) while a sheet is up, the top
/// sheet keeps the engine through the turn, so its content and its native
/// views follow it like any other Flutter view. The layers behind it keep
/// the last frame they drew, which UIKit stretches to the new size, so the
/// engine is lent to the page as soon as UIKit has given every view its
/// final frame, at the very start of the turn, and Dart draws the page at
/// its new size; it then goes straight back to the top sheet. The covered
/// sheets are drawn again the same way once the turn has finished animating
/// (the top sheet's transition coordinator says when). Dart keeps the top
/// sheet's widget mounted and laid out at the sheet's own size meanwhile, so
/// its native views are the same views, in the same places, when the engine
/// returns. The sheet is held under a picture of itself for the few frames
/// the engine is away, so nothing in it flickers and no touch reaches the
/// wrong layer; at the start of a turn the picture is taken before UIKit
/// moves the sheet, and turns with it.
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

    /// The page's size when the engine last drew it: as the first sheet
    /// opened, or when the covered layers were last drawn again. A size
    /// transition that ends with the page at another size calls for a redraw.
    private var drawnPageSize: CGSize?
    private var redrawing = false
    private var redrawAgain = false

    /// Size transitions of the top sheet that have started and not ended.
    private var transitionsInFlight = 0

    /// Whether the sheets under the top one still hold a frame of the size
    /// they had before a turn: the page alone is drawn as a turn starts.
    private var coveredSheetsStale = false

    /// Bumped when a sheet opens or closes, so a redraw in progress stops.
    private var stackGeneration = 0

    /// Controllers by depth. When a FlutterViewController is released, Flutter
    /// destroys an engine that may not run headless, so each is created once
    /// and kept for the life of the app, and reused.
    private var pool: [SheetViewController] = []

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
            let controller = SheetViewController(engine: engine, nibName: nil, bundle: nil)
            controller.onTransition = { [weak self] controller, coordinator in
                self?.transition(of: controller, with: coordinator)
            }
            pool.append(controller)
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
        stackGeneration += 1
        if levels.isEmpty {
            // The page was live until now, so it is drawn at this size.
            drawnPageSize = host.view.bounds.size
        }
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
    ///
    /// During a turn the new height is taken at once instead, as part of the
    /// turn: content measured at the new width (with its new safe area)
    /// reports a new height part way through it, and an animation of its own
    /// would still be resizing the sheet once the turn has ended, when the
    /// covered layers are drawn again under a picture of it.
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
        let resize = {
            sheet.detents = [
                .custom(identifier: fit) { context in min(context.maximumDetentValue, target) },
            ]
            sheet.selectedDetentIdentifier = fit
        }
        if transitionsInFlight > 0 {
            resize()
        } else {
            sheet.animateChanges(resize)
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
        stackGeneration += 1
        let gone = levels[index...]
        levels.removeSubrange(index...)
        // Windows that held nested sheets go too, top first. So does a
        // picture left over a closed sheet, which would otherwise cover
        // whatever its pooled controller shows next.
        for level in gone.reversed() {
            stills.removeValue(forKey: ObjectIdentifier(level.controller))?.removeFromSuperview()
            level.window?.isHidden = true
            level.window = nil
        }
        if levels.isEmpty {
            drawnPageSize = nil
            coveredSheetsStale = false
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
    /// touches, which would otherwise reach the engine's current layer. A
    /// picture already there is replaced in the same frame.
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
    private func thaw(_ controller: FlutterViewController, after delay: TimeInterval = 0.15) {
        guard let still = stills.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            still.removeFromSuperview()
        }
    }

    /// Moves every picture to where its layer is going, inside the turn's
    /// animation, so it turns with it. A picture taken once the turn has
    /// started would stand still at the size its layer is heading for.
    private func followTurn() {
        for controller in [originalHost] + levels.map(\.controller) {
            guard let controller, let still = stills[ObjectIdentifier(controller)] else { continue }
            still.frame = controller.view.frame
        }
    }

    // MARK: - Drawing the covered layers again after a resize

    /// A sheet's size is changing with the window's: a rotation, or the
    /// resize of a multitasking window. UIKit gives every view its final
    /// frame as the transition starts and animates towards it, so a UIKit
    /// page is laid out at its new size for the whole turn. In a rotation the
    /// page is drawn again at that point too: the top sheet is pictured
    /// before UIKit starts to move it, the picture turns with it, and the
    /// engine goes to the page and back. Otherwise, and for the covered
    /// sheets (and the page under a full-screen sheet), the layers are drawn
    /// again once the transition has ended, which the coordinator reports.
    /// Only the top sheet speaks for the stack: the sheets under it go
    /// through the same transition.
    private func transition(
        of controller: SheetViewController, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        guard levels.last?.controller === controller else { return }
        transitionsInFlight += 1
        let turning = !coordinator.targetTransform.isIdentity && !redrawing
            && originalHost.map { stills[ObjectIdentifier($0)] == nil } == true
        if turning { freeze(controller) }
        let registered = coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self, turning else { return }
            self.followTurn()
            // Once every view has its new frame.
            DispatchQueue.main.async { self.redrawPageAsTurnStarts(controller) }
        }, completion: { [weak self] _ in
            self?.transitionEnded()
        })
        if !registered {
            if turning { thaw(controller, after: 0) }
            transitionEnded()
        }
    }

    /// Draws the page at its new size while the turn has only just begun.
    private func redrawPageAsTurnStarts(_ controller: FlutterViewController) {
        guard levels.last?.controller === controller, pageIsStale else {
            return thaw(controller, after: 0)
        }
        redrawCovered(pageOnly: true)
    }

    /// Draws the covered layers again once no transition of the top sheet is
    /// still animating: a detent change that ends part way through a turn
    /// would otherwise picture the sheet while it is still moving.
    private func transitionEnded() {
        transitionsInFlight = max(0, transitionsInFlight - 1)
        guard transitionsInFlight == 0 else { return }
        redrawIfStale()
    }

    private func redrawIfStale() {
        guard pageIsStale || coveredSheetsStale else { return }
        redrawCovered()
    }

    /// Whether the page was last drawn at another size than it has now.
    private var pageIsStale: Bool {
        guard let host = originalHost, !levels.isEmpty, let drawnPageSize else { return false }
        return host.view.bounds.size != drawnPageSize
    }

    /// Lends the engine to the page and to each sheet below the top one, so
    /// Dart draws each at its current size, then gives it back to the top
    /// sheet. The top sheet is held still meanwhile: its widget stays mounted
    /// and laid out at its own size on the Dart side, so when the engine
    /// returns its native views are the same views in the same places.
    ///
    /// With [pageOnly], as a turn starts, only the page is drawn; the top
    /// sheet is already pictured, and its picture goes as soon as the sheet
    /// has drawn again, its new layout under it.
    private func redrawCovered(pageOnly: Bool = false) {
        guard let host = originalHost, let top = levels.last else { return }
        if redrawing {
            redrawAgain = true
            return
        }
        redrawing = true
        let generation = stackGeneration
        // The page, then each covered sheet, bottom first.
        let covered: [(index: Int, controller: FlutterViewController)] =
            [(-1, host)] + (pageOnly ? [] : levels.dropLast().map { ($0.depth, $0.controller) })
        coveredSheetsStale = pageOnly && levels.count > 1
        if !pageOnly { freeze(top.controller) }

        func finish() {
            redrawing = false
            if redrawAgain {
                redrawAgain = false
                // Only if this pass left the page behind the window's size.
                redrawIfStale()
            }
        }
        // A sheet opened or closed meanwhile: that already moved the engine.
        // Make Dart draw whatever is now on top, and stop. The picture held
        // over the old top goes if it is still the top; a sheet opened over
        // it replaced the picture with one of its own, which stays.
        func abandon() {
            channel.invokeMethod("drawLayer", arguments: ["index": levels.last?.depth ?? -1])
            if levels.last?.controller === top.controller { thaw(top.controller) }
            finish()
        }
        func step(_ i: Int) {
            guard generation == stackGeneration else { return abandon() }
            guard i < covered.count else {
                lend(top.controller, index: top.depth, untilShown: pageOnly) { [weak self] in
                    guard let self else { return }
                    guard generation == self.stackGeneration else { return abandon() }
                    self.thaw(top.controller, after: pageOnly ? 0 : 0.15)
                    finish()
                }
                return
            }
            let (index, controller) = covered[i]
            // A layer covered by a picture of itself (a sheet under another,
            // the page under a full-screen sheet) gets a new picture of its
            // new frame, which replaces the old one in the same frame. One
            // that was not covered stays bare: its own view now shows the
            // new frame.
            let pictured = stills[ObjectIdentifier(controller)] != nil
            lend(controller, index: index, untilShown: pageOnly) { [weak self] in
                guard let self else { return }
                guard generation == self.stackGeneration else { return abandon() }
                if index < 0 { self.drawnPageSize = host.view.bounds.size }
                if pictured { self.freeze(controller) }
                step(i + 1)
            }
        }
        step(0)
    }

    /// Gives the engine to [controller] and has Dart draw layer [index] into
    /// it: -1 for the page, otherwise the sheet at that depth. Dart answers
    /// once that layer's frame is drawn and its native views are composited.
    ///
    /// With [untilShown], during a turn, it goes on as soon as the layer
    /// shows a frame of its own size, which is well before Dart answers:
    /// every frame spent waiting is one more of the turn with a layer at its
    /// old size. The first frame to reach the layer can be the one the engine
    /// was still drawing for the layer it came from, which is of that layer's
    /// size; the layer is covered by its last frame until its own arrives.
    private func lend(
        _ controller: FlutterViewController, index: Int, untilShown: Bool = false,
        then: @escaping () -> Void
    ) {
        let view = controller.view!
        let covered = untilShown && stills[ObjectIdentifier(controller)] == nil
        if covered { cover(controller) }
        engine?.viewController = controller
        // In the first half of a turn the controller would keep its new size
        // from the engine, and the layer would be drawn at its old one.
        Self.releaseMetricsHold(controller)
        reattach(controller)
        var done = false
        let goOn = { [weak self] in
            guard !done else { return }
            done = true
            if covered { self?.thaw(controller, after: 0) }
            then()
        }
        if untilShown {
            FrameWatcher.watch(view, then: goOn)
        }
        channel.invokeMethod("drawLayer", arguments: ["index": index]) { _ in
            DispatchQueue.main.async(execute: goOn)
        }
    }

    /// Covers [controller]'s view with the frame it shows now, as [freeze]
    /// does, but by showing the same surface rather than drawing a picture of
    /// it: a picture of a Flutter view can come out as the engine's last
    /// frame for whichever view it last drew. The engine never draws into
    /// that surface again once the view has changed size, as it has in a
    /// turn.
    private func cover(_ controller: FlutterViewController) {
        let view = controller.view!
        guard let container = view.superview, let frame = view.layer.contents else { return }
        let still = UIView(frame: view.frame)
        still.layer.contents = frame
        still.layer.contentsGravity = view.layer.contentsGravity
        still.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        still.isUserInteractionEnabled = true
        container.insertSubview(still, aboveSubview: view)
        stills.removeValue(forKey: ObjectIdentifier(controller))?.removeFromSuperview()
        stills[ObjectIdentifier(controller)] = still
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

    /// Lets [target] send the engine its size during a turn.
    /// FlutterViewController holds it back for the first half of every turn,
    /// through its private `shouldIgnoreViewportMetricsUpdatesDuringRotation`,
    /// and lets it go itself half way through.
    private static func releaseMetricsHold(_ target: FlutterViewController) {
        let selector = NSSelectorFromString("setShouldIgnoreViewportMetricsUpdatesDuringRotation:")
        guard target.responds(to: selector) else { return }
        typealias Call = @convention(c) (AnyObject, Selector, Bool) -> Void
        let call = unsafeBitCast(target.method(for: selector), to: Call.self)
        call(target, selector, false)
    }

    /// Re-attaches a view controller's rendering surface. FlutterViewController
    /// does this when it appears; it did not go away, so ask for it directly.
    /// The layout pass sends the engine this view's metrics, so Dart lays
    /// out at its size.
    private func reattach(_ target: FlutterViewController) {
        Self.surfaceUpdated(target)
        target.viewWillAppear(false)
        target.viewDidAppear(false)
        target.view.setNeedsLayout()
        target.view.layoutIfNeeded()
    }
}

/// Calls back on the first display frame at which a Flutter view shows a
/// frame drawn for its own size: the engine presents a frame by setting the
/// view layer's contents to a surface of the frame's size, native views
/// included. A frame of another size is one the engine drew for another view
/// before it moved. Gives up after a second.
private final class FrameWatcher: NSObject {
    private weak var view: UIView?
    private let shown: AnyObject?
    private let then: () -> Void
    private var link: CADisplayLink?
    private let deadline = CACurrentMediaTime() + 1

    static func watch(_ view: UIView, then: @escaping () -> Void) {
        let watcher = FrameWatcher(view: view, then: then)
        let link = CADisplayLink(target: watcher, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        watcher.link = link
    }

    private init(view: UIView, then: @escaping () -> Void) {
        self.view = view
        self.shown = view.layer.contents as AnyObject?
        self.then = then
    }

    /// The display link holds the watcher until it stops.
    @objc private func tick() {
        guard let view, CACurrentMediaTime() < deadline else {
            link?.invalidate()
            return
        }
        let contents = view.layer.contents as AnyObject?
        guard contents !== shown, let contents, Self.fits(contents, view) else { return }
        link?.invalidate()
        then()
    }

    /// Whether [contents] is a frame drawn for [view] as it is now. Contents
    /// that are not a surface are taken as it.
    private static func fits(_ contents: AnyObject, _ view: UIView) -> Bool {
        guard CFGetTypeID(contents) == IOSurfaceGetTypeID() else { return true }
        let surface = unsafeBitCast(contents, to: IOSurfaceRef.self)
        let scale = view.layer.contentsScale
        return abs(CGFloat(IOSurfaceGetWidth(surface)) - view.bounds.width * scale) <= 1
            && abs(CGFloat(IOSurfaceGetHeight(surface)) - view.bounds.height * scale) <= 1
    }
}

/// A sheet's view controller: reports a size transition it takes part in (a
/// rotation), with the coordinator that says when it has finished animating.
private final class SheetViewController: FlutterViewController {
    var onTransition: ((SheetViewController, UIViewControllerTransitionCoordinator) -> Void)?

    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        onTransition?(self, coordinator)
    }
}
