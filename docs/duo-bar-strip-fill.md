# Filling the iPhone Duo bar strip from the app's bar colour

Instructions for an AI agent. On iPhone Duo the system reserves a strip at one edge of
the window for the vertical control bar. Without this change the strip shows the page
background (off-white), while the top bar above it is the app's solid colour (red). This
guide makes that strip take the app's bar colour, so the bar reads as one band from the
top of the window down the strip. The colour comes from the parent app's theme. The
package never hard-codes one.

## Result

* iPhone Duo (inner display, and the cover display while folded): the strip is painted
  with `AdaptiveThemeData.barStyle.color`.
* Any other iPhone, iPad and Android: nothing changes, because there is no strip.
* The native vertical bar's buttons, the status cluster and the camera cutout are drawn
  on top of the strip. The strip never takes a touch.
* An app that does not want the fill passes `fillsDuoStrip: false`.

## How it works

1. `DuoLayout.resolvePose` already decides, from the safe-area insets and the system's
   vertical bar edge, whether a Duo vertical bar is present, which side it is on
   (`DuoBarSide.left` or `.right`) and how wide its strip is (`DuoPose.stripWidth`).
2. `AdaptiveToolbarHost` already resolves that pose once and shares it. It stacks the
   app's navigator and then the native toolbar.
3. Add a third layer between them: a strip, aligned to the pose's side, `stripWidth`
   wide, full height, filled with the bar colour.
4. The bar colour is read from `AdaptiveTheme.of(context).barStyle`, which the app sets
   once on `AdaptiveApp`. `AdaptiveBarStyle.solid` gains `fillsDuoStrip` (default `true`)
   so an app can opt out. `AdaptiveBarStyle.system()` has no colour, so it never fills.

```
Stack
  |- _BarInset(pose, child: navigator)          page content, kept out of the strip
  |- Positioned.fill(_BarStrip(pose, color))    NEW: the coloured strip, no touches
  '- HostedTopToolbar                           native bar, status cluster, camera
```

The strip must always be in the `Stack`, even with no pose or no colour (then it draws
nothing). Adding and removing it as the pose changes would shift the toolbar's position
in the element tree and rebuild it.

## Step 1: add `fillsDuoStrip` to the bar style

Edit `packages/adaptive_platform_ui/lib/src/core/theme/adaptive_theme.dart`. The three changes are:

* the `system()` constructor sets `fillsDuoStrip = false`;
* the `solid()` constructor takes `this.fillsDuoStrip = true`;
* the field, `==` and `hashCode` include it.

The complete file after the change:

```dart
// packages/adaptive_platform_ui/lib/src/core/theme/adaptive_theme.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// How navigation bars look across the app.
@immutable
class AdaptiveBarStyle {
  /// The platform's own bar: Liquid Glass on iOS 26+, the classic bar on
  /// earlier iOS, the theme's app bar on Android.
  const AdaptiveBarStyle.system()
    : color = null,
      foreground = null,
      shadow = false,
      plainButtons = false,
      fillsDuoStrip = false;

  /// A solid [color] bar with [foreground] title, back button and actions.
  /// [shadow] draws a subtle shadow below it; [plainButtons] removes the
  /// glass background behind its buttons on iOS 26+.
  ///
  /// On iPhone Duo the system reserves a strip at one edge of the window for
  /// the vertical bar. [fillsDuoStrip] paints that strip with [color], so the
  /// bar reads as one band from the top of the window down the strip. Pass
  /// false to leave the strip in the page background.
  const AdaptiveBarStyle.solid(
    Color this.color, {
    this.foreground,
    this.shadow = false,
    this.plainButtons = false,
    this.fillsDuoStrip = true,
  });

  final Color? color;
  final Color? foreground;
  final bool shadow;
  final bool plainButtons;

  /// Whether the iPhone Duo vertical bar strip is painted with [color].
  final bool fillsDuoStrip;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveBarStyle &&
      color == other.color &&
      foreground == other.foreground &&
      shadow == other.shadow &&
      plainButtons == other.plainButtons &&
      fillsDuoStrip == other.fillsDuoStrip;

  @override
  int get hashCode =>
      Object.hash(color, foreground, shadow, plainButtons, fillsDuoStrip);
}

/// The app's look, set once on `AdaptiveApp` and shared by every platform.
///
/// `AdaptiveApp` derives its Material and Cupertino themes from this, so an
/// app states its colours once. Explicit Material or Cupertino themes passed
/// to `AdaptiveApp` still win.
@immutable
class AdaptiveThemeData {
  const AdaptiveThemeData({
    this.primaryColor,
    this.background,
    this.barStyle = const AdaptiveBarStyle.system(),
  });

  /// Accent for controls, selected tabs and links. Null keeps the platform
  /// default (system blue on iOS, the Material baseline on Android).
  final Color? primaryColor;

  /// Page background. Null keeps the platform default.
  final Color? background;

  final AdaptiveBarStyle barStyle;

  /// Cupertino theme for [brightness].
  CupertinoThemeData cupertino(Brightness brightness) => CupertinoThemeData(
    brightness: brightness,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: background,
  );

  /// Material theme for [brightness].
  ThemeData material(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: primaryColor == null
        ? null
        : ColorScheme.fromSeed(
            seedColor: primaryColor!,
            brightness: brightness,
          ),
    scaffoldBackgroundColor: background,
  );

  @override
  bool operator ==(Object other) =>
      other is AdaptiveThemeData &&
      primaryColor == other.primaryColor &&
      background == other.background &&
      barStyle == other.barStyle;

  @override
  int get hashCode => Object.hash(primaryColor, background, barStyle);
}

/// Provides the current [AdaptiveThemeData]. `AdaptiveApp` installs it.
class AdaptiveTheme extends InheritedWidget {
  const AdaptiveTheme({super.key, required this.data, required super.child});

  final AdaptiveThemeData data;

  static const _fallback = AdaptiveThemeData();

  /// The nearest theme, or the platform defaults when none is installed.
  static AdaptiveThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveTheme>()?.data ??
      _fallback;

  @override
  bool updateShouldNotify(AdaptiveTheme oldWidget) => data != oldWidget.data;
}
```

## Step 2: paint the strip in the toolbar host

Edit `packages/adaptive_platform_ui/lib/src/navigation/chrome/adaptive_toolbar_host.dart`:

* import `../../core/theme/adaptive_theme.dart`;
* add `_stripColor`, which returns the bar colour only when `fillsDuoStrip` is true;
* insert `Positioned.fill(child: _BarStrip(...))` between `_BarInset` and the hosted
  toolbar;
* add the `_BarStrip` widget at the end of the file.

The complete file after the change:

```dart
// packages/adaptive_platform_ui/lib/src/navigation/chrome/adaptive_toolbar_host.dart
import '../../core/theme/adaptive_theme.dart';
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
                child: _BarStrip(pose: pose, color: _stripColor(context)),
              ),
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

## The pose the strip depends on

`DuoPose` and `DuoLayout.resolvePose` are existing code. They are included so you can see
what `pose.onLeft`, `pose.stripWidth` and `pose.reservedBySystem` mean. Do not change
them for this feature.

```dart
// packages/adaptive_platform_ui/lib/src/devices/duo/duo_layout.dart
import 'package:flutter/cupertino.dart';

import 'system_vertical_bar.dart';

/// Width of the strip the vertical control bar lives in when the system
/// reserves none: the leading pane in Split View, or a missing inset. Matches
/// the hardware strip of the inner display (the bar's centre sits 48 points
/// from the edge in both), which the system mirrors there. Where the system
/// does reserve the strip, the bar takes the width of that inset instead.
const double kDuoVerticalBarWidth = 84.0;

/// The edge of the window the system reserves for vertical controls.
enum DuoBarSide { left, right }

/// The resolved iPhone Duo layout for a window: which edge the vertical bar is
/// on and how wide its strip is.
@immutable
class DuoPose {
  const DuoPose({
    required this.side,
    required this.stripWidth,
    required this.reservedBySystem,
  });

  final DuoBarSide side;

  /// Width of the strip the bar sits in.
  final double stripWidth;

  /// True when the strip is a system safe-area inset, holding the status
  /// cluster or camera. False in the leading Split View pane: the system
  /// wants a vertical bar there, but only adds its inset for bars it draws
  /// itself, never for a Flutter view.
  final bool reservedBySystem;

  bool get onLeft => side == DuoBarSide.left;

  /// [insets] with the strip added on the bar's side: the inset UIKit would
  /// have reserved for a vertical bar it draws itself.
  EdgeInsets addStrip(EdgeInsets insets) => onLeft
      ? insets.copyWith(left: insets.left + stripWidth)
      : insets.copyWith(right: insets.right + stripWidth);

  @override
  bool operator ==(Object other) =>
      other is DuoPose &&
      other.side == side &&
      other.stripWidth == stripWidth &&
      other.reservedBySystem == reservedBySystem;

  @override
  int get hashCode => Object.hash(side, stripWidth, reservedBySystem);

  @override
  String toString() =>
      '${side.name} ${stripWidth.toStringAsFixed(0)}pt '
      '(${reservedBySystem ? 'system strip' : 'bar-only strip'})';
}

/// Layout decisions for iPhone Duo.
abstract final class DuoLayout {
  /// The Duo layout for a window, or null where bars stay horizontal.
  ///
  /// The safe-area insets decide where they name a side ([barSide]). The
  /// system's own [edge] only adds a vertical pose where they name none, which
  /// is the leading Split View pane: it has no side inset, so the edge is the
  /// only signal there. The insets win because they arrive with the frame,
  /// while the edge comes on its own channel and can be a frame stale after a
  /// pane move.
  static DuoPose? resolvePose(
    EdgeInsets viewPadding,
    SystemVerticalBarEdge edge,
  ) {
    final side =
        barSide(viewPadding) ??
        switch (edge) {
          SystemVerticalBarEdge.left => DuoBarSide.left,
          SystemVerticalBarEdge.right => DuoBarSide.right,
          SystemVerticalBarEdge.none || SystemVerticalBarEdge.unknown => null,
        };
    if (side == null) return null;
    final inset = side == DuoBarSide.left
        ? viewPadding.left
        : viewPadding.right;
    return DuoPose(
      side: side,
      stripWidth: inset > 0 ? inset : kDuoVerticalBarWidth,
      reservedBySystem: inset > 0,
    );
  }

  /// The edge the safe-area insets alone put the bar on, or null where they
  /// say bars stay horizontal. [resolvePose] trusts it first and consults the
  /// system's vertical bar edge only when this returns null.
  ///
  /// Decided from what the system actually reserves rather than from a device
  /// or size class. On iPhone Duo the controls stay aligned with the hardware:
  /// the window has an inset on one side only, with no top inset. That strip
  /// holds the camera and status cluster, and measurements put it on the right
  /// in every pose that has it: the inner display in both landscape rotations,
  /// and the cover display while folded. A pane that does not touch the
  /// hardware strip reports no inset at all, which is why the leading Split
  /// View pane (the one real left-bar case) needs the system's edge instead.
  /// The strip is absent where bars stay horizontal:
  ///
  /// * any other iPhone in portrait has a top inset, and in landscape has
  ///   equal insets on both sides;
  /// * an iPad has no side inset;
  /// * the Duo inner display in portrait has a top inset.
  ///
  /// A left inset is handled too, although no pose has been observed to
  /// report one.
  ///
  /// Pass the *view* padding: it is known on the very first frame, and unlike
  /// `padding` it is not consumed by a `SafeArea` further up the tree.
  static DuoBarSide? barSide(EdgeInsets viewPadding) {
    if (viewPadding.top != 0) return null;
    if (viewPadding.right > 0 && viewPadding.left == 0) return DuoBarSide.right;
    if (viewPadding.left > 0 && viewPadding.right == 0) return DuoBarSide.left;
    return null;
  }
}

/// Hands the resolved [DuoPose] to everything below, so the bar, the title
/// and the page body agree on one decision instead of re-reading insets the
/// host may have adjusted.
class DuoPoseScope extends InheritedWidget {
  const DuoPoseScope({super.key, required this.pose, required super.child});

  /// The pose in effect, or null where bars stay horizontal.
  final DuoPose? pose;

  /// The nearest scope, or null when there is none. Tells "no scope" apart
  /// from a scope whose pose is null (a decision for horizontal bars).
  static DuoPoseScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoPoseScope>();

  /// The pose in effect here. Without a scope, derived from the insets alone.
  static DuoPose? of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope.pose;
    return DuoLayout.resolvePose(
      MediaQuery.viewPaddingOf(context),
      SystemVerticalBarEdge.unknown,
    );
  }

  @override
  bool updateShouldNotify(DuoPoseScope oldWidget) => pose != oldWidget.pose;
}

/// The band at the top of the page that holds the title on iPhone Duo, as
/// UIKit lays it out in this window: the title at the leading edge with the
/// controls in the trailing bar, and the page content below it.
///
/// The positions come from a native navigation controller measured in the
/// window ([SystemVerticalBar.titleBand]). Until that reading arrives, they
/// follow Flutter's own navigation bar: content below the status area and
/// one bar height, and the title centred in that bar.
abstract final class DuoTitleBand {
  /// The measured band, or the fallback for [context].
  static DuoTitleBandMetrics of(BuildContext context) {
    final measured = SystemVerticalBar.titleBand.value;
    if (measured != null) return measured;
    final top = MediaQuery.viewPaddingOf(context).top;
    final barMid = top + kMinInteractiveDimensionCupertino / 2;
    return DuoTitleBandMetrics(
      contentTop: top + kMinInteractiveDimensionCupertino,
      largeTitleMidY: barMid,
      inlineTitleMidY: barMid,
      titleMinX: NavigationToolbar.kMiddleSpacing,
    );
  }
}
```

## Step 3: set the colour in the parent app

The app states its bar colour once. Nothing else is needed.

```dart
// lib/app/meridian_app.dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/router.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';

class MeridianApp extends StatelessWidget {
  const MeridianApp({super.key});
  @override
  Widget build(BuildContext context) => AdaptiveApp.router(
    routerConfig: router,
    title: 'Meridian',
    themeMode: ThemeMode.light,
    theme: const AdaptiveThemeData(
      primaryColor: red,
      background: paper,
      barStyle: AdaptiveBarStyle.solid(
        red,
        foreground: Colors.white,
        shadow: true,
        plainButtons: true,
      ),
    ),
  );
}
```

To turn the fill off while keeping a solid bar:

```dart
barStyle: AdaptiveBarStyle.solid(
  red,
  foreground: Colors.white,
  shadow: true,
  plainButtons: true,
  fillsDuoStrip: false,
),
```

## Rules

* Read the colour from `AdaptiveTheme`, never from a constant. The app owns it.
* Keep the strip in the `Stack` at a fixed position, always built, so the toolbar after
  it keeps its place in the element tree as the pose changes.
* Wrap the strip in `IgnorePointer`. It sits above the page, so it must not block taps.
* Place the strip below the hosted toolbar so the native bar's buttons stay on top.
* Draw the strip only when `pose != null` and the colour is non-null.
* Use `pose.stripWidth` for the width and `pose.onLeft` for the side. Do not assume the
  right edge: the leading Split View pane puts the bar on the left.
* Do not add a rounded box, border or shadow to the strip. It is a plain full-bleed band.

## Verify

```sh
flutter analyze lib packages/adaptive_platform_ui/lib
```

Then run the app on three targets and compare:

1. **iPhone Duo simulator (portrait and landscape).** The strip down the vertical bar
   edge is the bar colour, continuous with the top bar. Switch tabs and push a page: the
   strip stays. Open a sheet: the strip dims with the rest of the window.
2. **A normal iPhone simulator.** No strip appears.
3. **An Android emulator.** No strip appears.

Check that the native bar's buttons are readable on the new background. The selected
tab's icon uses the app's accent colour. When that is also the bar colour, it sits on a
pale tint of the same hue and has lower contrast than the unselected icons, so pick an
accent for the selected item that contrasts with the bar if that matters.
