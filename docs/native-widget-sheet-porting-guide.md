# Native widget sheet: a step-by-step porting guide

This guide tells you how to add the **native widget sheet** to a Flutter app that
uses the `adaptive_platform_ui` package (the local fork under
`packages/adaptive_platform_ui`) but does not have the sheet yet. Follow the
steps in order. Every step says which file to create or change, gives the whole
code to paste, and ends with a check. Do not skip the checks.

The reference implementation is this repository (`native_widgets_on_duo`,
commit after `8a76596`). The code below is copied from it verbatim.

## Copy-ready prompt for the implementing AI

> Add the native widget sheet from `docs/native-widget-sheet-porting-guide.md`
> to this project. Work through the guide's steps in order, 1 to 10. For each
> step: create or change exactly the files it names, paste the code it gives,
> then run the check it gives. If a check fails, fix the cause before moving
> on. Do not change the design of existing pages, do not rename anything, and
> do not add features the guide does not ask for. When you change code that
> can be built, run a real build before reporting it done: `flutter analyze`
> for Dart, and an iOS device or simulator build for Swift. Keep working until
> every step is done and the final checklist in section 11 passes, then stop
> and report what you changed and what you could not verify.

## What you are building

On iOS, `AdaptiveNativeSheet.show(...)` presents a **real UIKit sheet**
(`UISheetPresentationController`: grabber, detents, dimming, drag to dismiss)
whose content is a **Flutter widget**. The content runs in its **own Flutter
engine** (one engine per open sheet, made by a `FlutterEngineGroup`), because
one Flutter engine can only draw into one view at a time. The page behind the
sheet keeps its own engine and keeps rendering.

Because the sheet has its own engine, nothing live can cross from the page to
the sheet: no widgets, no closures, no notifiers. The page sends a **route
name** and **plain codec data** (maps, lists, strings, numbers, bools). The
sheet engine starts at a second Dart entrypoint, `nativeSheetMain`, reads that
route, builds the matching content widget, and when it closes, returns plain
codec data back. The page decodes it.

On Android and other platforms the same `show` call uses Flutter's stock
`showModalBottomSheet`, built from the `builder` you pass. The full-screen
variant (`fullScreen: true`) is a Flutter page route on every platform.

```text
Page engine (Dart)                       UIKit                         Sheet engine (Dart)
AdaptiveNativeSheet.show(route, args) -> NativeWidgetSheet.present   -> nativeSheetMain()
                                          FlutterEngineGroup.makeEngine  AdaptiveNativeSheet.bootstrap()
                                          SheetWindow + .pageSheet       builds content for route
                                          fit detent from 'setHeight' <- AdaptiveNativeSheetContent measures
show future completes with value      <- dismiss(value)             <- AdaptiveNativeSheet.pop(context, value)
```

### Parts, and where each one lives

| Part | File | Side |
| --- | --- | --- |
| UIKit sheet manager: engines, windows, detents, dismissal, rotation | `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift` | package, Swift |
| Plugin wiring: channel, per-engine registration | `.../Plugin/AdaptivePlatformUiPlugin.swift` | package, Swift |
| Dart API: `AdaptiveNativeSheet.show`, `pop`, `bootstrap`, `AdaptiveNativeSheetContent` | `packages/adaptive_platform_ui/lib/src/overlays/native_sheet/adaptive_native_sheet.dart` | package, Dart |
| Detent names | `packages/adaptive_platform_ui/lib/src/overlays/filter_sheet/adaptive_filter_sheet.dart` (`AdaptiveFilterDetents`) | package, Dart |
| Second entrypoint | `lib/main.dart` (`nativeSheetMain`) | app, Dart |
| Sheet app: route to content widget | `lib/app/native_sheet_app.dart` | app, Dart |
| Codec: your models to plain data and back | `lib/app/native_sheet_codec.dart` | app, Dart |
| Content widgets | `lib/features/<feature>/view/<feature>_filter_sheet.dart` | app, Dart |

## Rules that must hold (read before coding)

1. **Only codec data crosses engines.** `arguments` and the value given to
   `pop` must be `null`, `bool`, `int`, `double`, `String`, `List` or `Map` of
   those. Convert enums with `.name`, dates with `toIso8601String()`, sets with
   `.toList()`. Never pass a widget, a closure, a `ValueNotifier` or a Bloc.
2. **Every sheet has a route.** On iOS `route` is required. The sheet app's
   `switch` must have a case for it, or the sheet throws at start.
3. **The sheet app does not install the page's navigation host.** It uses a
   plain `CupertinoApp` with your theme. It never uses `AdaptiveApp`,
   `AdaptiveToolbarHost`, a router, or `AdaptiveScaffold`.
4. **`nativeSheetMain` must carry `@pragma('vm:entry-point')`**, or Release
   builds tree-shake it and the sheet never starts (15 s timeout, then an error).
5. **Content with a fixed height at any width.** Use the package's native
   controls (`AdaptiveSegmentedControl`, `AdaptiveSwitch`, `AdaptiveSlider`) and
   fixed rows. Do not use `Wrap`, chips that re-flow, `AnimatedSize`, or
   collapsible sections inside a `fit` sheet: a sheet whose height depends on
   its width jumps after the phone rotates.
6. **Do not hide, snapshot or cover anything during rotation.** The rotation
   handling in step 8 keeps the old frame still under iOS's own cross-fade.
   Timers, snapshots and private engine calls are not allowed.

## Step 1: Swift, the UIKit sheet manager

Create `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift`
with this exact content. If the package uses CocoaPods instead of SwiftPM, the
folder is `packages/adaptive_platform_ui/ios/Classes/Overlays/` instead; the
code is the same.

```swift
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
```

What the pieces do, so you can read the file:

- `Level`: one open sheet. Holds its engine, `SheetViewController`
  (a `FlutterViewController`), method channel, arguments, result callback,
  window, measured fit height and state flags.
- `present`: makes an engine from the `FlutterEngineGroup` with entrypoint
  `nativeSheetMain`, registers the package's controls for it
  (`AdaptivePlatformUiPlugin.registerSheetContent`), and makes a transparent
  `UIWindow` one level above the page's window to present from. The sheet is
  presented only after the Dart side calls `bootstrap` (so the surface exists)
  and the `ready` call stops the 15 s startup timeout.
- `presentLevel`: `.pageSheet` with detents from the `detents` argument. `fit`
  is a custom detent that returns the measured content height
  (`setFitDetent`). A non-dismissible sheet is refused in
  `presentationControllerShouldDismiss`, not with `isModalInPresentation`.
- `setHeight` / `flushPendingHeights`: the content reports its height; the
  detent is replaced with a new identifier, after any running transition.
- `freezeForTurn` / `snapAfterTurn`: rotation (explained in step 8).
- `dismiss` / `finish`: reply to the sheet engine, complete the page's `show`
  call with the value, hide the window, destroy the engine next run loop.

**Check:** the file compiles once steps 2 and 3 are done. If `UIColor(argb:)`
is missing, add this extension anywhere in the package's Swift sources:

```swift
extension UIColor {
    convenience init(argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
```

## Step 2: Swift, plugin wiring

Open `.../Plugin/AdaptivePlatformUiPlugin.swift`. The plugin must register
twice: once for the page engine (owns navigation, tab bar, toolbar and the
sheet channel) and once per sheet engine (controls only). Make the entry
look like this:

```swift
    public static func register(with registrar: FlutterPluginRegistrar) {
        register(with: registrar, ownsNavigation: true)
    }

    /// Sheet engines own their controls but must not replace the page's
    /// process-wide native navigation and drawer channels.
    static func registerSheetContent(with registrar: FlutterPluginRegistrar) {
        register(with: registrar, ownsNavigation: false)
    }

    private static func register(with registrar: FlutterPluginRegistrar, ownsNavigation: Bool) {
        if ownsNavigation {
            NativeNavigationHost.registerNavigation(messenger: registrar.messenger())
        }
```

Inside the private `register(with:ownsNavigation:)`, after the filter sheet
channel (or anywhere before the control factories), add the widget sheet
channel. Only the page engine owns it; a sheet engine's channel is installed
by the manager in `present`, so nested sheets reply to the right isolate:

```swift
        let widgetSheets: NativeWidgetSheet?
        if ownsNavigation {
            let widgetSheetChannel = FlutterMethodChannel(
                name: "adaptive_platform_ui/widget_sheet", binaryMessenger: registrar.messenger())
            let manager = NativeWidgetSheet(
                channel: widgetSheetChannel, hostProvider: { registrar.viewController })
            widgetSheetChannel.setMethodCallHandler { call, result in
                manager.handle(call, result: result)
            }
            widgetSheets = manager
        } else {
            // The owning sheet manager installs this engine's channel, so
            // nested presentation returns to the correct parent isolate.
            widgetSheets = nil
        }
```

If the plugin has a Duo title band helper that reads the host view controller,
point it at the page controller while a sheet is up:

```swift
        // iPhone Duo: where UIKit lays out a navigation title in this window
        // Measured in the page's view controller: while a native sheet is up,
        // the engine's own is the sheet.
        let titleBand = DuoTitleBand(
            hostProvider: { widgetSheets?.pageController ?? registrar.viewController })
```

Everything else in `register` (text field, action sheet, filter sheet, buttons,
switches, date picker, slider, segmented control, alert, popup menu, context
menu, blur view) stays as it is and runs for both engine kinds. Only
`registerNavigation`, the search tab factories, the tab bar factory and the
toolbar factory are inside `if ownsNavigation { ... }`.

**Check:** `/usr/bin/grep -n "registerSheetContent\|widget_sheet" <plugin file>`
shows both the static function and the channel name.

## Step 3: Dart, the package API

Create `packages/adaptive_platform_ui/lib/src/overlays/native_sheet/adaptive_native_sheet.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart'
    show
        MaterialPageRoute,
        ModalBottomSheetRoute,
        PopScope,
        kMinInteractiveDimension;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../../devices/duo/duo_layout.dart';
import '../../devices/duo/system_vertical_bar.dart';
import '../../navigation/app_bar/native_toolbar.dart';
import '../../navigation/chrome/hosted_top_toolbar.dart';
import '../../navigation/chrome/toolbar_registry.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A sheet that hosts any widget, with native platform views inside it.
///
/// On iOS the sheet is a real UIKit sheet with its own Flutter engine: [show]
/// sends [route] and codec-safe [arguments] to the app's `nativeSheetMain`
/// entrypoint, which calls [bootstrap] and builds the route inside
/// [AdaptiveNativeSheetContent]. UIKit owns the grabber, detents, dimming and
/// drag dismissal, and hides the sheet while the screen turns (see
/// `docs/sheet-rotation-cut-failed-attempts.md`). Widgets, closures and
/// notifiers cannot cross engines, so [decodeResult] restores the result in
/// the caller.
///
/// Elsewhere, and for a [fullScreen] sheet on every platform, [builder]
/// supplies the content in the caller's isolate as a Flutter route.
class AdaptiveNativeSheet {
  AdaptiveNativeSheet._();

  static const _channel = MethodChannel('adaptive_platform_ui/widget_sheet');
  static bool _hosted = false;
  static bool _closing = false;
  static Object? Function(Object?) _encodeResult = (value) => value;

  static final Set<Route<Object?>> _leavingRoutes = <Route<Object?>>{};
  static final ValueNotifier<bool> _leaving = ValueNotifier(false);

  /// True while a sheet shown by [show] slides away after it was popped.
  ///
  /// The page under it is current again from the moment of the pop, so its
  /// native tab bar would come back over the sheet as it slides down. The
  /// scaffold keeps the tab bar away until this is false.
  static ValueListenable<bool> get leaving => _leaving;

  static void _watchLeaving(TransitionRoute<Object?> route) {
    route.animation?.addStatusListener((status) {
      switch (status) {
        case AnimationStatus.reverse:
          _leavingRoutes.add(route);
        case AnimationStatus.dismissed:
          _leavingRoutes.remove(route);
        case AnimationStatus.forward:
        case AnimationStatus.completed:
          return;
      }
      _leaving.value = _leavingRoutes.isNotEmpty;
    });
  }

  /// Called once by `nativeSheetMain`, before building the sheet app.
  ///
  /// The returned map contains `route`, `arguments`, `detents`,
  /// `backgroundColor` and `brightness`. [encodeResult] converts the value
  /// passed to [pop] into StandardMessageCodec-compatible data.
  static Future<Map<String, dynamic>> bootstrap({
    required Object? Function(Object?) encodeResult,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    _hosted = true;
    _encodeResult = encodeResult;
    final configuration = await _channel.invokeMapMethod<String, dynamic>(
      'bootstrap',
    );
    if (configuration == null) {
      throw StateError('The native sheet has no configuration.');
    }
    return configuration;
  }

  /// Shows the sheet and completes after it has been dismissed, with the
  /// value given to [pop], or null when it was dragged away or tapped
  /// outside.
  ///
  /// A [fullScreen] sheet covers the whole screen and, like an [isDismissible]
  /// `false` sheet, only closes through [pop]. On iOS [route] is required and
  /// [arguments] must be StandardMessageCodec data.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? route,
    Object? arguments,
    T Function(Object)? decodeResult,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.fit,
    bool fullScreen = false,
    bool isDismissible = true,
    Color? backgroundColor,
  }) async {
    if (fullScreen) {
      // An opaque page on the root navigator. On iOS the page's native bar
      // stays over its top while it slides up; once it covers the screen the
      // page below leaves the stage, so the bar loses its owner and UIKit
      // hides it until the cover starts to slide away.
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
    if (AdaptiveStyle.of(context) == AdaptiveStyle.native) {
      if (route == null || route.isEmpty) {
        throw ArgumentError(
          'Native sheets require a route for nativeSheetMain.',
        );
      }
      // The page stays mounted with its own engine, metrics and native
      // controls. UIKit presents the sheet from a window of its own.
      final value = await _channel.invokeMethod<Object?>('present', {
        'route': route,
        'arguments': arguments,
        'detents': detents.name,
        'dismissible': isDismissible,
        'backgroundColor':
            (backgroundColor ??
                    CupertinoColors.systemBackground.resolveFrom(context))
                .toARGB32(),
        'brightness': CupertinoTheme.brightnessOf(context).name,
      });
      if (value == null) return null;
      return decodeResult == null ? value as T : decodeResult(value);
    }
    // Elsewhere the sheet is Flutter's own modal bottom sheet on the root
    // navigator.
    final fill =
        backgroundColor ??
        CupertinoColors.systemBackground.resolveFrom(context);
    if (detents == AdaptiveFilterDetents.fit) {
      // `showModalBottomSheet` with its route in hand, so the tab bar can
      // wait for the sheet to slide away (see [leaving]).
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = ModalBottomSheetRoute<T>(
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: isDismissible,
        enableDrag: isDismissible,
        isDismissible: isDismissible,
        backgroundColor: fill,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        barrierLabel: 'Dismiss',
        builder: (context) => PopScope(
          canPop: isDismissible,
          child: _BelowNativeBars(
            handle: isDismissible,
            child: ValueListenableBuilder<bool>(
              valueListenable: _leaving,
              builder: (context, leaving, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leaving)
                    const SizedBox(
                      height: 40,
                      width: double.infinity,
                      child: ColoredBox(color: Color(0xFFFF0000)),
                    ),
                  Flexible(child: child!),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: builder(context),
              ),
            ),
          ),
        ),
      );
      final result = navigator.push<T>(route);
      _watchLeaving(route);
      return result;
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
      backgroundColor: fill,
      isDismissible: isDismissible,
    );
  }

  /// Closes the sheet [context] is in, completing its [show] with [value].
  static Future<void> pop<T>(BuildContext context, [T? value]) async {
    if (!_hosted) {
      Navigator.of(context).pop<T>(value);
      return;
    }
    if (_closing) return;
    _closing = true;
    try {
      await _channel.invokeMethod<void>('dismiss', {
        'value': _encodeResult(value),
      });
    } finally {
      _closing = false;
    }
  }
}

/// Sheet content in its dedicated engine. UIKit supplies the real sheet,
/// grabber, detents, dimming and dismissal gestures.
///
/// Fit content scrolls once its natural height exceeds the native detent.
/// Safe areas come from this sheet's FlutterView, never from the page behind it.
class AdaptiveNativeSheetContent extends StatefulWidget {
  const AdaptiveNativeSheetContent({
    super.key,
    required this.child,
    this.fits = true,
    this.backgroundColor,
  });

  final Widget child;
  final bool fits;
  final Color? backgroundColor;

  @override
  State<AdaptiveNativeSheetContent> createState() =>
      _AdaptiveNativeSheetContentState();
}

class _AdaptiveNativeSheetContentState
    extends State<AdaptiveNativeSheetContent> {
  final _contentKey = GlobalKey();
  Timer? _heightTimer;
  double? _height;
  bool _measureScheduled = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    _heightTimer?.cancel();
    super.dispose();
  }

  void _scheduleMeasurement() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      if (widget.fits) {
        final box = _contentKey.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize && box.size.height.isFinite) {
          final height = box.size.height;
          if (_height == null || (height - _height!).abs() >= 0.5) {
            _height = height;
            _heightTimer?.cancel();
            if (!_ready) {
              _reportHeight(height);
            } else {
              _heightTimer = Timer(
                const Duration(milliseconds: 40),
                () => _reportHeight(height),
              );
            }
          }
        }
      }
      if (!_ready) {
        _ready = true;
        unawaited(AdaptiveNativeSheet._channel.invokeMethod<void>('ready'));
      }
    });
  }

  void _reportHeight(double height) {
    unawaited(
      AdaptiveNativeSheet._channel.invokeMethod<void>('setHeight', {
        'height': height,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return ColoredBox(
      color:
          widget.backgroundColor ??
          CupertinoColors.systemBackground.resolveFrom(context),
      child: widget.fits
          ? NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _scheduleMeasurement();
                return false;
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizeChangedLayoutNotifier(
                  child: KeyedSubtree(key: _contentKey, child: widget.child),
                ),
              ),
            )
          : widget.child,
    );
  }
}

/// Gap between the sheet's top and the native bar above it.
const double _inset = 8;

/// Caps a fit sheet's content so the sheet's top stays below the native bars
/// over the page, which UIKit draws above everything Flutter draws; taller
/// content scrolls. UIKit moves the bars when the screen turns, and the cap
/// follows them.
class _BelowNativeBars extends StatelessWidget {
  const _BelowNativeBars({required this.handle, required this.child});

  /// Whether the sheet shows Material's drag handle above [child].
  final bool handle;
  final Widget child;

  /// How far down the screen the native bars over the covered page reach:
  /// its navigation bar, with any large title, or on iPhone Duo the title
  /// band. Only the status bar when the page shows no native bar.
  double _barsBottom(BuildContext context, TopToolbarContent bar) {
    // The sheet's route has taken the status bar out of its padding.
    final statusBar = MediaQueryData.fromView(View.of(context)).viewPadding.top;
    if (DuoPoseScope.of(context) != null) {
      return SystemVerticalBar.titleBand.value?.contentTop ??
          statusBar + kMinInteractiveDimensionCupertino;
    }
    if (ToolbarRegistry.maybeOf(context) == null) {
      return nativeNavigationBarBottom.value ?? statusBar;
    }
    if (bar.isEmpty) return statusBar;
    return bar.scrollController?.navigationBarBottom.value ??
        nativeNavigationBarBottom.value ??
        statusBar + kHostedToolbarHeight;
  }

  @override
  Widget build(BuildContext context) {
    // While a sheet covers it, the page in front keeps owning the bar.
    final bar = TopToolbarContent.of(ToolbarRegistry.maybeOf(context)?.owner);
    final barBottom = bar.scrollController?.navigationBarBottom;
    return ListenableBuilder(
      listenable: Listenable.merge([
        nativeNavigationBarBottom,
        SystemVerticalBar.titleBand,
        if (barBottom != null) barBottom,
      ]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        // The sheet's drag handle sits above the content and takes a row.
        final handleHeight = handle ? kMinInteractiveDimension : 0.0;
        final room = math.max(
          0.0,
          media.size.height -
              media.viewInsets.bottom -
              _barsBottom(context, bar) -
              _inset -
              handleHeight,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room),
          child: child,
        );
      },
    );
  }
}
```

Then export it. In `packages/adaptive_platform_ui/lib/adaptive_platform_ui.dart`
add, next to the other overlay exports:

```dart
export 'src/overlays/native_sheet/adaptive_native_sheet.dart';
```

The file imports `AdaptiveFilterDetents` from the filter sheet. Make sure that
enum has a `fit` value:

```dart
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

If the package does not have `TopToolbarContent`, `ToolbarRegistry`,
`DuoPoseScope` or `SystemVerticalBar` (they are only used by
`_BelowNativeBars`, the non-iOS fallback), delete those four imports and
replace the body of `_barsBottom` with:

```dart
  double _barsBottom(BuildContext context) {
    final statusBar = MediaQueryData.fromView(View.of(context)).viewPadding.top;
    return nativeNavigationBarBottom.value ?? statusBar;
  }
```

and in `build` remove `bar` and the `barBottom` listenable, calling
`_barsBottom(context)` instead. `nativeNavigationBarBottom` lives in
`src/navigation/app_bar/native_toolbar.dart`.

**Check:** `cd packages/adaptive_platform_ui && flutter pub get && flutter analyze`
reports no errors (warnings about `package:flutter/material.dart` being
deprecated are fine).

## Step 4: App, the second Dart entrypoint

In `lib/main.dart` add the entrypoint next to `main`. The pragma is mandatory.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:native_widgets_on_duo/app/meridian_app.dart';
import 'package:native_widgets_on_duo/app/native_sheet_app.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BlocProvider(create: (_) => InvestmentBloc(), child: const MeridianApp()),
  );
}

/// Native sheets start their own isolate while the page keeps rendering.
@pragma('vm:entry-point')
void nativeSheetMain() {
  runNativeSheetApp();
}
```

**Check:** `/usr/bin/grep -n "vm:entry-point" lib/main.dart` prints the line.

## Step 5: App, the sheet app (route to widget)

Create `lib/app/native_sheet_app.dart`. This is the whole widget tree of a
sheet engine. Replace the routes in the `switch` with your own; keep the
structure.

```dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/features/activity/view/activity_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/markets/view/market_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/view/orders_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/sign_in/view/sign_in_sheet.dart';
import 'package:native_widgets_on_duo/features/watchlist/view/watchlist_filter_sheet.dart';

Future<void> runNativeSheetApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = await AdaptiveNativeSheet.bootstrap(
    encodeResult: NativeSheetCodec.encode,
  );
  runApp(_NativeSheetApp(configuration: configuration));
}

/// A sheet gets a dedicated widget tree and draft, without installing the
/// page's native navigation host in its engine.
class _NativeSheetApp extends StatefulWidget {
  const _NativeSheetApp({required this.configuration});

  final Map<String, dynamic> configuration;

  @override
  State<_NativeSheetApp> createState() => _NativeSheetAppState();
}

class _NativeSheetAppState extends State<_NativeSheetApp> {
  final _notifiers = <ChangeNotifier>[];
  late final Widget _content;

  ValueNotifier<T> _own<T>(T value) {
    final notifier = ValueNotifier(value);
    _notifiers.add(notifier);
    return notifier;
  }

  @override
  void initState() {
    super.initState();
    final argument = widget.configuration['arguments'];
    _content = switch (widget.configuration['route']) {
      'watchlist' => _watchlist(argument as Object),
      'activity' => _activity(argument as Object),
      'date' => DateSheetContent(
        chosen: _own(NativeSheetCodec.date(argument!)),
      ),
      'orders' => OrdersFilterContent(
        draft: _own(NativeSheetCodec.orders(argument!)),
      ),
      'accounts' => _accounts(argument as Object),
      'markets' => MarketFilterContent(
        draft: _own(NativeSheetCodec.markets(argument!)),
      ),
      'signIn' => const SignInContent(),
      final route => throw ArgumentError.value(route, 'route', 'Unknown sheet'),
    };
  }

  Widget _watchlist(Object argument) {
    final current = NativeSheetCodec.watchlist(argument);
    return WatchlistFilterContent(draft: _own(current));
  }

  Widget _activity(Object argument) {
    final current = NativeSheetCodec.activity(argument);
    return ActivityFilterContent(draft: _own(current));
  }

  Widget _accounts(Object argument) {
    final initial = NativeSheetCodec.accounts(argument);
    return AccountsSheetContent(
      chosen: _own(initial.isEmpty ? Account.values.toSet() : initial),
    );
  }

  @override
  void dispose() {
    for (final notifier in _notifiers) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const theme = AdaptiveThemeData(primaryColor: red, background: paper);
    final brightness = widget.configuration['brightness'] == 'dark'
        ? Brightness.dark
        : Brightness.light;
    final background = widget.configuration['backgroundColor'] as int?;
    final fits =
        widget.configuration['route'] != 'signIn' &&
        (widget.configuration['detents'] == null ||
            widget.configuration['detents'] == 'fit');
    return AdaptiveStyleScope(
      style: AdaptiveStyle.native,
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        theme: theme.cupertino(brightness),
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
          child: AdaptiveTheme(
            data: theme,
            child: Theme(data: theme.material(brightness), child: child!),
          ),
        ),
        home: AdaptiveNativeSheetContent(
          fits: fits,
          backgroundColor: background == null ? null : Color(background),
          child: _content,
        ),
      ),
    );
  }
}
```

Notes:

- `_own` makes a `ValueNotifier` the sheet owns and disposes. The page's
  notifier never reaches here.
- `AdaptiveStyleScope(style: AdaptiveStyle.native)` makes the package's
  controls use their native iOS views inside the sheet.
- `AdaptiveNativeSheetContent(fits: ...)` measures the content and reports its
  height for the `fit` detent, scrolls taller content, and sends `ready`.
- `localizationsDelegates: [DefaultMaterialLocalizations.delegate]` is needed
  because the content uses Material widgets inside a `CupertinoApp`.

**Check:** `flutter analyze lib` has no errors.

## Step 6: App, the codec

Create `lib/app/native_sheet_codec.dart`. One `encode` for every model and
result type that crosses engines, one decoder per model. This is the
reference app's codec; replace the models with yours and keep the pattern
(enums by `.name`, dates as ISO strings, sets as lists).

```dart
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

/// Sheet engines have independent isolates. Only these plain values cross
/// their platform channels; draft objects stay owned by their sheet.
abstract final class NativeSheetCodec {
  static Object? encode(Object? value) => switch (value) {
    null => null,
    WatchlistFilter filter => {
      'movement': filter.movement.name,
      'maxPrice': filter.maxPrice,
      'types': filter.types.map((type) => type.name).toList(),
    },
    MarketFilter filter => {
      'movement': filter.movement.name,
      'sort': filter.sort.name,
      'maxPrice': filter.maxPrice,
      'types': filter.types.map((type) => type.name).toList(),
      'minChange': filter.minChange,
      'symbols': filter.symbols.toList(),
    },
    ActivityFilter filter => {
      'kind': filter.kind.name,
      'symbols': filter.symbols.toList(),
      'period': filter.period.name,
      'minAmount': filter.minAmount,
      'since': filter.since?.toIso8601String(),
    },
    OrdersFilter filter => {
      'side': filter.side?.name,
      'sort': filter.sort.name,
      'minValue': filter.minValue,
      'limitOnly': filter.limitOnly,
      'showCancelled': filter.showCancelled,
      'accounts': filter.accounts.map((account) => account.name).toList(),
    },
    DateTime date => date.toIso8601String(),
    Set<Account> accounts => accounts.map((account) => account.name).toList(),
    String text => text,
    _ => throw ArgumentError.value(value, 'value', 'Unsupported sheet result'),
  };

  static Map<Object?, Object?> _map(Object value) =>
      Map<Object?, Object?>.from(value as Map);

  static Set<String> _strings(Object? value) =>
      (value as List).cast<String>().toSet();

  static WatchlistFilter watchlist(Object value) {
    final data = _map(value);
    return WatchlistFilter(
      movement: MarketMovement.values.byName(data['movement'] as String),
      maxPrice: (data['maxPrice'] as num).toDouble(),
      types: _strings(data['types']).map(HoldingType.values.byName).toSet(),
    );
  }

  static MarketFilter markets(Object value) {
    final data = _map(value);
    return MarketFilter(
      movement: MarketMovement.values.byName(data['movement'] as String),
      sort: MarketSort.values.byName(data['sort'] as String),
      maxPrice: (data['maxPrice'] as num).toDouble(),
      types: _strings(data['types']).map(HoldingType.values.byName).toSet(),
      minChange: (data['minChange'] as num).toDouble(),
      symbols: _strings(data['symbols']),
    );
  }

  static ActivityFilter activity(Object value) {
    final data = _map(value);
    return ActivityFilter(
      kind: ActivityKind.values.byName(data['kind'] as String),
      symbols: _strings(data['symbols']),
      period: ActivityPeriod.values.byName(data['period'] as String),
      minAmount: (data['minAmount'] as num).toDouble(),
      since: data['since'] == null ? null : date(data['since']!),
    );
  }

  static OrdersFilter orders(Object value) {
    final data = _map(value);
    return OrdersFilter(
      side: data['side'] == null
          ? null
          : OrderSide.values.byName(data['side'] as String),
      sort: OrderSort.values.byName(data['sort'] as String),
      minValue: (data['minValue'] as num).toDouble(),
      limitOnly: data['limitOnly'] as bool,
      showCancelled: data['showCancelled'] as bool,
      accounts: accounts(data['accounts']!),
    );
  }

  static DateTime date(Object value) => DateTime.parse(value as String);

  static Set<Account> accounts(Object value) =>
      _strings(value).map(Account.values.byName).toSet();
}
```

**Check:** for every `route` in the sheet app, the codec can encode the
argument the page sends and decode the value the sheet returns.

## Step 7: App, a content widget and how a page opens it

A content widget is a plain stateless widget that takes notifiers. The same
class is used by the page (on Android, through `builder`) and by the sheet
engine (on iOS, through the route). It closes itself with
`AdaptiveNativeSheet.pop(context, value)`.

Reference content, `lib/features/markets/view/market_filter_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

/// The sheet's content is a plain widget built from the package's native
/// controls: the segmented controls, slider and switches are real UIKit views
/// on iOS, drawn inside the native sheet like any other widget.
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<MarketFilter>(
    context: context,
    route: 'markets',
    arguments: NativeSheetCodec.encode(current),
    decodeResult: NativeSheetCodec.markets,
    builder: (_) => MarketFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class MarketFilterContent extends StatelessWidget {
  const MarketFilterContent({super.key, required this.draft});

  final ValueNotifier<MarketFilter> draft;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MarketFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.apply(assets).length,
      onReset: filter == const MarketFilter()
          ? null
          : () => draft.value = const MarketFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Gainers', 'Losers'],
          selectedIndex: filter.movement.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(movement: MarketMovement.values[i]),
        ),
        const SizedBox(height: 16),
        AdaptiveSegmentedControl(
          labels: const ['A-Z', 'Price', 'Change'],
          selectedIndex: filter.sort.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(sort: MarketSort.values[i]),
        ),
        const SizedBox(height: 24),
        label(
          filter.maxPrice >= MarketFilter.ceiling
              ? 'Any price'
              : 'Up to ${money(filter.maxPrice)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.maxPrice,
          min: 100,
          max: MarketFilter.ceiling,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
        ),
        const SizedBox(height: 8),
        _SwitchLine(
          text: 'Stocks',
          value: filter.types.contains(HoldingType.stock),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.stock, on),
          ),
        ),
        _SwitchLine(
          text: 'ETFs',
          value: filter.types.contains(HoldingType.etf),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.etf, on),
          ),
        ),
      ],
    ),
  );

  Set<HoldingType> _toggled(Set<HoldingType> set, HoldingType type, bool on) =>
      on ? {...set, type} : ({...set}..remove(type));
}

/// A title with a native switch at the trailing edge.
class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: label(text, size: 17),
        ),
      ),
      AdaptiveSwitch(value: value, onChanged: onChanged),
    ],
  );
}
```

Its shared frame, `lib/core/widgets/sheet_frame.dart`: title row, the caller's
rows, a full-width apply button, and a fixed-height `SwitchLine`. Everything in
it keeps one height at any width.

```dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

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

/// An icon and title with a native switch at the trailing edge. One fixed
/// row at any width, so a sheet holding it keeps its height when the screen
/// turns.
class SwitchLine extends StatelessWidget {
  const SwitchLine({
    super.key,
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
```

How the page opens it (from the reference above):

```dart
Future<void> openFilters() async {
  final result = await showMarketFilterSheet(context, filter);
  if (result != null && mounted) setState(() => filter = result);
}
```

Nested sheet: a content widget may call `AdaptiveNativeSheet.show` again with
another route (the Activity sheet opens a `date` sheet this way). The nested
sheet gets its own engine and window above the first; its result returns to
the first sheet's engine, whose draft is untouched.

Full-screen sheet: pass `fullScreen: true` (the reference sign-in uses it).
That is a Flutter page route on the root navigator, not a UIKit sheet, and it
only closes through `pop`.

**Check:** `flutter analyze` is clean, then build and run on an iOS simulator:
open the sheet, change a control, tap apply, and confirm the page shows the
new value. Drag the sheet down: the `show` future completes with `null`.

## Step 8: Rotation, required changes to the navigation host

On a real iPhone running iOS 26 or later, a rotation lays a picture of the old
screen over the new layout and fades it out. Anything that moves or stretches
under that picture during the first half of the turn shows as a cut line.
Flutter's view stretches its last frame to the animating bounds by default,
and UIKit moves a sheet to its new frame at once. These changes keep both
still until Flutter draws the new size, half way through the turn. They are
all public API. The sheet side is already inside `NativeWidgetSheet.swift`
(`freezeForTurn`, `snapAfterTurn`). The page side is below.

### 8a. Pin the page's Flutter view

In `.../Navigation/NativeNavigationContent.swift` (the controller whose view is
the native scroll view that holds the page's `FlutterViewController`), make
`attachFlutter` set the content mode and background, and pin overlays:

```swift
    func attachFlutter(_ controller: FlutterViewController) {
        loadViewIfNeeded()
        flutter = controller
        if controller.parent !== self {
            addChild(controller)
            backingScroll.viewport.addSubview(controller.view)
            controller.view.frame = backingScroll.viewport.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.didMove(toParent: self)
        }
        // While the screen turns, UIKit animates this view's bounds but
        // Flutter keeps drawing the old size until half way through the turn.
        // Keep that frame unscaled at the top left, where UIKit's picture of
        // the old screen shows it, instead of stretching it to the moving
        // bounds; the band the view grows by shows the page colour.
        controller.view.contentMode = .topLeft
        controller.view.backgroundColor = backingScroll.backgroundColor
        FlutterTurnPinning.pinOverlays(in: controller.view)
        setNeedsStatusBarAppearanceUpdate()
        backingScroll.setNeedsLayout()
        backingScroll.layoutIfNeeded()
    }
```

Add this override to the same class:

```swift
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        // Before UIKit lays the turn out, so no overlay follows the bounds.
        if let flutter { FlutterTurnPinning.pinOverlays(in: flutter.view) }
        super.viewWillTransition(to: size, with: coordinator)
    }
```

Keep the background in step with the page colour:

```swift
    func setNativeBackground(style: UIUserInterfaceStyle) {
        // Resolve the exposed native background without overriding traits on
        // the scroll view that contains Flutter's appearance observer.
        backingScroll.backgroundColor = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
        flutter?.view.backgroundColor = backingScroll.backgroundColor
    }
```

Add this helper at the end of the same file:

```swift
/// Keeps every Flutter-drawn layer of a Flutter view still while the view's
/// bounds animate through a turn. The view's own layer is pinned with
/// `contentMode`; this pins the overlay views Flutter's compositor adds for
/// pixels drawn over a native control (a segmented control on a page, say),
/// which the engine creates with flexible autoresizing, so they would
/// stretch with the bounds and part from UIKit's picture of the old screen.
/// The compositor sets their frames on every frame it draws, so they need
/// no autoresizing.
enum FlutterTurnPinning {
    static func pinOverlays(in view: UIView) {
        for subview in view.subviews
        where NSStringFromClass(type(of: subview)).contains("FlutterOverlayView") {
            subview.autoresizingMask = []
            subview.contentMode = .topLeft
            pinOverlays(in: subview)
        }
    }
}
```

Why `contentMode` and not `layer.contentsGravity`: on iOS the gravity
constants are named for macOS's flipped axis, so `.topLeft` on the layer pins
the visual bottom-left. `UIView.contentMode` picks the right constant.

### 8b. Tag bar metrics with the Flutter view size

UIKit lays the navigation bar out for the new size at the start of the turn,
while Flutter keeps the old size until half way. If Dart applied the new bar
inset at once, the page would be laid out at the old size under the new bar
for the first half. So the native side tags each reading with the Flutter
view's size, and Dart holds a reading until it draws that size.

In `.../Navigation/iOS26ToolbarPlatformView.swift`, add
`private var lastViewSize: CGSize?` next to `lastInset` and `lastBarBottom`,
and make the reporting method:

```swift
    func nativeNavigationLayout(contentInset: CGFloat, barBottom: CGFloat) {
        guard contentInset > 0, barBottom > 0 else { return }
        // The size of the Flutter view the bar was measured against. While
        // the screen turns UIKit measures the new size before Flutter draws
        // it; Dart holds the reading until it does.
        let viewSize = NativeNavigationHost.installed?.flutter.view.bounds.size ?? .zero
        if metricsGeneration != scrollGeneration || lastInset != contentInset
            || lastBarBottom != barBottom || lastViewSize != viewSize {
            metricsGeneration = scrollGeneration
            lastInset = contentInset
            lastBarBottom = barBottom
            lastViewSize = viewSize
            var arguments: [String: Any] = [
                "contentInset": Double(contentInset), "barBottom": Double(barBottom),
                "generation": scrollGeneration
            ]
            if viewSize.width > 0, viewSize.height > 0 {
                arguments["viewWidth"] = Double(viewSize.width)
                arguments["viewHeight"] = Double(viewSize.height)
            }
            channel.invokeMethod("onNavigationMetrics", arguments: arguments)
        }
    }
```

In `packages/adaptive_platform_ui/lib/src/navigation/app_bar/native_toolbar.dart`,
make `_NativeToolbarState` a `WidgetsBindingObserver`
(`class _NativeToolbarState extends State<NativeToolbar> with WidgetsBindingObserver`),
add the field:

```dart
  /// A bar reading UIKit measured for a size this view is not drawing yet.
  ///
  /// As the screen turns, UIKit lays the bar out for the new size at once,
  /// while Flutter keeps the old size until half way through the turn. The
  /// reading waits for that size, so the page is laid out once, with the
  /// size and the bar together, and never at the old size under the new bar.
  Map<Object?, Object?>? _pendingMetrics;
```

add these methods (replace the existing `initState`):

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController?.addListener(_syncScroll);
  }

  @override
  void didChangeMetrics() {
    final pending = _pendingMetrics;
    if (pending == null || !mounted || !_measuredAtViewSize(pending)) return;
    _pendingMetrics = null;
    _applyNavigationMetrics(pending);
  }

  /// Whether [args] were measured at the size this view draws now. Readings
  /// without a size are taken as measured at the current size.
  bool _measuredAtViewSize(Map<Object?, Object?> args) {
    final width = (args['viewWidth'] as num?)?.toDouble();
    final height = (args['viewHeight'] as num?)?.toDouble();
    if (width == null || height == null) return true;
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    return (size.width - width).abs() < 1 && (size.height - height).abs() < 1;
  }

  void _applyNavigationMetrics(Map<Object?, Object?> args) {
    final inset = (args['contentInset'] as num?)?.toDouble();
    final bottom = (args['barBottom'] as num?)?.toDouble();
    if (!mounted ||
        args['generation'] != _scrollGeneration ||
        inset == null ||
        bottom == null ||
        !inset.isFinite ||
        !bottom.isFinite ||
        inset <= 0 ||
        bottom <= 0) {
      return;
    }
    nativeNavigationBarBottom.value = bottom;
    final controller = widget.scrollController;
    controller?.contentTopInset.value = inset;
    controller?.navigationBarBottom.value = bottom;
    setState(() {});
  }
```

call `WidgetsBinding.instance.removeObserver(this);` first thing in `dispose`,
and make the channel handler case:

```dart
      case 'onNavigationMetrics':
        final args = call.arguments;
        if (args is! Map<Object?, Object?>) break;
        if (_measuredAtViewSize(args)) {
          _pendingMetrics = null;
          _applyNavigationMetrics(args);
        } else {
          _pendingMetrics = args;
        }
        break;
```

### 8c. Tab bar while a sheet is up

The native tab bar steps aside while a sheet is current and comes back only
once a popped Flutter-drawn sheet has slid away. In the scaffold that decides
whether to show the native tab bar (`native_scaffold.dart` in this fork):

```dart
    // sheet rises over the tab bar, so the tab bar follows this rule alone,
    // and it stays away while a popped sheet is still sliding down.
    final showNativeView =
        (isCurrentRoute && !AdaptiveNativeSheet.leaving.value) || isPopping;
```

and listen to `AdaptiveNativeSheet.leaving` in `initState` / `dispose` so the
scaffold rebuilds when it changes. If your fork has no such scaffold, skip 8c.

**Check:** `flutter analyze` is clean for the package and the app, and an iOS
device build succeeds. Rotation cannot be judged on the simulator (it never
takes the old-screen picture); judge it on a real phone.

## Step 9: Build and install

Dart: `flutter pub get` in the app and in `packages/adaptive_platform_ui`,
then `flutter analyze` in both. On Flutter `main` (3.50 and later)
`ChangeNotifier` lives in the `listen` package; running `pub get` in the
package folder is what makes the analyser see it.

iOS: build the Runner workspace for a simulator (Debug) to check it compiles,
then build Release for the connected phone and install without launching.
Build errors in `NativeWidgetSheet.swift` usually mean a missing helper
(`UIColor(argb:)`, `AdaptivePlatformUiPlugin.registerSheetContent`) from steps
1 and 2.

## Step 10: Add a new sheet later (the routine)

1. Make the content widget (step 7 shape). Fixed-height rows only.
2. Add `encode` and a decoder for its argument and result in the codec.
3. Add a `case 'yourRoute' => YourContent(draft: _own(...))` to the sheet app.
4. Call `AdaptiveNativeSheet.show(context: context, route: 'yourRoute',
   arguments: NativeSheetCodec.encode(current), decodeResult: NativeSheetCodec.yours,
   builder: (_) => YourContent(draft: draft))` from the page.
5. `flutter analyze`, build, open it, apply, rotate on a phone.

## 11. Final checklist

- [ ] `NativeWidgetSheet.swift` exists and compiles; `registerSheetContent` exists.
- [ ] `adaptive_native_sheet.dart` exists and is exported; `AdaptiveFilterDetents.fit` exists.
- [ ] `nativeSheetMain` has `@pragma('vm:entry-point')` and calls `runNativeSheetApp`.
- [ ] Every route used by a page has a case in `native_sheet_app.dart` and codec functions.
- [ ] Opening a sheet on an iOS simulator shows a UIKit sheet with the content; apply returns the value; drag down returns null.
- [ ] A sheet opened from inside a sheet returns its value to the first sheet.
- [ ] `fullScreen: true` opens a full-screen page that only `pop` closes.
- [ ] Step 8 changes are in: `contentMode = .topLeft` on the page view, overlays pinned, bar metrics tagged and held, sheet frozen then snapped.
- [ ] No `Wrap`, chips, `AnimatedSize` or collapsible section inside a `fit` sheet.
- [ ] `flutter analyze` clean in app and package; iOS Release build installed on the phone.

## Known limits

- The simulator never shows the rotation cut, so only a phone can judge step 8.
- A sheet's content cannot read the page's state except through `arguments`.
- Flutter main (3.50 pre) was used for the reference; the engine's half-way
  viewport hold (`FlutterViewController.viewWillTransitionToSize`) is relied
  on as behaviour, not called.
