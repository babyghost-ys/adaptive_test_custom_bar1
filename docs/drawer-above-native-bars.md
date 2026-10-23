# Keeping the drawer above the native bars on iOS 26

Instructions for an AI agent. On iOS 26 and later, `AdaptiveScaffold` draws its navigation
bar and tab bar as native UIKit views. A native view always sits above everything Flutter
draws, and the side menu (the drawer) is drawn by Flutter, so it cannot simply be placed
above them. The package gets the same result another way: UIKit cuts the bars open where
the drawer's panel is, and dims the rest. The panel then shows through, above the bars.

Before this fix the bars were only cut open when the widget passed to
`AdaptiveScaffold.drawer` was itself an `AdaptiveDrawer`. An app that kept its menu in a
widget of its own, such as `drawer: AppDrawer()` whose `build` returns
`AdaptiveDrawer.custom(...)`, failed that check. On iOS 26 its drawer then slid in under
the tab bar and the navigation bar. On earlier iOS versions the bars are drawn by Flutter,
so the drawer sat above them and the bug never showed.

This guide makes the cut-out follow the drawer panel itself, whatever widget it is wrapped
in.

## Result

* iOS 26 and later: any drawer given to `AdaptiveScaffold.drawer` shows above the native
  bars. That covers an `AdaptiveDrawer.custom`, one wrapped in the app's own widget (a
  `StatelessWidget`, a `Builder`, a `BlocBuilder`), and a plain Material `Drawer`.
* The dimmed area beside the panel, the tap-outside-to-close behaviour and the status bar
  colour all work for those drawers too.
* iPhone Duo: the vertical bar is cut open in the same way.
* Earlier iOS and Android: nothing changes.
* An item-based `AdaptiveDrawer` (one built with `sections:`) still only opens as the
  fully native panel when it is passed to `drawer:` directly. Wrapped, it shows as a
  Flutter drawer above the bars instead, which also looks right.

## How it works

1. `NativeDrawerCover` (Swift) lays a dimmed backdrop over the window and masks the bars
   so the panel's column is open. It needs the panel's left edge, its width and its
   colour. The colour only decides whether the status bar text over the panel is dark or
   light.
2. `DrawerCoverReporter` (Dart) measures its own position every frame while the drawer
   moves, and sends those to the native side over the `setDrawerCover` method call.
   When the drawer has gone it sends `clearDrawerCover`.
3. Before the fix, `AdaptiveDrawer.custom` put the reporter inside itself, so only that
   widget could report. The scaffold only set things up when `drawer is AdaptiveDrawer`.
   That is a type check on the exact widget passed in, so any wrapper defeated it.
4. After the fix, the scaffold puts the reporter around whatever drawer it is given.
   Material's `DrawerController` lays the drawer out at its own width and slides it, so
   the reporter's box is exactly the panel's box, wherever the panel came from.
5. The panel's colour can no longer come from the reporter's constructor, because the
   scaffold does not know it. `DrawerCoverPulse`, which the scaffold already shares with
   the drawer through `DrawerCoverScope`, gains a `panelColor` field. An
   `AdaptiveDrawer.custom` anywhere inside the drawer sets it as it builds. Any other
   drawer falls back to the theme's drawer colour.

## Changes

### 1. `lib/src/navigation/drawer/drawer_cover.dart`

Import Material instead of only widgets, because the reporter now reads the theme:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'adaptive_drawer.dart';
```

Give the pulse a place for the panel's colour:

```dart
/// A [ChangeNotifier] others can ask to notify, for [DrawerCoverScope].
class DrawerCoverPulse extends ChangeNotifier {
  void ping() => notifyListeners();

  /// The panel's colour, when the drawer says what it is. An
  /// [AdaptiveDrawer.custom] anywhere in the drawer sets it as it builds.
  /// Null falls back to the theme's drawer colour.
  Color? panelColor;
}
```

Update the scope's doc comment, since it now wraps any drawer:

```dart
/// Tells the drawer it is on a native page: its panel lies beneath the
/// native bars, so UIKit cuts them open where the panel is. The scaffold
/// puts it around whatever drawer it is given, wrapped in the app's own
/// widgets or not, together with a [DrawerCoverReporter] that follows the
/// panel.
class DrawerCoverScope extends InheritedWidget {
```

Make the reporter take the pulse and the open-check directly, instead of a scope and a
colour:

```dart
/// Follows its own left edge, which is the drawer panel's, frame by frame
/// while it moves, and has UIKit cut the bars open there.
///
/// It wraps the drawer itself, so it is laid out at the panel's size.
class DrawerCoverReporter extends StatefulWidget {
  const DrawerCoverReporter({
    super.key,
    required this.pulse,
    required this.isOpen,
    required this.child,
  });

  /// Pinged whenever the drawer may have started to move.
  final DrawerCoverPulse pulse;

  /// Whether the drawer is open or opening, as its owner last heard.
  final bool Function() isOpen;
  final Widget child;
```

In `_DrawerCoverReporterState`, replace every `widget.scope.pulse` with `widget.pulse`,
`oldWidget.scope.pulse` with `oldWidget.pulse`, and `widget.scope.isOpen()` with
`widget.isOpen()`. Then report the colour from the pulse, falling back to the theme:

```dart
      AdaptiveDrawer.reportCover(
        x: x,
        width: width,
        color:
            widget.pulse.panelColor ??
            AdaptiveDrawer.defaultBackground(Theme.of(context)),
      );
```

### 2. `lib/src/navigation/drawer/adaptive_drawer.dart`

Add one place that works out a drawer's default colour, next to the channel constant:

```dart
  /// The panel colour a drawer without its own takes from [theme].
  static Color defaultBackground(ThemeData theme) =>
      theme.drawerTheme.backgroundColor ??
      (theme.useMaterial3
          ? theme.colorScheme.surfaceContainerLow
          : theme.canvasColor);
```

In `build`, in the `child != null` branch (`AdaptiveDrawer.custom`), use it, hand the
colour to the pulse, and stop wrapping the content in a reporter of its own:

```dart
      final cover = DrawerCoverScope.maybeOf(context);
      final color = backgroundColor ?? defaultBackground(theme);
      // The scaffold's reporter, around the whole drawer, tells UIKit the
      // panel's colour so the status bar stays legible over it.
      cover?.pulse.panelColor = color;
      // ... the MediaQuery / SafeArea `content` stays as it was ...
      return Drawer(
        width: _width(context),
        backgroundColor: color,
        shape: cover == null ? null : const RoundedRectangleBorder(),
        child: content,
      );
```

Setting `panelColor` during `build` is safe: it is a plain field, nothing listens to it,
and the reporter reads it on its next frame.

### 3. `lib/src/navigation/scaffold/adaptive_scaffold.dart`

In `_wrapWithDrawerIfNeeded`, cover the bars for any drawer on the native path, and put
the reporter around it:

```dart
    var drawer = _nativeDrawer == null ? widget.drawer : null;
    // On iOS 26+ the bars are UIKit views above everything Flutter draws,
    // the drawer panel included, so UIKit cuts them open where the panel
    // is. That follows the panel itself, so it works for any drawer: an
    // AdaptiveDrawer, one wrapped in the app's own widget, or a plain
    // Drawer.
    final coversBars = _native && drawer != null;
    if (coversBars) {
      drawer = DrawerCoverScope(
        pulse: _drawerPulse,
        isOpen: () => _customDrawerOpen,
        child: DrawerCoverReporter(
          pulse: _drawerPulse,
          isOpen: () => _customDrawerOpen,
          child: drawer,
        ),
      );
    }
```

Nothing else in that method changes. `coversBars` already drives the transparent Material
scrim (UIKit draws the backdrop instead), the tap-outside handler and the pointer
listener, so all of those now apply to every drawer.

Extend the `drawer` property's doc comment:

```dart
  ///
  /// On iOS 26 and later the bars are native views above the drawer, so
  /// they are cut open where its panel is and the panel shows above them.
  /// That works for any drawer, including one wrapped in the app's own
  /// widget. Only an item-based [AdaptiveDrawer] passed here directly opens
  /// as the native panel.
  final Widget? drawer;
```

### 4. Native side

Nothing changes in Swift. `NativeNavigationHost` handles `setDrawerCover` and
`clearDrawerCover` as before, and `NativeDrawerCover` sizes its masks from the window.

### 5. Tests: `test/navigation/drawer/drawer_cover_test.dart`

The test host is not iOS, so the scaffold never takes the native path in a widget test.
Test what it builds on that path instead: a Material `Scaffold` whose drawer is a
`DrawerCoverScope` around a `DrawerCoverReporter` around the drawer under test, with the
`adaptive_platform_ui/navigation` channel mocked to record calls. Cover three cases:

* An `AdaptiveDrawer.custom(width: 300, backgroundColor: ...)` inside the app's own
  `StatelessWidget`. After `openDrawer()` the last `setDrawerCover` has `x` 0, `width`
  300, and `background` equal to that colour, which proves the colour crossed the
  wrapper.
* A plain `Drawer(width: 280)`. The last `setDrawerCover` has `width` 280 and
  `background` equal to `AdaptiveDrawer.defaultBackground(theme)`.
* After `closeDrawer()` the last call is `clearDrawerCover`.

## What an app needs to do

Nothing, once it uses a package with this fix. Pass the menu to `drawer:` however the app
prefers:

```dart
AdaptiveScaffold(
  drawer: const AppDrawer(), // returns AdaptiveDrawer.custom(...) in its build
  // ...
)
```

Two things are still worth knowing:

* Prefer `AdaptiveDrawer.custom` inside the wrapper over a plain `Drawer`. It squares the
  panel's corners when it covers the bars and tells the native side its exact colour. A
  plain Material 3 `Drawer` keeps its rounded trailing corners, and the bars show through
  the small gap they leave. Give it `shape: const RoundedRectangleBorder()` to avoid that.
* An item-based `AdaptiveDrawer(sections: ...)` only opens as the fully native UIKit
  panel when it is passed to `drawer:` directly.

### Workaround for a package without this fix

Pass `AdaptiveDrawer.custom` straight to `drawer:` and move what the wrapper did into its
`child`:

```dart
AdaptiveScaffold(
  drawer: const AdaptiveDrawer.custom(
    backgroundColor: Color(0xFFEEEDE7),
    child: AppMenuContent(), // the wrapper's content, not the wrapper
  ),
  // ...
)
```

## Verify

1. Run `flutter analyze` and `flutter test` in the package. All tests pass.
2. In the app, temporarily wrap the drawer, for example
   `drawer: Builder(builder: (_) => const AdaptiveDrawer.custom(...))`.
3. On an iOS 26 simulator, open the drawer. The panel shows above the navigation bar and
   the tab bar, the rest of the screen is dimmed, and the status bar text is legible over
   the panel. Tapping the dimmed area closes the drawer.
4. Rotate with the drawer open. The cut-out and the backdrop follow the new size.
5. On an iPhone Duo simulator, open the drawer. The top band is cut open where the panel
   is, and the vertical bar stays intact.
6. Remove the temporary wrapper.
