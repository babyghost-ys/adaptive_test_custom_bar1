# Building the native sheet

Instructions for an AI agent that must add a native sheet to a Flutter app, the way
this repository does. The parent app passes one plain Flutter `Widget`. The package
decides how to present it and how tall to make it. Follow the steps in order. Every
code listing is complete and can be copied as is.

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
  controls (`AdaptiveSegmentedControl`, `AdaptiveSlider`, `AdaptiveSwitch`). Those
  render as real UIKit views inside the sheet with no extra work.
* **The height** follows the widget. The package measures it. When the content grows
  (an expanding section, more rows) the sheet animates taller. Past the screen height
  it rests at full height and the content scrolls. The parent passes no height.
* Closing: call `AdaptiveNativeSheet.pop(context, value)` from inside the widget, or
  the user drags the sheet down (the call returns `null`).

## How it works

A native UIKit sheet cannot contain Flutter widgets by itself. So the sheet's content
is a second `FlutterViewController` on the same `FlutterEngine`:

1. Dart asks the plugin to present. Swift creates a `FlutterViewController` for the
   engine and presents it as a `.pageSheet`. Presenting it makes the engine render into
   the sheet. The page behind it keeps its last frame.
2. Dart then draws the caller's widget as a full-window layer. That layer is part of the
   same widget tree and the same isolate as the rest of the app, so the widget keeps its
   closures, state and blocs.
3. Dart measures the widget's height and sends it to Swift (`setHeight`). Swift resizes
   a custom detent to match, animated.
4. When the sheet closes, Swift hands the engine back to the page's own view controller.

```
page
  |  AdaptiveNativeSheet.show(builder: widget)
  v
AdaptiveNativeSheet (Dart)
  |-- iOS ----> MethodChannel "adaptive_platform_ui/widget_sheet"
  |               present {detents, height} --> NativeWidgetSheet.swift
  |                                              presents a FlutterViewController sheet
  |               setHeight {height}          --> resizes the "fit" detent
  |               dismiss                       --> dismisses, hands the engine back
  |               <-- dismissedByUser           (dragged away)
  |   active.value = entry  -->  AdaptiveNativeSheetLayer (in AdaptiveToolbarHost)
  |                              draws the widget over the whole window
  '-- other ---> showModalBottomSheet(builder)  (Flutter, same widget)
```

## Build steps

Do these in order.

1. Add the Swift presenter to the package.
2. Register its channel in the plugin.
3. Add the Dart API and export it.
4. Add the detent enum value.
5. Mount the layer in the toolbar host.
6. In the app, write the sheet's widget and open it from a page.
7. Verify on iOS and Android.

## Step 1: the Swift presenter

Create `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift`.

```swift
// packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift
import Flutter
import UIKit

/// A real UIKit sheet (`UISheetPresentationController`) whose content is the
/// app's own Flutter widget.
///
/// The sheet's content is a second `FlutterViewController` on the same
/// engine. Only one view controller can drive an engine at a time, so while
/// the sheet is up the engine renders into the sheet, and the page behind it
/// keeps its last frame. Dart pushes the caller's widget as a full-window
/// route, which therefore fills the sheet, and runs in the same isolate as the
/// rest of the app, so the widget keeps its closures, its state and its blocs.
/// When the sheet goes, the engine is handed back to the original view
/// controller.
final class NativeWidgetSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private weak var originalHost: FlutterViewController?
    private weak var engine: FlutterEngine?
    private var sheet: UIViewController?

    /// The one controller that ever hosts a sheet. When a FlutterViewController
    /// is released, Flutter destroys an engine that may not run headless, so it
    /// is created once and kept for the life of the app, and reused.
    private var persistent: FlutterViewController?

    /// Height of the "fit" detent: what Dart measured for the content.
    private var fitHeight: CGFloat = 320

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
        guard sheet == nil else {
            result(FlutterError(code: "busy", message: "A widget sheet is already open", details: nil))
            return
        }
        guard let host = hostProvider() as? FlutterViewController,
              let presenter = topPresenter(from: host), !presenter.isBeingDismissed else {
            result(FlutterError(code: "unavailable", message: "No Flutter view to present from", details: nil))
            return
        }

        let engine: FlutterEngine = host.engine
        let controller = persistent
            ?? FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        persistent = controller
        // Becoming the engine's view controller again if it already hosted a
        // sheet before.
        engine.viewController = controller
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            switch args["detents"] as? String ?? "halfAndFull" {
            case "full":
                sheet.detents = [.large()]
            case "fit":
                fitHeight = CGFloat((args["height"] as? NSNumber)?.doubleValue ?? 320)
                if #available(iOS 16.0, *) {
                    let fit = UISheetPresentationController.Detent.Identifier("fit")
                    sheet.detents = [
                        .custom(identifier: fit) { [weak self] context in
                            min(context.maximumDetentValue, self?.fitHeight ?? 320)
                        },
                        .large(),
                    ]
                    sheet.selectedDetentIdentifier = fit
                } else {
                    sheet.detents = [.medium(), .large()]
                }
            case "short":
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom(identifier: UISheetPresentationController.Detent.Identifier("short")) {
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

        originalHost = host
        self.engine = engine
        sheet = controller
        controller.view.backgroundColor = .systemBackground
        presenter.present(controller, animated: true)
        // Answer as soon as the engine has moved into the sheet, not when the
        // slide-up finishes: Dart switches the sheet's content on at that
        // point, so the sheet never shows the page it is about to cover.
        result(nil)
    }

    /// The content's height changed: resize the "fit" detent to it, animated.
    private func setHeight(_ args: [String: Any], result: @escaping FlutterResult) {
        defer { result(nil) }
        guard let height = (args["height"] as? NSNumber)?.doubleValue,
              abs(CGFloat(height) - fitHeight) > 0.5 else { return }
        fitHeight = CGFloat(height)
        guard #available(iOS 16.0, *), let sheet = sheet?.sheetPresentationController else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
    }

    private func dismiss(result: @escaping FlutterResult) {
        guard let sheet else {
            result(nil)
            return
        }
        sheet.dismiss(animated: true) { [weak self] in
            self?.restoreEngine()
            result(nil)
        }
    }

    /// The user dragged the sheet away.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        restoreEngine()
        channel.invokeMethod("dismissedByUser", arguments: nil)
    }

    /// Hands the engine back to the page's own view controller. The sheet's
    /// controller stays alive in [persistent]; releasing it would destroy the
    /// engine.
    private func restoreEngine() {
        sheet = nil
        guard let engine, let originalHost else { return }
        engine.viewController = originalHost
        // Re-attach the page's rendering surface. FlutterViewController does
        // this when it appears; it did not go away, so ask for it directly.
        let selector = NSSelectorFromString("surfaceUpdated:")
        if originalHost.responds(to: selector) {
            typealias Call = @convention(c) (AnyObject, Selector, Bool) -> Void
            let call = unsafeBitCast(originalHost.method(for: selector), to: Call.self)
            call(originalHost, selector, true)
        }
        originalHost.viewWillAppear(false)
        originalHost.viewDidAppear(false)
        originalHost.view.setNeedsLayout()
        originalHost.view.layoutIfNeeded()
    }
}
```

## Step 2: register the channel

In `register(with:)` of `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Plugin/AdaptivePlatformUiPlugin.swift`, add:

```swift
        let widgetSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/widget_sheet", binaryMessenger: registrar.messenger())
        let widgetSheets = NativeWidgetSheet(
            channel: widgetSheetChannel, hostProvider: { registrar.viewController })
        widgetSheetChannel.setMethodCallHandler { call, result in
            widgetSheets.handle(call, result: result)
        }
```

## Step 3: the Dart API

Create `packages/adaptive_platform_ui/lib/src/overlays/native_sheet/adaptive_native_sheet.dart`. It holds
`AdaptiveNativeSheet` (`show`, `pop`, `active`), the entry type, the layer that draws the
widget, and the widget that measures it.

```dart
// packages/adaptive_platform_ui/lib/src/overlays/native_sheet/adaptive_native_sheet.dart
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
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

  /// The widget the native sheet is showing, or null. `AdaptiveToolbarHost`
  /// draws it over the whole window, which on iOS is the sheet: the engine
  /// renders into the sheet while one is up.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> active =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// True while a native sheet is showing. Chrome the app paints over its
  /// pages (such as the Duo bar strip) must not draw over the sheet.
  static bool get isShowingNow => active.value != null;

  /// Shows [builder]'s widget in the sheet. Returns the value passed to [pop],
  /// or null when the sheet is dragged away.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.fit,
    Color? backgroundColor,
  }) async {
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      if (detents == AdaptiveFilterDetents.fit) {
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          useSafeArea: true,
          showDragHandle: true,
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
      );
    }
    if (active.value != null) return null;

    final done = Completer<T?>();
    final entry = AdaptiveNativeSheetEntry._(
      builder: builder,
      backgroundColor: backgroundColor,
      fits: detents == AdaptiveFilterDetents.fit,
      complete: (value) {
        if (!done.isCompleted) done.complete(value as T?);
      },
    );
    _channel.setMethodCallHandler((call) async {
      // The user dragged the sheet down: it is already gone.
      if (call.method == 'dismissedByUser' && active.value == entry) {
        active.value = null;
        entry.complete(null);
      }
      return null;
    });
    try {
      await _channel.invokeMethod<void>('present', {
        'detents': detents.name,
        // Until the widget has been measured, open at the height the last
        // sheet measured, so a repeat open does not visibly resize.
        'height': _lastOpenHeight > 0 ? _lastOpenHeight : 320.0,
      });
    } on PlatformException {
      _channel.setMethodCallHandler(null);
      return null;
    }
    active.value = entry;
    try {
      return await done.future;
    } finally {
      if (active.value == entry) active.value = null;
      _channel.setMethodCallHandler(null);
    }
  }

  static Timer? _heightTimer;
  static double _lastHeight = 0;
  static double _lastOpenHeight = 0;

  /// Tells UIKit the content's height, so the "fit" detent follows it. Debounced:
  /// an animating widget changes size every frame.
  static void _reportHeight(double height) {
    if ((height - _lastHeight).abs() < 0.5) return;
    _lastHeight = height;
    _lastOpenHeight = height;
    _heightTimer?.cancel();
    _heightTimer = Timer(const Duration(milliseconds: 40), () {
      if (active.value == null) return;
      _channel
          .invokeMethod<void>('setHeight', {'height': height})
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
    final entry = active.value;
    if (entry == null) return;
    if (AdaptiveStyle.of(context) == AdaptiveStyle.native) {
      // Let UIKit finish dismissing first, so the sheet never shows the page
      // behind it as it leaves.
      try {
        await _channel.invokeMethod<void>('dismiss');
      } on PlatformException {
        // Already gone.
      }
    }
    active.value = null;
    entry.complete(value);
  }
}

/// One open native sheet: the caller's widget and how to finish it.
class AdaptiveNativeSheetEntry {
  AdaptiveNativeSheetEntry._({
    required this.builder,
    required this.backgroundColor,
    required this.fits,
    required this.complete,
  });

  /// Whether the sheet's height follows [builder]'s widget.
  final bool fits;
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final void Function(Object? value) complete;
}

/// Fills the window, which on iOS is the sheet, with the caller's widget.
///
/// Placed above the app by `AdaptiveToolbarHost`. It has its own [Overlay], so
/// widgets that need one (tooltips, menus) work inside it, and it drops the
/// side insets the page below carries, since the sheet floats inside the window
/// and is not part of the strip the system reserves for a vertical bar.
class AdaptiveNativeSheetLayer extends StatelessWidget {
  const AdaptiveNativeSheetLayer({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AdaptiveNativeSheetEntry?>(
        valueListenable: AdaptiveNativeSheet.active,
        builder: (context, entry, _) {
          if (entry == null) return const SizedBox.shrink();
          final mq = MediaQuery.of(context);
          return Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(left: 0, right: 0),
                viewPadding: mq.viewPadding.copyWith(left: 0, right: 0),
              ),
              child: ColoredBox(
                color:
                    entry.backgroundColor ??
                    CupertinoColors.systemBackground.resolveFrom(context),
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) => entry.fits
                          ? _FitContent(child: entry.builder(context))
                          : entry.builder(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// Lays [child] out at its natural height and reports it, so the native sheet
/// can follow it. Scrolls when the sheet is capped at full height.
class _FitContent extends StatefulWidget {
  const _FitContent({required this.child});
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
        AdaptiveNativeSheet._reportHeight(box.size.height);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    AdaptiveNativeSheet._lastHeight = 0;
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

Export it in `packages/adaptive_platform_ui/lib/adaptive_platform_ui.dart`:

```dart
export 'src/overlays/native_sheet/adaptive_native_sheet.dart';
```

## Step 4: the detent enum

`AdaptiveNativeSheet.show` takes `AdaptiveFilterDetents`, defined in
`packages/adaptive_platform_ui/lib/src/overlays/filter_sheet/adaptive_filter_sheet.dart`. It must contain `fit`,
which is the default for the native sheet:

```dart
/// How tall a filter sheet rests.
enum AdaptiveFilterDetents {
  /// Half height, draggable to full height.
  halfAndFull,

  /// Full height only.
  full,

  /// A short sheet that fits a single control.
  short,

  /// Follows the height of its content, and grows to full height when the
  /// content is taller. Only [AdaptiveNativeSheet] measures content; elsewhere
  /// it rests at half height.
  fit,
}
```

## Step 5: mount the layer in the toolbar host

The layer must sit above everything the app draws, inside the same `Stack` that holds
the navigator and the native toolbar. The strip the host paints for the iPhone Duo must
not draw over the sheet, because the engine renders into the sheet while it is up.

Edit `packages/adaptive_platform_ui/lib/src/navigation/chrome/adaptive_toolbar_host.dart`: import the sheet file,
listen to `AdaptiveNativeSheet.active` for the strip colour, and add
`AdaptiveNativeSheetLayer` after the toolbar. The complete file:

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

  /// The app's bar colour where it asks for the Duo strip to be filled.
  Color? _stripColor(BuildContext context) {
    final bar = AdaptiveTheme.of(context).barStyle;
    return bar.fillsDuoStrip ? bar.color : null;
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
                  valueListenable: AdaptiveNativeSheet.active,
                  builder: (context, sheet, _) => _BarStrip(
                    pose: pose,
                    // The engine renders into a native sheet while one is up.
                    color: sheet != null ? null : _stripColor(context),
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
/// the app's bar colour, so the bar reads as one band down that edge. Draws
/// nothing without a pose or a colour, and never takes a touch.
class _BarStrip extends StatelessWidget {
  const _BarStrip({required this.pose, required this.color});

  final DuoPose? pose;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pose = this.pose;
    final color = this.color;
    if (pose == null || color == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: pose.onLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: SizedBox(
          width: pose.stripWidth,
          height: double.infinity,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
```

## Step 6: the app

### A frame for the sheet's content

A widget that takes its natural height, so the sheet can fit it: a title with a reset
icon, the caller's children, and a full-width apply button that shows a live count.

```dart
// lib/core/widgets/sheet_frame.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// The shell of a filter sheet's content: a title with a reset icon, the
/// caller's [children], and a full-width apply button showing [count]. It
/// takes its natural height, so a sheet can fit it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.children,
    required this.count,
    required this.onApply,
    this.onReset,
  });

  final List<Widget> children;
  final int count;
  final VoidCallback onApply;

  /// Null disables the reset icon.
  final VoidCallback? onReset;

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
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
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

### The sheet's widget, with the package's native controls

The widget is stateless. The draft filter lives in a `ValueNotifier` that the open
function creates and disposes. The segmented controls, slider and switches are the
package's own, so on iOS they are real UIKit controls inside the sheet.

```dart
// lib/features/markets/view/market_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

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

### The filter model (pure data)

```dart
// lib/features/markets/models/market_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

enum MarketMovement { all, gainers, losers }

enum MarketSort { symbol, price, change }

class MarketFilter extends Equatable {
  const MarketFilter({
    this.movement = MarketMovement.all,
    this.sort = MarketSort.symbol,
    this.maxPrice = ceiling,
    this.types = const {},
    this.minChange = floor,
    this.symbols = const {},
  });

  static const double ceiling = 600;
  static const double floor = -5;

  final MarketMovement movement;
  final MarketSort sort;
  final double maxPrice;

  /// Empty means every type.
  final Set<HoldingType> types;
  final double minChange;

  /// Empty means every symbol.
  final Set<String> symbols;

  int get activeCount =>
      (movement != MarketMovement.all ? 1 : 0) +
      (sort != MarketSort.symbol ? 1 : 0) +
      (maxPrice < ceiling ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (minChange > floor ? 1 : 0) +
      (symbols.isEmpty ? 0 : 1);

  MarketFilter copyWith({
    MarketMovement? movement,
    MarketSort? sort,
    double? maxPrice,
    Set<HoldingType>? types,
    double? minChange,
    Set<String>? symbols,
  }) => MarketFilter(
    movement: movement ?? this.movement,
    sort: sort ?? this.sort,
    maxPrice: maxPrice ?? this.maxPrice,
    types: types ?? this.types,
    minChange: minChange ?? this.minChange,
    symbols: symbols ?? this.symbols,
  );

  List<Asset> apply(List<Asset> source) {
    final result = source
        .where(
          (a) =>
              a.price <= maxPrice &&
              a.change >= minChange &&
              (types.isEmpty || types.contains(holdingType(a))) &&
              (symbols.isEmpty || symbols.contains(a.symbol)) &&
              switch (movement) {
                MarketMovement.all => true,
                MarketMovement.gainers => a.change > 0,
                MarketMovement.losers => a.change < 0,
              },
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        MarketSort.symbol => a.symbol.compareTo(b.symbol),
        MarketSort.price => b.price.compareTo(a.price),
        MarketSort.change => b.change.compareTo(a.change),
      },
    );
    return result;
  }

  @override
  List<Object> get props => [
    movement,
    sort,
    maxPrice,
    types,
    minChange,
    symbols,
  ];
}
```

### The page

The page keeps the filter, opens the sheet, and rebuilds with the result. It never says
how the sheet is presented or how tall it is.

```dart
// lib/features/markets/view/markets_page.dart
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/markets/view/market_filter_sheet.dart';

class Markets extends StatefulWidget {
  const Markets({super.key});
  @override
  State<Markets> createState() => _MarketsState();
}

class _MarketsState extends State<Markets> {
  MarketFilter filter = const MarketFilter();

  Future<void> openFilters() async {
    final result = await showMarketFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'markets',
    children: [
      section('Market overview', 'Demo prices'),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: metric('S&P 500', '5,892.16')),
          const SizedBox(width: 12),
          Expanded(child: metric('NASDAQ', '18,421.09')),
        ],
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 150,
        child: CustomPaint(painter: ChartPainter(seed: 7, filled: true)),
      ),
      const SizedBox(height: 24),
      FilterSectionHeader(
        title: 'Explore',
        onPressed: openFilters,
        activeCount: filter.activeCount,
      ),
      const SizedBox(height: 8),
      ...filter.apply(assets).map((a) => AssetRow(asset: a)),
      if (filter.apply(assets).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Icon(Icons.search_off_rounded, size: 40, color: muted),
        ),
    ],
  );
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

### A sheet whose height changes with its content

The Watchlist sheet has a "more" section that opens and closes. The sheet grows and
shrinks with it.

```dart
// lib/features/watchlist/models/watchlist_filter.dart
import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

class WatchlistFilter extends Equatable {
  const WatchlistFilter({
    this.movement = MarketMovement.all,
    this.maxPrice = ceiling,
    this.types = const {},
  });

  static const double ceiling = 600;

  final MarketMovement movement;
  final double maxPrice;

  /// Empty means every type.
  final Set<HoldingType> types;

  int get activeCount =>
      (movement == MarketMovement.all ? 0 : 1) +
      (maxPrice < ceiling ? 1 : 0) +
      (types.isEmpty ? 0 : 1);

  WatchlistFilter copyWith({
    MarketMovement? movement,
    double? maxPrice,
    Set<HoldingType>? types,
  }) => WatchlistFilter(
    movement: movement ?? this.movement,
    maxPrice: maxPrice ?? this.maxPrice,
    types: types ?? this.types,
  );

  bool allows(Asset a) =>
      a.price <= maxPrice &&
      (types.isEmpty || types.contains(holdingType(a))) &&
      switch (movement) {
        MarketMovement.all => true,
        MarketMovement.gainers => a.change > 0,
        MarketMovement.losers => a.change < 0,
      };

  @override
  List<Object> get props => [movement, maxPrice, types];
}
```

```dart
// lib/features/watchlist/view/watchlist_filter_sheet.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

/// A native sheet that follows the height of the widget it is given. The
/// widget is plain Flutter, stateless, and owned by the app: the draft and the
/// open state live in notifiers made here.
Future<WatchlistFilter?> showWatchlistFilterSheet(
  BuildContext context,
  WatchlistFilter current,
) {
  final draft = ValueNotifier(current);
  final more = ValueNotifier(
    current.maxPrice < WatchlistFilter.ceiling || current.types.isNotEmpty,
  );
  return AdaptiveNativeSheet.show<WatchlistFilter>(
    context: context,
    builder: (_) => WatchlistFilterContent(draft: draft, more: more),
  ).whenComplete(() {
    draft.dispose();
    more.dispose();
  });
}

class WatchlistFilterContent extends StatelessWidget {
  const WatchlistFilterContent({
    super.key,
    required this.draft,
    required this.more,
  });

  final ValueNotifier<WatchlistFilter> draft;
  final ValueNotifier<bool> more;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WatchlistFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: assets.where(filter.allows).length,
      onReset: filter == const WatchlistFilter()
          ? null
          : () => draft.value = const WatchlistFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        ChipGroup<MarketMovement>(
          options: const [
            (MarketMovement.all, Icons.all_inclusive_rounded, 'All'),
            (MarketMovement.gainers, Icons.north_east_rounded, 'Gainers'),
            (MarketMovement.losers, Icons.south_east_rounded, 'Losers'),
          ],
          isSelected: (m) => filter.movement == m,
          onTap: (m) => draft.value = filter.copyWith(movement: m),
        ),
        OpenSection(
          open: more,
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipGroup<HoldingType>(
                options: const [
                  (HoldingType.stock, Icons.business_rounded, 'Stocks'),
                  (HoldingType.etf, Icons.pie_chart_outline_rounded, 'ETFs'),
                ],
                isSelected: filter.types.contains,
                onTap: (t) => draft.value = filter.copyWith(
                  types: filter.types.contains(t)
                      ? ({...filter.types}..remove(t))
                      : {...filter.types, t},
                ),
              ),
              const SizedBox(height: 16),
              label(
                filter.maxPrice >= WatchlistFilter.ceiling
                    ? 'Any price'
                    : 'Up to ${money(filter.maxPrice)}',
                size: 28,
                weight: FontWeight.w600,
              ),
              Slider(
                value: filter.maxPrice,
                min: 100,
                max: WatchlistFilter.ceiling,
                onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
```

## Rules the implementation must follow

**Swift**

* One `FlutterViewController` drives an engine at a time. Present the sheet's controller
  and let it take the engine. Never create a second engine.
* Keep the sheet's `FlutterViewController` alive for the life of the app (`persistent`).
  Releasing a `FlutterViewController` destroys the engine, which crashes the app.
* On close, set `engine.viewController` back to the page's controller synchronously, and
  re-attach its surface. Do it on both paths: `dismiss` and drag to dismiss.
* Answer the `present` call as soon as presenting starts, not when the slide-up finishes.
  Dart switches the sheet's content on at that point, so the sheet never shows the page it
  covers as it rises.
* Give the controller's view a solid background so nothing blank flashes.
* Build the `fit` detent with `UISheetPresentationController.Detent.custom`, read its
  height from a property, and resize it by changing that property then calling
  `animateChanges { sheet.invalidateDetents() }`. Always offer `.large()` as well, so
  content taller than the screen scrolls.
* Resolve the presenting view controller at call time, not during plugin registration.
  Present from the topmost presented controller and refuse a second sheet.
* Guard `#available(iOS 16.0, *)` for custom detents and fall back to `.medium()`.

**Dart**

* The widget is not a route. If it is pushed as one, the page behind stops being the
  current route and the package hides its navigation bar. Draw it as a layer in the
  toolbar host instead.
* The layer has its own `Overlay`, so tooltips and menus inside the sheet work, and it
  drops the left and right insets, because the sheet floats inside the window and is not
  part of the strip the system reserves for a vertical bar.
* Measure the content with a `GlobalKey` and `SizeChangedLayoutNotifier`, wrapped in a
  `SingleChildScrollView`. Report the height after the frame and debounce it, because an
  animating widget changes size every frame.
* Open at the last measured height so a repeat open does not visibly resize.
* Clear the channel handler when the sheet is done.
* `pop` waits for UIKit to finish dismissing before it completes the result.
* Off iOS, show `showModalBottomSheet` with `useRootNavigator: true` so the sheet covers
  the bottom bar, and make `pop` call `Navigator.pop`.
* While a native sheet is up, do not paint chrome over the window (the Duo strip).

**App**

* Keep the sheet's widget stateless. Put the draft and any open or closed state in
  `ValueNotifier`s created by the open function and disposed when the sheet completes.
* The apply button's count comes from the same filter function the page uses.
* Use the package's `Adaptive` controls for anything that should look native on iOS.
* Respect the system colour scheme. Do not force light or dark.

## Step 7: verify

```sh
flutter analyze lib packages/adaptive_platform_ui/lib
```

Run on real runtimes and check each item on every sheet:

* it opens with its content already inside, with no flash of the page behind it;
* native controls inside the widget respond (segmented, slider, switch);
* choosing an option changes the apply count and applying filters the list;
* the sheet's height follows the content when a section opens or closes;
* dragging the sheet away returns `null` and the page stays usable;
* reopening works, and remembers the current filter;
* the top navigation bar stays visible behind the dimming, and on the iPhone Duo the
  vertical bar and its strip too.

iOS: build and run with XcodeBuildMCP on an iPhone simulator and the iPhone Duo. Use
`snapshot_ui` to read control labels, switches and the live count, and record the open
animation with `record_sim_video`, then look at the frames. Re-read the screenshot
orientation before computing tap coordinates, because a rotated simulator misplaces taps.
Native switches need a short press (about 0.15 seconds) in the simulator.

Android:

```sh
export PATH=$PATH:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator
emulator -avd Medium_Phone_API_35 -no-snapshot-save -no-audio &
flutter run -d emulator-5554 --debug
adb -s emulator-5554 shell input tap 964 792
adb -s emulator-5554 exec-out screencap -p > shot.png
```

Wait for the app to finish installing before sending taps. Android screenshot
coordinates are physical pixels (1080 by 2400 on the test emulators).

## Adding a sheet to another page: checklist

1. Write the pure data filter model with `activeCount`, `copyWith` and an apply method.
2. Write the sheet's widget, stateless, taking `ValueNotifier`s from its open function.
3. Write `show<Name>Sheet` that creates the notifiers, calls `AdaptiveNativeSheet.show`
   with `builder: (_) => <Name>Content(...)`, and disposes the notifiers in `whenComplete`.
4. In the page state, keep the filter, call the show function from `openFilters`, and
   rebuild with the result when it is not `null`.
5. Place `FilterSectionHeader(title: ..., onPressed: openFilters, activeCount: filter.activeCount)`.
6. Run the verification steps.
