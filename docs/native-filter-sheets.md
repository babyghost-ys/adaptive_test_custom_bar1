# Building the native filter sheet, nested sheets included

Instructions for an AI agent adding a native filter sheet to a Flutter app that uses
`adaptive_platform_ui`, the way this repository does. Assume the package has no native
sheet support yet: you add all of it here. The app passes one plain Flutter `Widget`; the
package decides how to present it and how tall to make it. A sheet's widget can open a
second sheet on top of itself (a nested sheet), and both stay real UIKit sheets.

Follow the steps in order. Every code listing is complete and is the file as it is in this
repository, so it can be copied as is.

## What you are building

```dart
final result = await AdaptiveNativeSheet.show<MyFilter>(
  context: context,
  builder: (_) => MyFilterContent(draft: draft),
);
```

* **iOS:** a real UIKit sheet (`UISheetPresentationController`). It floats above the
  whole window, so it covers the navigation bar, the tab bar and the iPhone Duo vertical
  bar. UIKit owns the grabber, the dimming, the corners and drag to dismiss.
* **Android and other platforms:** a Material bottom sheet showing the same widget.
* **The widget** is ordinary Flutter. It can be a `StatelessWidget`, close over anything,
  read the app's state (a bloc, a provider, a notifier), and contain the package's native
  controls (`AdaptiveSegmentedControl`, `AdaptiveSlider`, `AdaptiveSwitch`,
  `AdaptiveInlineDatePicker`). Those render as real UIKit views inside the sheet.
* **The height** follows the widget. The package measures it. When the content grows
  (an expanding section) the sheet animates taller. Past the screen height it is capped
  and the content scrolls. Dragging up stretches the sheet and it springs back; it never
  stays taller than its content. The app passes no height.
* **Nested sheets:** from inside a sheet's widget, call `AdaptiveNativeSheet.show` again.
  The new sheet opens on top; the one below keeps its full height and its controls, under
  the new sheet's dimming. Each sheet has its own result.
* **Closing:** call `AdaptiveNativeSheet.pop(context, value)` from inside the widget. It
  closes the top sheet. Dragging a sheet away returns `null`.
* **Not dismissible:** pass `isDismissible: false` to `show` when tapping outside must not
  close the sheet. The widget then needs its own close control (a close icon calling
  `pop`). On iOS the sheet also cannot be dragged away and shows no grabber, because UIKit
  blocks both together (`isModalInPresentation`). Off iOS the drag and the drag handle go
  too. The default, `true`, keeps tapping outside and dragging away.

```dart
// Inside a sheet's widget: open a second sheet, then use its result.
Future<void> _pickAccounts(BuildContext context) async {
  final picked = await showAccountsSheet(context, draft.value.accounts);
  if (picked != null) draft.value = draft.value.copyWith(accounts: picked);
}
```

## How it works

A UIKit sheet cannot contain Flutter widgets by itself, and one `FlutterEngine` can render
into only one `FlutterViewController` at a time. So:

1. **Present.** Dart asks the plugin to present. Swift takes a `FlutterViewController` for
   the engine from a pool (one per depth, created once and never released), makes it the
   engine's view controller, and presents it as a `.pageSheet`. The engine now renders
   into the sheet.
2. **Draw.** Dart adds the caller's widget to a stack and points
   `AdaptiveNativeSheet.active` at it. `AdaptiveNativeSheetLayer`, mounted in the toolbar
   host above everything, draws that widget over the whole window, which on iOS is the
   sheet. It is the same widget tree and isolate as the app, so closures, state and blocs
   work.
3. **Fit.** Dart measures the widget and sends its height (`setHeight`). Swift swaps in a
   custom detent of that height, animated.
4. **Nest.** A second `show` repeats this one level up, with two differences. The sheet
   below is first covered with a bitmap of itself, because the engine and its native
   controls are about to leave it. The new sheet is presented from its own transparent
   window, not by the sheet below, because UIKit shrinks a presenting sheet to the
   height of the sheet it presents.
5. **Close.** The top sheet is dismissed, the engine goes back to whatever is now on top
   (the sheet below, or the page), and that one's bitmap is removed once it has drawn.
6. **Resize.** If the window changes size while a sheet is up (a rotation), everything
   under the top sheet is a stale frame, stretched to the new size. The top sheet keeps the
   engine through the turn. When its transition coordinator reports the turn's animation
   finished, Swift lends the engine to the page and to each covered sheet in turn, Dart
   draws each at its new size (`drawLayer`), and the top sheet gets the engine back. The
   top sheet's widget stays mounted and laid out at its own size meanwhile, held under a
   bitmap of itself, so its native controls are the same views in the same places when the
   engine returns. A covered sheet that had a bitmap gets a new one of its new frame; the
   page under a plain sheet keeps its own view, which now holds the right frame.

```
page
  |  AdaptiveNativeSheet.show(builder: widget)          (again from a sheet: nested)
  v
AdaptiveNativeSheet (Dart)  -- stack of entries, active = top
  |-- iOS ----> MethodChannel "adaptive_platform_ui/widget_sheet"
  |               present {detents, height,  --> NativeWidgetSheet.swift
  |                        dismissible}
  |                                               freezes the sheet below (bitmap)
  |                                               presents a pooled FlutterViewController,
  |                                               from an overlay window when nested
  |               setHeight {height, depth}  --> swaps that sheet's "fit" detent
  |               dismiss                    --> dismisses the top sheet, hands the
  |                                               engine back, unfreezes the one below
  |               <-- dismissedByUser          (dragged away)
  |               <-- drawLayer {index}        (after a resize: draw the page, -1,
  |                                               or the sheet at index, then answer)
  |   active.value = entry  -->  AdaptiveNativeSheetLayer (in AdaptiveToolbarHost)
  |   drawn.value = entry        keeps the top sheet's widget mounted and paints
  |                              the one the engine draws over the whole window
  '-- other ---> showModalBottomSheet(builder)  (Flutter, same widget)
```

## Build steps

1. Add the Swift presenter to the package.
2. Register its channel in the plugin, and point the Duo title band at the page.
3. Make the Duo vertical bar events carry the view size.
4. Add the Dart API and export it.
5. Add the `fit` detent value.
6. Mount the layer in the toolbar host.
7. In the app, write the sheet's widgets (one of them nested) and open them from a page.
8. Verify on iOS (iPhone and iPhone Duo) and Android.

## Step 1: the Swift presenter

Create this file. It presents and nests sheets, keeps covered sheets frozen, hands the
engine back on close, reclaims native views after the app becomes active, and redraws
covered layers after the window resizes.

```swift
// packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift
import Flutter
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
/// the last frame they drew, which UIKit stretches to the new size. Once the
/// turn has finished animating and every view has its final frame (the top
/// sheet's transition coordinator says when), the engine is lent to the page
/// and to each covered sheet in turn, so Dart draws each at its new size,
/// and is then handed back to the top sheet. Dart keeps the top sheet's
/// widget mounted and laid out at the sheet's own size meanwhile, so its
/// native views are the same views, in the same places, when the engine
/// returns. The sheet is held under a picture of itself for the few frames
/// the engine is away, so nothing in it flickers and no touch reaches the
/// wrong layer.
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
        if levels.isEmpty { drawnPageSize = nil }
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
    private func thaw(_ controller: FlutterViewController) {
        guard let still = stills.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            still.removeFromSuperview()
        }
    }

    // MARK: - Drawing the covered layers again after a resize

    /// A sheet's size is changing with the window's: a rotation, or the
    /// resize of a multitasking window. UIKit gives every view its final
    /// frame as the transition starts and animates towards it for a while;
    /// the covered layers are drawn again once that animation has ended,
    /// which the coordinator reports. (Drawn from a timer instead, they were
    /// caught mid-animation.) Only the top sheet speaks for the stack: the
    /// sheets under it go through the same transition. A sheet whose detent
    /// changes passes through here too, with the page the same size as
    /// before, and nothing is drawn.
    private func transition(
        of controller: SheetViewController, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        guard levels.last?.controller === controller else { return }
        let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.transitionEnded()
        }
        if !registered { transitionEnded() }
    }

    private func transitionEnded() {
        guard let host = originalHost, !levels.isEmpty,
              let drawnPageSize, host.view.bounds.size != drawnPageSize else { return }
        redrawCovered()
    }

    /// Lends the engine to the page and to each sheet below the top one, so
    /// Dart draws each at its current size, then gives it back to the top
    /// sheet. The top sheet is held still meanwhile: its widget stays mounted
    /// and laid out at its own size on the Dart side, so when the engine
    /// returns its native views are the same views in the same places.
    private func redrawCovered() {
        guard let host = originalHost, let top = levels.last else { return }
        if redrawing {
            redrawAgain = true
            return
        }
        redrawing = true
        let generation = stackGeneration
        // The page, then each covered sheet, bottom first.
        let covered: [(index: Int, controller: FlutterViewController)] =
            [(-1, host)] + levels.dropLast().map { ($0.depth, $0.controller) }
        freeze(top.controller)

        func finish() {
            redrawing = false
            if redrawAgain {
                redrawAgain = false
                redrawCovered()
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
                lend(top.controller, index: top.depth) { [weak self] in
                    guard let self else { return }
                    guard generation == self.stackGeneration else { return abandon() }
                    self.thaw(top.controller)
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
            lend(controller, index: index) { [weak self] in
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
    private func lend(
        _ controller: FlutterViewController, index: Int, then: @escaping () -> Void
    ) {
        engine?.viewController = controller
        reattach(controller)
        channel.invokeMethod("drawLayer", arguments: ["index": index]) { _ in
            DispatchQueue.main.async(execute: then)
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
```

## Step 2: register the channel, and measure the Duo title band in the page

In `register(with:)` of
`packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Plugin/AdaptivePlatformUiPlugin.swift`,
add the sheet channel:

```swift
        let widgetSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/widget_sheet", binaryMessenger: registrar.messenger())
        let widgetSheets = NativeWidgetSheet(
            channel: widgetSheetChannel, hostProvider: { registrar.viewController })
        widgetSheetChannel.setMethodCallHandler { call, result in
            widgetSheets.handle(call, result: result)
        }
```

`registrar.viewController` is the engine's *current* view controller. While a sheet is up
that is the sheet, not the page. Anything that measures the page's layout must therefore
ask for the page instead. The iPhone Duo title band does: create it after `widgetSheets`,
with a host provider:

```swift
        // iPhone Duo: where UIKit lays out a navigation title in this window
        // Measured in the page's view controller: while a native sheet is up,
        // the engine's own is the sheet.
        let titleBand = DuoTitleBand(
            hostProvider: { widgetSheets.pageController ?? registrar.viewController })
```

and give `DuoTitleBand` that provider in place of the registrar:

```swift
// packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Duo/DuoTitleBand.swift
import Flutter
import UIKit

/// Measures where UIKit lays out a navigation bar's title for this window, so
/// the Flutter-drawn iPhone Duo title band follows the system instead of
/// assumed sizes. A hidden navigation controller is laid out under the app's
/// view controller, which gives it the window's traits (the vertical bar edge
/// among them), then removed again. Nothing is shown on screen.
final class DuoTitleBand {
    /// The page's view controller, whose window the band belongs to.
    private let hostProvider: () -> UIViewController?

    init(hostProvider: @escaping () -> UIViewController?) {
        self.hostProvider = hostProvider
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "measure" else {
            result(FlutterMethodNotImplemented)
            return
        }
        result(measure())
    }

    /// `contentTop`: where UIKit starts the page content below the bar.
    /// `largeTitleMidY` / `inlineTitleMidY`: vertical centre of each title.
    /// `titleMinX`: leading edge of the title. Positions are in points, in the
    /// Flutter view's coordinates. `…FontSize` / `…FontWeight`: the type of
    /// each title, the weight as the index of the nearest `UIFont.Weight`
    /// from ultra light to black. Nil when the view is not in a window yet.
    private func measure() -> [String: Double]? {
        guard let host = hostProvider(), host.view.window != nil else { return nil }
        guard let large = layout(in: host, large: true),
              let inline = layout(in: host, large: false) else { return nil }
        return [
            "contentTop": Double(large.contentTop),
            "largeTitleMidY": Double(large.title.midY),
            "inlineTitleMidY": Double(inline.title.midY),
            "titleMinX": Double(large.title.minX),
            "largeTitleFontSize": Double(large.font.pointSize),
            "largeTitleFontWeight": Double(Self.weightIndex(of: large.font)),
            "inlineTitleFontSize": Double(inline.font.pointSize),
            "inlineTitleFontWeight": Double(Self.weightIndex(of: inline.font)),
        ]
    }

    private func layout(
        in host: UIViewController, large: Bool
    ) -> (contentTop: CGFloat, title: CGRect, font: UIFont)? {
        let marker = "Title"
        let page = UIViewController()
        page.title = marker
        page.navigationItem.largeTitleDisplayMode = large ? .always : .never
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = large
        navigation.view.isHidden = true
        navigation.view.isUserInteractionEnabled = false
        navigation.view.accessibilityElementsHidden = true
        navigation.view.frame = host.view.bounds

        host.addChild(navigation)
        host.view.insertSubview(navigation.view, at: 0)
        navigation.didMove(toParent: host)
        navigation.view.setNeedsLayout()
        navigation.view.layoutIfNeeded()

        let contentTop = page.view.convert(
            CGPoint(x: 0, y: page.view.safeAreaInsets.top), to: host.view
        ).y
        let label = Self.titleLabel(in: navigation.view, text: marker)
        let title = label.map { $0.convert($0.bounds, to: host.view) }

        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
        guard let title, let font = label?.font, contentTop > 0 else { return nil }
        return (contentTop, title, font)
    }

    private static let weights: [UIFont.Weight] = [
        .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
    ]

    /// Index in [weights] of the weight nearest to the font's.
    private static func weightIndex(of font: UIFont) -> Int {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let raw = (traits?[.weight] as? NSNumber).map { CGFloat($0.doubleValue) }
            ?? UIFont.Weight.regular.rawValue
        let distances = weights.map { abs($0.rawValue - raw) }
        return distances.firstIndex(of: distances.min()!) ?? weights.firstIndex(of: .regular)!
    }

    /// The label UIKit shows the title in: of the labels carrying it, the
    /// visible one with the largest font (large and inline labels coexist).
    private static func titleLabel(in view: UIView, text: String) -> UILabel? {
        var best: UILabel?
        func visit(_ view: UIView) {
            if let label = view as? UILabel,
               label.text == text || label.attributedText?.string == text,
               !label.isHidden, label.alpha > 0, !label.bounds.isEmpty,
               label.font.pointSize > (best?.font.pointSize ?? 0) {
                best = label
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best
    }
}
```

## Step 3: Duo vertical bar events carry the view size

In `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Duo/VerticalBarEdgeStreamHandler.swift`,
`send` must include the view's size. Dart re-measures the title band on each event, and
events that equal the last one are dropped. Without the size, a rotation can end with no
event at the final size, and the band keeps a reading taken mid-rotation (a gap above the
page content).

```swift
    private func send(_ edge: String, view: UIView? = nil) {
        // The size is part of the payload so a rotation always ends with an
        // event once the view reaches its final size. Dart measures the title
        // band on each event, and the trait change that flips the edge can
        // arrive while the view still has the previous orientation's size.
        let payload: NSDictionary = [
            "edge": edge,
            "regions": view.map(Self.occlusions) ?? [],
            "width": Double(view?.bounds.width ?? 0),
            "height": Double(view?.bounds.height ?? 0),
        ]
        guard lastSent == nil || !payload.isEqual(lastSent!) else { return }
        lastSent = payload
        sink?(payload)
    }
```

## Step 4: the Dart API

Create this file. It holds `AdaptiveNativeSheet` (`show`, `pop`, `active`), the entry
type, the layer that draws the top sheet's widget, and the widget that measures it.

````dart
// packages/adaptive_platform_ui/lib/src/overlays/native_sheet/adaptive_native_sheet.dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialPageRoute, PopScope, showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../../devices/duo/duo_layout.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A real UIKit sheet (`UISheetPresentationController`) that shows your own
/// widget.
///
/// On iOS the sheet is native: it floats above the whole window, so it covers
/// the navigation bar and tab bar, and it has native detents, grabber, dimming
/// and drag-to-dismiss. Its content is [builder]'s widget, drawn by Flutter
/// inside the sheet, in the same isolate as the rest of the app. The widget
/// can be a `StatelessWidget`, close over anything, and read the app's state
/// (a bloc, a provider, a notifier) as it would anywhere else.
///
/// A sheet can open another on top of itself: call [show] again from the
/// sheet's widget. Each sheet has its own result and its own [pop].
///
/// The widget is not a route. The page behind the sheet stays the current
/// route, so its navigation bar and toolbar stay in place.
///
/// ```dart
/// final result = await AdaptiveNativeSheet.show<MyFilter>(
///   context: context,
///   builder: (_) => MyWidget(),
/// );
/// ```
///
/// The sheet's height follows the widget's height. Close it from inside with
/// [pop], not `Navigator.pop`.
///
/// Where [AdaptiveStyle] is material, the same widget is shown in a Material
/// bottom sheet.
class AdaptiveNativeSheet {
  AdaptiveNativeSheet._();
  static const _channel = MethodChannel('adaptive_platform_ui/widget_sheet');

  /// The topmost native sheet, or null.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> active =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// The sheet the engine draws into right now, or null while it draws the
  /// page. On iOS the engine renders into one view at a time: the topmost
  /// sheet while any is up, so this is [active], except while the native
  /// side has the engine draw a covered layer again after the window changed
  /// size (`drawLayer`). `AdaptiveToolbarHost` paints that sheet's widget
  /// over the whole window, which is then that sheet.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> drawn =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// Open native sheets, bottom first. A sheet can open another on top of
  /// itself by calling [show] again from its own widget.
  static final List<AdaptiveNativeSheetEntry> _stack = [];

  static bool _handlerInstalled = false;

  /// One handler for the whole stack.
  ///
  /// `dismissedByUser`: the user dragged the top sheet away, so it is already
  /// gone.
  ///
  /// `drawLayer`: the window changed size while a sheet was up, so what the
  /// engine was not drawing (the page, any sheet under the top one) is a
  /// stale frame. The native side lends the engine to each such layer in
  /// turn (the page at index -1, then each covered sheet by index) and
  /// finally gives it back to the top sheet, which stays mounted throughout.
  /// Answers once that layer's frame, native views included, is on screen.
  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dismissedByUser':
          if (_stack.isNotEmpty) _finish(_stack.last, null);
        case 'drawLayer':
          final index = (call.arguments as Map?)?['index'] as int? ?? -1;
          drawn.value = index < 0
              ? null
              : index < _stack.length
              ? _stack[index]
              : _stack.lastOrNull;
          await _settled();
      }
      return null;
    });
  }

  /// Completes once the engine has drawn the current layer and composited
  /// its native views: a frame, a pause for the raster thread and the
  /// platform views to catch up, then one more frame.
  static Future<void> _settled() async {
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Removes [entry] from the stack and completes its result. The sheet below,
  /// if any, becomes the one drawn.
  static void _finish(AdaptiveNativeSheetEntry entry, Object? value) {
    _stack.remove(entry);
    active.value = _stack.lastOrNull;
    drawn.value = _stack.lastOrNull;
    entry.complete(value);
  }

  /// True while the engine draws a native sheet. Chrome the app paints over
  /// its pages (such as the Duo bar strip) must not draw then: the window the
  /// engine draws into is the sheet.
  static bool get isShowingNow => drawn.value != null;

  /// Shows [builder]'s widget in the sheet. Returns the value passed to [pop],
  /// or null when the sheet is dragged away.
  ///
  /// With [fullScreen], the sheet covers the whole screen (UIKit's
  /// `.overFullScreen` presentation) and cannot be dragged away: only [pop]
  /// closes it, so the widget must offer its own close control. [detents]
  /// is then ignored. Off iOS it is a full-screen dialog route that the
  /// system back gesture does not close.
  ///
  /// With [isDismissible] false, tapping outside the sheet does not close it,
  /// so the widget must offer its own close control. On iOS the sheet cannot
  /// be dragged away either and shows no grabber, since UIKit stops both
  /// together. Off iOS the drag handle goes too.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.fit,
    bool fullScreen = false,
    bool isDismissible = true,
    Color? backgroundColor,
  }) async {
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native && fullScreen) {
      return Navigator.of(context, rootNavigator: true).push<T>(
        MaterialPageRoute<T>(
          fullscreenDialog: true,
          builder: (context) => PopScope(
            canPop: false,
            child: ColoredBox(
              color:
                  backgroundColor ??
                  CupertinoColors.systemBackground.resolveFrom(context),
              child: builder(context),
            ),
          ),
        ),
      );
    }
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      if (detents == AdaptiveFilterDetents.fit) {
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          useSafeArea: true,
          showDragHandle: isDismissible,
          enableDrag: isDismissible,
          isDismissible: isDismissible,
          backgroundColor: backgroundColor,
          builder: (context) => SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: builder(context),
          ),
        );
      }
      return AdaptiveBottomSheet.show<T>(
        context: context,
        builder: builder,
        heightFactor: switch (detents) {
          AdaptiveFilterDetents.short => 0.34,
          AdaptiveFilterDetents.full => 0.94,
          AdaptiveFilterDetents.halfAndFull || AdaptiveFilterDetents.fit => 0.5,
        },
        expandedHeightFactor: detents == AdaptiveFilterDetents.halfAndFull
            ? 0.94
            : null,
        backgroundColor: backgroundColor,
        isDismissible: isDismissible,
      );
    }
    _installHandler();
    final done = Completer<T?>();
    final entry = AdaptiveNativeSheetEntry._(
      builder: builder,
      backgroundColor: backgroundColor,
      fits: !fullScreen && detents == AdaptiveFilterDetents.fit,
      fullScreen: fullScreen,
      complete: (value) {
        if (!done.isCompleted) done.complete(value as T?);
      },
    );
    try {
      await _channel.invokeMethod<void>('present', {
        'detents': fullScreen ? 'fullScreen' : detents.name,
        'dismissible': isDismissible,
        // Until the widget has been measured, open at the height the last
        // sheet measured, so a repeat open does not visibly resize.
        'height': _lastOpenHeight > 0 ? _lastOpenHeight : 320.0,
      });
    } on PlatformException {
      return null;
    }
    _stack.add(entry);
    active.value = entry;
    drawn.value = entry;
    return done.future;
  }

  static double _lastOpenHeight = 0;

  /// Tells UIKit the content's height, so the "fit" detent follows it. Debounced:
  /// an animating widget changes size every frame.
  ///
  /// [entry] says which sheet: a covered sheet drawn again after a rotation
  /// can measure differently at its new width. Only the sheet the engine
  /// draws is laid out at its own size, so a measurement of any other sheet
  /// is dropped.
  static void _reportHeight(AdaptiveNativeSheetEntry entry, double height) {
    if (drawn.value != entry) return;
    if ((height - entry._lastHeight).abs() < 0.5) return;
    entry._lastHeight = height;
    if (entry == _stack.lastOrNull) _lastOpenHeight = height;
    entry._heightTimer?.cancel();
    entry._heightTimer = Timer(const Duration(milliseconds: 40), () {
      final depth = _stack.indexOf(entry);
      if (depth < 0) return;
      _channel
          .invokeMethod<void>('setHeight', {'height': height, 'depth': depth})
          .catchError((Object _) {});
    });
  }

  /// Closes the sheet opened by [show], returning [value] from it. Call it
  /// from inside the sheet's widget.
  static Future<void> pop<T>(BuildContext context, [T? value]) async {
    // Off iOS the sheet is an ordinary modal bottom sheet route.
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      Navigator.of(context).pop<T>(value);
      return;
    }
    if (_stack.isEmpty) return;
    final entry = _stack.last;
    // Let UIKit finish dismissing first, so the sheet never shows what is
    // below it as it leaves.
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on PlatformException {
      // Already gone.
    }
    _finish(entry, value);
  }
}

/// One open native sheet: the caller's widget and how to finish it.
class AdaptiveNativeSheetEntry {
  AdaptiveNativeSheetEntry._({
    required this.builder,
    required this.backgroundColor,
    required this.fits,
    required this.fullScreen,
    required this.complete,
  });

  /// Whether the sheet's height follows [builder]'s widget.
  final bool fits;

  /// Whether the sheet covers the whole screen.
  final bool fullScreen;
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final void Function(Object? value) complete;

  /// The content height last reported for this sheet, and the debounce of
  /// the next report.
  double _lastHeight = 0;
  Timer? _heightTimer;
}

/// Fills the window, which on iOS is the sheet, with the caller's widget.
///
/// Placed above the app by `AdaptiveToolbarHost`. The topmost sheet's widget
/// stays mounted while any sheet is up, and is painted while the engine draws
/// that sheet ([AdaptiveNativeSheet.drawn]). While the engine draws another
/// layer (the page or a covered sheet, after the window changed size) it is
/// kept offstage at the size it last had, so nothing in it is laid out again
/// and its native views are where they were when the engine returns; the
/// covered sheet being drawn is mounted for that alone, over the page.
///
/// Each sheet has its own [Overlay], so widgets that need one (tooltips,
/// menus) work inside it. Where the window has a vertical bar (iPhone Duo),
/// it drops that bar's side inset, since the sheet floats inside the window
/// and is not part of the strip the system reserves for it. Every other inset
/// stays, such as the camera housing's on either side of an iPhone in
/// landscape, where the sheet fills the screen.
class AdaptiveNativeSheetLayer extends StatelessWidget {
  const AdaptiveNativeSheetLayer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AdaptiveNativeSheet.active,
      AdaptiveNativeSheet.drawn,
    ]),
    builder: (context, _) {
      final top = AdaptiveNativeSheet.active.value;
      if (top == null) return const SizedBox.shrink();
      final drawn = AdaptiveNativeSheet.drawn.value;
      return Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A covered sheet the engine draws again, mounted for that alone.
            if (drawn != null && drawn != top)
              _SheetSlot(key: ObjectKey(drawn), entry: drawn, painted: true),
            // The top sheet, mounted throughout.
            _SheetSlot(key: ObjectKey(top), entry: top, painted: drawn == top),
          ],
        ),
      );
    },
  );
}

/// One sheet's widget in [AdaptiveNativeSheetLayer].
///
/// While [painted], it fills the window, which is its sheet, and remembers
/// the window's metrics. While not, it stays mounted but offstage, laid out
/// with those metrics, so the engine can draw another layer at that layer's
/// size without this sheet's widgets being measured at it: the sheet's
/// native views would move and come back, and a fit sheet would report a
/// height it does not have.
class _SheetSlot extends StatefulWidget {
  const _SheetSlot({super.key, required this.entry, required this.painted});

  final AdaptiveNativeSheetEntry entry;
  final bool painted;

  @override
  State<_SheetSlot> createState() => _SheetSlotState();
}

class _SheetSlotState extends State<_SheetSlot> {
  /// The window's metrics when this sheet was last painted.
  MediaQueryData? _painted;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    var mq = MediaQuery.of(context);
    if (widget.painted) {
      _painted = mq;
    } else {
      mq = _painted ?? mq;
    }
    final pose = DuoPoseScope.of(context);
    // A full-screen sheet fills the window like a page, so it keeps the
    // strip's inset.
    EdgeInsets withoutStrip(EdgeInsets insets) =>
        pose == null || entry.fullScreen
        ? insets
        : pose.onLeft
        ? insets.copyWith(left: 0)
        : insets.copyWith(right: 0);
    // Always present, with no bounds of its own while painted, so that
    // toggling [painted] never moves the sheet's widget in the element tree.
    final size = widget.painted ? null : mq.size;
    return Visibility(
      visible: widget.painted,
      maintainState: true,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size?.width,
        maxWidth: size?.width,
        minHeight: size?.height,
        maxHeight: size?.height,
        child: MediaQuery(
          data: mq.copyWith(
            padding: withoutStrip(mq.padding),
            viewPadding: withoutStrip(mq.viewPadding),
          ),
          child: ColoredBox(
            color:
                entry.backgroundColor ??
                CupertinoColors.systemBackground.resolveFrom(context),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => entry.fits
                      ? _FitContent(entry: entry, child: entry.builder(context))
                      : entry.builder(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays [child] out at its natural height and reports it, so the native sheet
/// can follow it. Scrolls when the sheet is capped at full height.
class _FitContent extends StatefulWidget {
  const _FitContent({required this.entry, required this.child});
  final AdaptiveNativeSheetEntry entry;
  final Widget child;

  @override
  State<_FitContent> createState() => _FitContentState();
}

class _FitContentState extends State<_FitContent> {
  final _key = GlobalKey();

  void _measure() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        AdaptiveNativeSheet._reportHeight(widget.entry, box.size.height);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _measure();
          return false;
        },
        child: SingleChildScrollView(
          child: SizeChangedLayoutNotifier(
            child: KeyedSubtree(key: _key, child: widget.child),
          ),
        ),
      );
}
```

## Step 5: the detent enum

`AdaptiveNativeSheet.show` takes `AdaptiveFilterDetents`, defined in
`packages/adaptive_platform_ui/lib/src/overlays/filter_sheet/adaptive_filter_sheet.dart`.
It must contain `fit`, the default for the native sheet:

```dart
/// How tall a filter sheet rests.
enum AdaptiveFilterDetents {
  /// Half height, draggable to full height.
  halfAndFull,

  /// Full height only.
  full,

  /// A short sheet that fits a single control.
  short,

  /// Follows the height of its content, up to full height when the content is
  /// taller, and cannot be dragged taller than that. Only
  /// [AdaptiveNativeSheet] measures content; elsewhere it rests at half
  /// height.
  fit,
}
```

## Step 6: mount the layer in the toolbar host

The layer must sit above everything the app draws, inside the same `Stack` that holds the
navigator and the native toolbar, and inside `DuoPoseScope` (the layer reads the pose to
know which side inset belongs to the Duo vertical bar). The strip the host paints for the
iPhone Duo must not draw while a sheet is up. The complete file:

```dart
// packages/adaptive_platform_ui/lib/src/navigation/chrome/adaptive_toolbar_host.dart
import '../../core/theme/adaptive_theme.dart';
import '../../overlays/native_sheet/adaptive_native_sheet.dart';
import '../../core/adaptive_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../devices/duo/system_vertical_bar.dart';
import '../../devices/duo/duo_layout.dart';
import 'hosted_top_toolbar.dart';
import 'toolbar_blend.dart';
import 'toolbar_chrome_scope.dart';
import 'toolbar_registry.dart';

/// Fixed toolbar chrome that lives above the navigator.
///
/// Install it once around the navigator (an app `builder` is the right
/// place; [AdaptiveApp] does this for you). It owns a [ToolbarRegistry] that
/// every [AdaptiveScaffold] below publishes its app bar to, and it draws one
/// persistent bar whose items change as routes come and go. Because the bar
/// is not part of any route it stays put during page transitions, exactly
/// like the system bars on iOS 26 and the vertical bar on the iPhone Duo
/// inner display.
///
/// Works with any router: it depends on nothing but the widget tree.
class AdaptiveToolbarHost extends StatefulWidget {
  const AdaptiveToolbarHost({
    super.key,
    required this.child,
    @visibleForTesting this.debugVerticalBarEdge,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// Replaces the system's vertical bar edge in widget tests, where the
  /// platform channel it comes from does not exist.
  @visibleForTesting
  final SystemVerticalBarEdge? debugVerticalBarEdge;

  @override
  State<AdaptiveToolbarHost> createState() => _AdaptiveToolbarHostState();
}

class _AdaptiveToolbarHostState extends State<AdaptiveToolbarHost>
    with TickerProviderStateMixin {
  final ToolbarRegistry _registry = ToolbarRegistry();
  late final ToolbarBlend _blend;

  /// The system's vertical bar edge; null wherever the chrome is never drawn
  /// and in tests, where no platform channel answers.
  ValueListenable<SystemVerticalBarEdge>? _edge;

  @override
  void initState() {
    super.initState();
    _blend = ToolbarBlend(registry: _registry, vsync: this);
    if (widget.debugVerticalBarEdge == null &&
        AdaptiveCapabilities.systemVerticalBarEdge) {
      // The side the bar belongs on comes from the system, not from insets:
      // the leading Split View pane has none to read.
      _edge = SystemVerticalBar.edge..addListener(_onEdgeChanged);
    }
  }

  void _onEdgeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _edge?.removeListener(_onEdgeChanged);
    _blend.dispose();
    _registry.dispose();
    super.dispose();
  }

  /// The app's bar style where it asks for the Duo strip to be filled.
  AdaptiveBarStyle? _stripStyle(BuildContext context) {
    final bar = AdaptiveTheme.of(context).barStyle;
    return bar.fillsDuoStrip && bar.color != null ? bar : null;
  }

  @override
  Widget build(BuildContext context) {
    // The fixed chrome only exists where pages use the native iOS 26
    // toolbar; elsewhere pages keep their own Cupertino / Material bars.
    final hostsToolbar = AdaptiveStyle.of(context) == AdaptiveStyle.native;
    final edge =
        widget.debugVerticalBarEdge ??
        _edge?.value ??
        SystemVerticalBarEdge.unknown;
    // Resolved once: the bar, the title and the pages all read this decision.
    final pose = hostsToolbar
        ? DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), edge)
        : null;

    return ToolbarRegistryScope(
      registry: _registry,
      child: ToolbarChromeScope(
        hostsToolbar: hostsToolbar,
        hostsDuoControls: pose != null,
        child: DuoPoseScope(
          pose: pose,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always the first child at a stable position, so toggling the
              // chrome never rebuilds the navigator from scratch. The
              // MediaQuery in it is always here too, even when it changes
              // nothing:
              // adding it only in some poses would move the navigator in the
              // element tree whenever the pose changes (moving between Split
              // View panes), and rebuild every route.
              _BarInset(pose: pose, child: widget.child),
              // Always present, so the toolbar after it keeps its position in
              // the element tree as the pose changes.
              Positioned.fill(
                child: ValueListenableBuilder<AdaptiveNativeSheetEntry?>(
                  valueListenable: AdaptiveNativeSheet.drawn,
                  builder: (context, sheet, _) => _BarStrip(
                    pose: pose,
                    // The window the engine renders into is a native sheet
                    // while it draws one; the strip belongs to the page.
                    style: sheet != null ? null : _stripStyle(context),
                  ),
                ),
              ),
              // The widget of an open native sheet, over everything.
              const AdaptiveNativeSheetLayer(),
              if (hostsToolbar)
                HostedTopToolbar(blend: _blend, titleOnly: pose != null),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gives the pages the inset the system would have added for a vertical bar
/// it does not draw: in the leading Split View pane the system wants a bar
/// there but reserves no strip for it, since UIKit only insets for bars it
/// draws itself. Add that inset here, as UIKit does for a native app, so a
/// page's SafeArea and the scaffold's body inset keep clear of the bar.
///
/// Always builds a [MediaQuery], with the data unchanged when there is nothing
/// to add, and is a widget of its own so the host does not depend on the whole
/// [MediaQueryData] (every keyboard frame would rebuild the chrome).
class _BarInset extends StatelessWidget {
  const _BarInset({required this.pose, required this.child});

  final DuoPose? pose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pose = this.pose;
    return MediaQuery(
      data: pose == null || pose.reservedBySystem
          ? mq
          : mq.copyWith(
              padding: pose.addStrip(mq.padding),
              viewPadding: pose.addStrip(mq.viewPadding),
            ),
      child: child,
    );
  }
}

/// Fills the strip the system reserves for the iPhone Duo vertical bar with
/// the app's bar colour, so the bar reads as one band down that edge. A strip
/// gradient starts where the title band ends, so the bar runs into it without
/// a step; above that the strip keeps the bar colour. Draws nothing without a
/// pose or a style, and never takes a touch.
class _BarStrip extends StatelessWidget {
  const _BarStrip({required this.pose, required this.style});

  final DuoPose? pose;
  final AdaptiveBarStyle? style;

  @override
  Widget build(BuildContext context) {
    final pose = this.pose;
    final style = this.style;
    final color = style?.color;
    if (pose == null || style == null || color == null) {
      return const SizedBox.shrink();
    }
    final gradient = style.duoStripGradient;
    return IgnorePointer(
      child: Align(
        alignment: pose.onLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: SizedBox(
          width: pose.stripWidth,
          height: double.infinity,
          child: gradient == null
              ? ColoredBox(color: color)
              : ValueListenableBuilder<DuoTitleBandMetrics?>(
                  valueListenable: SystemVerticalBar.titleBand,
                  builder: (context, _, _) => Column(
                    children: [
                      SizedBox(
                        height: DuoTitleBand.of(context).contentTop,
                        width: double.infinity,
                        child: ColoredBox(color: color),
                      ),
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: gradient),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
```

## Step 7: the app

The example is an Orders page. Its filter sheet is built from the package's native
controls, and its accounts line opens a nested sheet of native switches.

### A frame for a filter sheet's content

It takes its natural height, so the sheet can fit it: a title with a reset icon (or a
close icon, for a sheet opened with `isDismissible: false`), the caller's children, and a
full-width apply button showing a live count.

```dart
// lib/core/widgets/sheet_frame.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// The shell of a filter sheet's content: a title with a reset icon (or a
/// close icon, given [onClose]), the caller's [children], and a full-width
/// apply button showing [count]. It takes its natural height, so a sheet can
/// fit it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.children,
    required this.count,
    required this.onApply,
    this.onReset,
    this.onClose,
  });

  final List<Widget> children;
  final int count;
  final VoidCallback onApply;

  /// Null disables the reset icon.
  final VoidCallback? onReset;

  /// Shows a close icon in place of the reset icon, for a sheet that tapping
  /// outside does not close.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: label('Filters', size: 22, weight: FontWeight.w600),
                ),
                IconButton(
                  onPressed: onClose ?? onReset,
                  icon: Icon(
                    onClose == null
                        ? Icons.restart_alt_rounded
                        : Icons.close_rounded,
                  ),
                  color: ink,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: onApply,
                icon: const Icon(Icons.check_rounded),
                label: Text('$count'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A row of single-choice or multi-choice chips.
class ChipGroup<T> extends StatelessWidget {
  const ChipGroup({
    super.key,
    required this.options,
    required this.isSelected,
    required this.onTap,
  });

  final List<(T, IconData, String)> options;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (value, icon, text) in options)
        ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(text),
          selected: isSelected(value),
          onSelected: (_) => onTap(value),
        ),
    ],
  );
}

/// A titled section that opens and closes, animating its height. The open
/// state belongs to the caller, so the widget can stay stateless.
class OpenSection extends StatelessWidget {
  const OpenSection({
    super.key,
    required this.open,
    required this.icon,
    required this.child,
  });

  final ValueNotifier<bool> open;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: open,
    builder: (context, isOpen, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => open.value = !isOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: muted),
                const Spacer(),
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: muted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Padding(padding: const EdgeInsets.only(bottom: 8), child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );
}
```

### The models (pure data)

```dart
// lib/features/orders/models/order.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum OrderSide { buy, sell }

enum OrderStatus { open, filled, cancelled }

enum Account {
  personal('Personal', Icons.person_outline_rounded),
  isa('ISA', Icons.savings_outlined),
  pension('Pension', Icons.account_balance_outlined);

  const Account(this.title, this.icon);
  final String title;
  final IconData icon;
}

class Order extends Equatable {
  const Order(
    this.symbol,
    this.side,
    this.quantity,
    this.price,
    this.status,
    this.account, {
    this.limit = false,
  });

  final String symbol;
  final OrderSide side;
  final double quantity, price;
  final OrderStatus status;
  final Account account;

  /// A limit order rather than a market order.
  final bool limit;

  double get value => quantity * price;

  @override
  List<Object> get props => [
    symbol,
    side,
    quantity,
    price,
    status,
    account,
    limit,
  ];
}

/// Newest first.
const orders = [
  Order('NVDA', OrderSide.buy, 10, 142.87, OrderStatus.open, Account.personal),
  Order(
    'VOO',
    OrderSide.buy,
    4,
    538.26,
    OrderStatus.filled,
    Account.isa,
    limit: true,
  ),
  Order(
    'AAPL',
    OrderSide.sell,
    6,
    237.49,
    OrderStatus.filled,
    Account.personal,
  ),
  Order(
    'MSFT',
    OrderSide.buy,
    2,
    428.76,
    OrderStatus.cancelled,
    Account.pension,
    limit: true,
  ),
  Order('VTI', OrderSide.buy, 12, 291.42, OrderStatus.filled, Account.pension),
  Order(
    'AMZN',
    OrderSide.sell,
    8,
    219.32,
    OrderStatus.open,
    Account.isa,
    limit: true,
  ),
  Order('NVDA', OrderSide.sell, 15, 142.87, OrderStatus.filled, Account.isa),
  Order(
    'AAPL',
    OrderSide.buy,
    3,
    237.49,
    OrderStatus.cancelled,
    Account.personal,
  ),
  Order(
    'VOO',
    OrderSide.sell,
    1,
    538.26,
    OrderStatus.open,
    Account.pension,
    limit: true,
  ),
  Order('MSFT', OrderSide.buy, 5, 428.76, OrderStatus.filled, Account.personal),
];
```

```dart
// lib/features/orders/models/orders_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/orders/models/order.dart';

enum OrderSort { newest, value }

class OrdersFilter extends Equatable {
  const OrdersFilter({
    this.side,
    this.sort = OrderSort.newest,
    this.minValue = 0,
    this.limitOnly = false,
    this.showCancelled = true,
    this.accounts = const {},
  });

  static const double maxValue = 4000;

  /// Null means buys and sells.
  final OrderSide? side;
  final OrderSort sort;
  final double minValue;
  final bool limitOnly;
  final bool showCancelled;

  /// Empty means every account.
  final Set<Account> accounts;

  int get activeCount =>
      (side != null ? 1 : 0) +
      (sort != OrderSort.newest ? 1 : 0) +
      (minValue > 0 ? 1 : 0) +
      (limitOnly ? 1 : 0) +
      (showCancelled ? 0 : 1) +
      (accounts.isEmpty ? 0 : 1);

  OrdersFilter copyWith({
    OrderSide? side,
    bool clearSide = false,
    OrderSort? sort,
    double? minValue,
    bool? limitOnly,
    bool? showCancelled,
    Set<Account>? accounts,
  }) => OrdersFilter(
    side: clearSide ? null : (side ?? this.side),
    sort: sort ?? this.sort,
    minValue: minValue ?? this.minValue,
    limitOnly: limitOnly ?? this.limitOnly,
    showCancelled: showCancelled ?? this.showCancelled,
    accounts: accounts ?? this.accounts,
  );

  bool allows(Order o) =>
      (side == null || o.side == side) &&
      o.value >= minValue &&
      (!limitOnly || o.limit) &&
      (showCancelled || o.status != OrderStatus.cancelled) &&
      (accounts.isEmpty || accounts.contains(o.account));

  List<Order> apply(List<Order> all) {
    final kept = all.where(allows).toList();
    if (sort == OrderSort.value) {
      kept.sort((a, b) => b.value.compareTo(a.value));
    }
    return kept;
  }

  @override
  List<Object?> get props => [
    side,
    sort,
    minValue,
    limitOnly,
    showCancelled,
    accounts,
  ];
}
```

### The sheets: a filter sheet, and a nested sheet opened from it

Each sheet has an open function that creates the draft notifiers, calls
`AdaptiveNativeSheet.show`, and disposes the notifiers when the sheet completes. The
widgets are stateless. The nested sheet is opened from the filter sheet's widget with that
widget's own `context`, exactly like the first one.

The line that opens the nested sheet uses a `GestureDetector`, not an `InkWell`: the sheet
below is frozen into a bitmap as the nested sheet opens, and a ripple would be caught
mid-animation and stay on screen.

```dart
// lib/features/orders/view/orders_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';

/// A native sheet holding the app's own widget, built from the package's
/// native controls: segmented controls, a slider and switches, each a real
/// UIKit view on iOS. The accounts line opens a second native sheet on top,
/// holding another widget of native switches.
Future<OrdersFilter?> showOrdersFilterSheet(
  BuildContext context,
  OrdersFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<OrdersFilter>(
    context: context,
    builder: (_) => OrdersFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class OrdersFilterContent extends StatelessWidget {
  const OrdersFilterContent({super.key, required this.draft});

  final ValueNotifier<OrdersFilter> draft;

  /// Opens the accounts as a second sheet over this one.
  Future<void> _pickAccounts(BuildContext context) async {
    final picked = await showAccountsSheet(context, draft.value.accounts);
    if (picked != null) draft.value = draft.value.copyWith(accounts: picked);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OrdersFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.apply(orders).length,
      onReset: filter == const OrdersFilter()
          ? null
          : () => draft.value = const OrdersFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Buy', 'Sell'],
          icons: const [
            AdaptiveIcon(
              sfSymbol: 'arrow.up.arrow.down',
              icon: Icons.swap_vert_rounded,
            ),
            AdaptiveIcon(
              sfSymbol: 'arrow.down.left',
              icon: Icons.south_west_rounded,
            ),
            AdaptiveIcon(
              sfSymbol: 'arrow.up.right',
              icon: Icons.north_east_rounded,
            ),
          ],
          selectedIndex: filter.side == null ? 0 : filter.side!.index + 1,
          onValueChanged: (i) => draft.value = i == 0
              ? filter.copyWith(clearSide: true)
              : filter.copyWith(side: OrderSide.values[i - 1]),
        ),
        const SizedBox(height: 16),
        AdaptiveSegmentedControl(
          labels: const ['Newest', 'Value'],
          icons: const [
            AdaptiveIcon(sfSymbol: 'clock', icon: Icons.schedule_rounded),
            AdaptiveIcon(
              sfSymbol: 'dollarsign.circle',
              icon: Icons.paid_outlined,
            ),
          ],
          selectedIndex: filter.sort.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(sort: OrderSort.values[i]),
        ),
        const SizedBox(height: 24),
        label(
          filter.minValue <= 0 ? 'Any value' : 'Over ${money(filter.minValue)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.minValue,
          max: OrdersFilter.maxValue,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(minValue: v),
        ),
        const SizedBox(height: 8),
        _SwitchLine(
          icon: Icons.price_change_outlined,
          text: 'Limit only',
          value: filter.limitOnly,
          onChanged: (on) => draft.value = filter.copyWith(limitOnly: on),
        ),
        _SwitchLine(
          icon: Icons.block_rounded,
          text: 'Cancelled',
          value: filter.showCancelled,
          onChanged: (on) => draft.value = filter.copyWith(showCancelled: on),
        ),
        _AccountsLine(
          accounts: filter.accounts,
          onTap: () => _pickAccounts(context),
        ),
      ],
    ),
  );
}

/// An icon and title with a native switch at the trailing edge.
class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    required this.icon,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: muted),
        const SizedBox(width: 14),
        Expanded(child: label(text, size: 17)),
        AdaptiveSwitch(value: value, activeColor: red, onChanged: onChanged),
      ],
    ),
  );
}

/// A tappable line showing the chosen accounts, opening the accounts sheet.
class _AccountsLine extends StatelessWidget {
  const _AccountsLine({required this.accounts, required this.onTap});

  final Set<Account> accounts;
  final VoidCallback onTap;

  // No ink: the sheet opening is the feedback, and a ripple would be
  // caught mid-animation in the still frame this sheet shows underneath.
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: muted),
          const SizedBox(width: 14),
          Expanded(
            child: accounts.isEmpty
                ? label('All accounts', size: 17)
                : Row(
                    children: [
                      for (final a in Account.values)
                        if (accounts.contains(a))
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(a.icon, color: red),
                          ),
                    ],
                  ),
          ),
          const Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    ),
  );
}

/// Opens a second native sheet over the first, holding a native switch per
/// account. Returns the chosen accounts, or null when the sheet is dragged
/// away. An empty set means every account.
Future<Set<Account>?> showAccountsSheet(
  BuildContext context,
  Set<Account> initial,
) {
  final chosen = ValueNotifier(
    initial.isEmpty ? Account.values.toSet() : initial,
  );
  return AdaptiveNativeSheet.show<Set<Account>>(
    context: context,
    builder: (_) => AccountsSheetContent(chosen: chosen),
  ).whenComplete(chosen.dispose);
}

/// The second sheet's widget: a native switch per account, and a Done button.
class AccountsSheetContent extends StatelessWidget {
  const AccountsSheetContent({super.key, required this.chosen});

  final ValueNotifier<Set<Account>> chosen;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: ValueListenableBuilder<Set<Account>>(
          valueListenable: chosen,
          builder: (context, set, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Accounts', size: 22, weight: FontWeight.w600),
              const SizedBox(height: 12),
              for (final a in Account.values)
                _SwitchLine(
                  icon: a.icon,
                  text: a.title,
                  value: set.contains(a),
                  onChanged: (on) =>
                      chosen.value = on ? {...set, a} : ({...set}..remove(a)),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  // Every account, or none, both mean no account filter.
                  onPressed: set.isEmpty
                      ? null
                      : () => AdaptiveNativeSheet.pop(
                          context,
                          set.length == Account.values.length
                              ? <Account>{}
                              : set,
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('${set.length}'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
```

### The page

The page keeps the filter, opens the sheet, and rebuilds with the result. It never says
how the sheet is presented or how tall it is.

```dart
// lib/features/orders/view/orders_page.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';
import 'package:native_widgets_on_duo/features/orders/view/orders_filter_sheet.dart';

class Orders extends StatefulWidget {
  const Orders({super.key});
  @override
  State<Orders> createState() => _OrdersState();
}

class _OrdersState extends State<Orders> {
  OrdersFilter filter = const OrdersFilter();

  Future<void> openFilters() async {
    final result = await showOrdersFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final rows = filter.apply(orders);
    return PageScroll(
      storageKey: 'orders',
      children: [
        FilterSectionHeader(
          title: 'Recent orders',
          onPressed: openFilters,
          activeCount: filter.activeCount,
        ),
        const SizedBox(height: 20),
        for (final o in rows) _OrderRow(order: o),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Icon(Icons.search_off_rounded, size: 40, color: muted),
          ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final buy = order.side == OrderSide.buy;
    final cancelled = order.status == OrderStatus.cancelled;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 9),
      leading: CircleAvatar(
        backgroundColor: buy
            ? const Color(0xFFE5EBE1)
            : const Color(0xFFF3E1E2),
        child: Icon(
          buy ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: buy ? green : red,
          size: 20,
        ),
      ),
      title: label(
        '${order.quantity.toStringAsFixed(0)} ${order.symbol}',
        weight: FontWeight.w500,
        color: cancelled ? muted : ink,
      ),
      subtitle: Row(
        children: [
          Icon(order.account.icon, size: 14, color: muted),
          if (order.limit) ...[
            const SizedBox(width: 6),
            const Icon(Icons.price_change_outlined, size: 14, color: muted),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          label(money(order.value), size: 14, color: cancelled ? muted : ink),
          const SizedBox(width: 10),
          Icon(
            switch (order.status) {
              OrderStatus.open => Icons.schedule_rounded,
              OrderStatus.filled => Icons.check_circle_rounded,
              OrderStatus.cancelled => Icons.block_rounded,
            },
            size: 18,
            color: order.status == OrderStatus.filled ? green : muted,
          ),
        ],
      ),
    );
  }
}
```

```dart
// lib/core/widgets/filter_button.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';

/// Opens a filter sheet. Shows how many filters are active.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.onPressed,
    this.activeCount = 0,
  });
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: active ? 'Filters, $activeCount active' : 'Filters',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: active,
            label: Text('$activeCount'),
            backgroundColor: red,
            child: Icon(
              Icons.tune_rounded,
              size: 24,
              color: active ? red : ink,
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// lib/core/widgets/filter_section_header.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/core/widgets/filter_button.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// A page section title with the filter button at its trailing edge.
class FilterSectionHeader extends StatelessWidget {
  const FilterSectionHeader({
    super.key,
    required this.title,
    required this.onPressed,
    required this.activeCount,
  });
  final String title;
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: label(title, size: 20, weight: FontWeight.w600),
        ),
      ),
      FilterButton(onPressed: onPressed, activeCount: activeCount),
    ],
  );
}
```

Add the page to the router and a tab for it, as for any other page.

## Rules the implementation must follow

**Swift**

* One `FlutterViewController` drives an engine at a time. Hand the engine to the top
  sheet's controller. Never create a second engine.
* Keep every sheet controller alive for the life of the app (`pool`, one per depth).
  Releasing a `FlutterViewController` destroys the engine and crashes the app.
* Present a nested sheet from its own transparent `UIWindow` one level above the sheet
  below. Never let a sheet present another: UIKit then shrinks the lower sheet to the
  upper sheet's height, whatever its detents say.
* Before the engine leaves a sheet, cover it with a bitmap of itself:
  `drawHierarchy(in:afterScreenUpdates: false)` into an image, in a `UIImageView` added
  *above* the Flutter view in its superview, taking touches. Not `snapshotView`: that one
  can keep showing the engine's surface, which the engine reuses. Not inside the Flutter
  view: the engine can still add its layers there while handing over. Remove the bitmap
  shortly after the engine has drawn into the view again.
* On close, hand the engine to whatever is now on top and re-attach its surface
  (`surfaceUpdated:`), on both paths: `dismiss` and drag to dismiss. Hide the overlay
  window of every closed nested sheet.
* After the app becomes active, every `FlutterViewController` on the engine claims the
  engine's native views, and the last one wins. On the next run loop, call
  `surfaceUpdated:` on `engine.viewController` so the controller on screen gets them back.
* Answer `present` as soon as presenting starts, not when the slide-up finishes, so the
  sheet never shows what it covers as it rises.
* The `fit` detent is the only detent (`.custom`, capped at `maximumDetentValue`). Add no
  `.large()`: it lets the user drag the sheet tall and leave it there. Give each depth its
  own detent identifier, and change the height by swapping in a new detent with a new
  identifier inside `animateChanges`, never by invalidating detents (that resizes the
  sheets below too).
* Redraw after a resize from the top sheet's transition coordinator, never from a timer.
  The pooled controllers are `SheetViewController`s that report `viewWillTransition`; when
  the top one's coordinator reports the animation finished and the page's size differs
  from when the page was last drawn, lend the engine to the page and to each covered sheet
  in turn, have Dart draw each (`drawLayer`), give a new bitmap only to a layer that had
  one, and give the engine back to the top sheet. Hold the top sheet under a bitmap
  meanwhile. Stop and resync if a sheet opens or closes meanwhile.
* Anything that measures the page (the Duo title band) uses the page's controller
  (`pageController`), not `registrar.viewController`.
* For a sheet presented with `dismissible: false`, set `isModalInPresentation = true` and
  hide the grabber. UIKit has no way to block only the tap outside; the drag goes with it.
  Set `isModalInPresentation` on every present, since the pooled controllers are reused.
* Guard `#available(iOS 16.0, *)` for custom detents. Before iOS 16 there are no custom
  detents, so `fit` falls back to `[.medium(), .large()]`.

**Dart**

* The widget is not a route. If it is pushed as one, the page behind stops being the
  current route and the package hides its navigation bar. Draw it as a layer in the
  toolbar host.
* Keep a stack of entries; `active` is the top one and `drawn` the one the engine draws:
  the same, except while `drawLayer` has it draw the page (null) or a covered sheet. `pop`
  closes the top of the stack.
* Keep the top sheet's widget mounted while `drawLayer` draws another layer: offstage, laid
  out with the metrics it last had (`OverflowBox` and `MediaQuery` in `_SheetSlot`), its
  tickers off. Unmounting it would dispose its native views and create them again on
  return, which shows as controls jumping; laying it out at the page's size would move
  them and make a fit sheet report a height it does not have.
* Install the channel handler once, for the whole stack.
* The layer has its own `Overlay` keyed by the entry, so tooltips and menus work and a
  different sheet gets a fresh overlay. It drops only the Duo vertical bar's side inset;
  every other inset stays (an iPhone in landscape needs them clear of the camera housing).
* Measure the content with a `GlobalKey` and `SizeChangedLayoutNotifier`, wrapped in a
  `SingleChildScrollView`. Report the height after the frame, debounced, with the sheet's
  depth, so a covered sheet redrawn at a new width resizes itself and not the top one.
  Drop a measurement of any sheet the engine is not drawing.
* Open at the last measured height so a repeat open does not visibly resize.
* `pop` waits for UIKit to finish dismissing before it completes the result.
* Off iOS, show `showModalBottomSheet` with `useRootNavigator: true`, and make `pop` call
  `Navigator.pop`. Nested sheets then stack as ordinary routes.
* While the engine draws a native sheet (`drawn`), do not paint chrome over the window
  (the Duo strip); while it draws the page again, do.
* Pass `isDismissible` through on every path: `dismissible` in the `present` arguments,
  and `isDismissible`, `enableDrag` and `showDragHandle` off iOS.

**App**

* Keep each sheet's widget stateless. Put the draft and any open or closed state in
  `ValueNotifier`s created by the open function and disposed when the sheet completes.
* Open a nested sheet from the sheet's widget with its own `context`, and apply the result
  to the outer sheet's draft.
* A sheet opened with `isDismissible: false` must show a close control that calls
  `AdaptiveNativeSheet.pop(context)`, or the user cannot leave it. With `SheetFrame`, pass
  `onClose` instead of `onReset`.
* Rows that open a nested sheet get no ink ripple (`GestureDetector`, not `InkWell`).
* The apply count comes from the same filter function the page uses.
* Use the package's `Adaptive` controls for anything that should look native on iOS.
* Respect the system colour scheme. Do not force light or dark.

## Troubleshooting

Each of these was hit while building this, and the listings above already contain the
fix. If you see one, check that part of your copy.

* **The sheet below shrinks to the nested sheet's height.** The nested sheet was presented
  by the sheet below. Present it from an overlay window (`overlayWindow(over:)`).
* **The sheet below loses its switches and sliders while a nested sheet is open.** It was
  not frozen, or the bitmap went inside the Flutter view or came from `snapshotView`. Use
  `freeze(_:)` as listed.
* **A highlight stays stuck on the row that opened the nested sheet.** The row has an ink
  ripple that the freeze captured. Use a `GestureDetector`.
* **A sheet opened with `isDismissible: false` still closes on a tap outside.** The
  `dismissible` argument is missing from `present`, or `isModalInPresentation` is not set
  in `presentLevel`.
* **Dragging the sheet up leaves it at full height.** The `fit` detents include
  `.large()`. Keep the fit detent alone.
* **Native controls in a sheet vanish after locking and unlocking the phone**, once a
  nested sheet has been opened. A pooled, off-screen controller claimed the native views
  on becoming active. Keep `becameActive()`.
* **After rotating with a sheet open, the page behind (and any covered sheet) is squeezed
  or stretched.** It is the previous orientation's frame, scaled: only the top sheet draws
  live. The redraw (`transition(of:with:)`, `redrawCovered`, `lend`, and Dart's
  `drawLayer`) runs when the top sheet's transition coordinator reports the rotation
  finished. Check that `present` gives each pooled `SheetViewController` its
  `onTransition`, that `drawnPageSize` is recorded when the first sheet opens, and that
  Dart answers `drawLayer` only after its frame is drawn.
* **Native controls in the top sheet jump after a rotation.** The top sheet's widget was
  unmounted while the engine drew the covered layers, so its native views were destroyed
  and created again. Keep it mounted and offstage at its own size (`_SheetSlot`); only
  `drawn` changes during a redraw, `active` stays the top.
* **iPhone Duo: after rotating, a gap appears between the title band and the page
  content**, in the page behind a sheet or on the page itself. The title band was measured
  in the wrong place or at the wrong time. It must be measured in the page's controller
  (Step 2), and the vertical bar events must carry the view size (Step 3).
* **iPhone in landscape: the sheet's content sits under the Dynamic Island.** The layer
  dropped all side insets. Drop only the Duo vertical bar's side.
* **In the simulator, a tap on a native switch is occasionally ignored** right after a
  sheet opens or closes. This was seen in the simulator only and could not be reproduced
  on demand. Wait for the sheet to settle before tapping, and tap again before treating
  it as a bug.

## Step 8: verify

```sh
flutter analyze lib packages/adaptive_platform_ui/lib
```

Run on real runtimes and check:

* the sheet opens with its content already inside, with no flash of what it covers;
* native controls inside the sheet respond (segmented, slider, switch);
* choosing an option changes the apply count, and applying filters the list;
* the height follows the content when a section opens or closes, and a drag up springs
  back;
* the nested sheet opens over the filter sheet, which keeps its full height and its
  controls; Done returns the result to the filter sheet, and a drag away returns `null`;
* closing a sheet leaves the page usable, and reopening remembers the current filter;
* a sheet opened with `isDismissible: false` stays open on a tap outside and a drag down,
  shows no grabber, and closes with its close icon, returning `null`;
* with a nested sheet opened once, locking and unlocking keeps every sheet's controls;
* on an iPhone and on the iPhone Duo, rotating with one sheet and with two sheets open
  ends with the page and every covered sheet drawn correctly at the new size as soon as
  the turn's animation ends, the top sheet's controls where they were, the title band
  without a gap, and the page live after the sheets close;
* on an iPhone in landscape, the sheet's content clears the Dynamic Island.

iOS: build and run with XcodeBuildMCP on an iPhone simulator, on the iPhone Duo, and on
iOS 18 and iOS 26 or later. Use `snapshot_ui` to read switch values and the live count.
Re-read the screenshot orientation before computing tap coordinates after a rotation.

Android:

```sh
export PATH=$PATH:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator
emulator -avd Medium_Phone_API_35 -no-snapshot-save -no-audio &
flutter run -d emulator-5554 --debug
adb -s emulator-5554 shell input tap 964 792
adb -s emulator-5554 exec-out screencap -p > shot.png
```

Wait for the app to finish installing before sending taps. Android screenshot coordinates
are physical pixels (1080 by 2400 on the test emulators).

## Adding a sheet to another page: checklist

1. Write the pure data filter model with `activeCount`, `copyWith` and an apply method.
2. Write the sheet's widget, stateless, taking `ValueNotifier`s from its open function.
3. Write `show<Name>Sheet` that creates the notifiers, calls `AdaptiveNativeSheet.show`
   with `builder: (_) => <Name>Content(...)`, and disposes the notifiers in `whenComplete`.
   If tapping outside must not close the sheet, also pass `isDismissible: false` and give
   the widget a close icon (`SheetFrame(onClose: () => AdaptiveNativeSheet.pop<T>(context))`).
4. For a nested sheet, write a second open function and content widget the same way, and
   call the open function from the first sheet's widget, from a row without ink.
5. In the page state, keep the filter, call the show function from `openFilters`, and
   rebuild with the result when it is not `null`.
6. Place `FilterSectionHeader(title: ..., onPressed: openFilters, activeCount: filter.activeCount)`.
7. Run the verification steps.
