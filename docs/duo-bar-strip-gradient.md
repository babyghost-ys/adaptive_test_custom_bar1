# Filling the iPhone Duo bar strip with a gradient

Instructions for an AI agent, and a follow-up to `duo-bar-strip-fill.md`.

Well done on the strip. If you have worked through that guide, the iPhone Duo vertical
bar strip now takes the app's bar colour, and the bar reads as one band from the top of
the window down the edge. That was the structural work: resolving the pose, keeping the
strip at a stable place in the tree, and staying out of the way of touches and the
native controls. With that foundation in place, this guide moves on to polish. The
strip can now carry a gradient chosen by the parent app, and the join between the bar
and the strip becomes completely seamless.

Apply this guide only to a codebase that already paints the Duo strip with the app's bar
colour (the `_BarStrip` widget in `AdaptiveToolbarHost` and
`AdaptiveBarStyle.fillsDuoStrip`). If that is not in place yet, follow
`duo-bar-strip-fill.md` first.

After this change the parent app can pass a gradient for the strip. The top bar stays
the solid bar colour, because it is a native UIKit bar. The strip runs into it with no
visible edge:

* no shadow across the strip where the bar ends, while the bar's shadow over the page
  content stays;
* no step in colour where the bar ends, because the gradient starts there.

An app that passes no gradient gets exactly the solid strip it had before.

## Why two fixes are needed

Painting the strip with a gradient alone leaves a visible edge at the bottom of the top
bar, for two separate reasons.

1. **The shadow.** On iPhone Duo the top bar is a real `UINavigationBar` spanning the
   full window width, including the strip. With `shadow: true` UIKit draws the bar's
   shadow image under the bar's full width, so it crosses the strip as a dark band.
   This is fixed natively: the part of the shadow over the strip is masked out.
2. **The colour step.** The strip is drawn by Flutter, under the native bar. A gradient
   that starts at the top of the window has already moved away from the bar colour by
   the time it appears below the bar, so the strip starts a shade off the bar colour.
   This is fixed in Dart: the gradient starts at the bottom of the title band, and the
   strip keeps the solid bar colour above it.

## Step 1: add `duoStripGradient` to the bar style

Edit `packages/adaptive_platform_ui/lib/src/core/theme/adaptive_theme.dart`. Only
`AdaptiveBarStyle` changes:

* `system()` sets `duoStripGradient = null`;
* `solid()` takes an optional `this.duoStripGradient`;
* the field, `==` and `hashCode` include it.

The complete class after the change:

```dart
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
      fillsDuoStrip = false,
      duoStripGradient = null;

  /// A solid [color] bar with [foreground] title, back button and actions.
  /// [shadow] draws a subtle shadow below it; [plainButtons] removes the
  /// glass background behind its buttons on iOS 26+.
  ///
  /// On iPhone Duo the system reserves a strip at one edge of the window for
  /// the vertical bar. [fillsDuoStrip] paints that strip with [color], so the
  /// bar reads as one band from the top of the window down the strip. Pass
  /// false to leave the strip in the page background. [duoStripGradient]
  /// paints the strip below the title band with a gradient instead of
  /// [color]; start a vertical one at [color] so it joins the bar without a
  /// step.
  const AdaptiveBarStyle.solid(
    Color this.color, {
    this.foreground,
    this.shadow = false,
    this.plainButtons = false,
    this.fillsDuoStrip = true,
    this.duoStripGradient,
  });

  final Color? color;
  final Color? foreground;
  final bool shadow;
  final bool plainButtons;

  /// Whether the iPhone Duo vertical bar strip is painted with [color].
  final bool fillsDuoStrip;

  /// Paints the iPhone Duo strip in place of [color] when [fillsDuoStrip].
  final Gradient? duoStripGradient;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveBarStyle &&
      color == other.color &&
      foreground == other.foreground &&
      shadow == other.shadow &&
      plainButtons == other.plainButtons &&
      fillsDuoStrip == other.fillsDuoStrip &&
      duoStripGradient == other.duoStripGradient;

  @override
  int get hashCode => Object.hash(
    color,
    foreground,
    shadow,
    plainButtons,
    fillsDuoStrip,
    duoStripGradient,
  );
}
```

## Step 2: start the gradient where the title band ends

Edit `packages/adaptive_platform_ui/lib/src/navigation/chrome/adaptive_toolbar_host.dart`.

The strip now needs both the bar colour (for the part under the bar) and the gradient,
so it takes the whole bar style instead of a colour.

Replace `_stripColor` with `_stripStyle`:

```dart
  /// The app's bar style where it asks for the Duo strip to be filled.
  AdaptiveBarStyle? _stripStyle(BuildContext context) {
    final bar = AdaptiveTheme.of(context).barStyle;
    return bar.fillsDuoStrip && bar.color != null ? bar : null;
  }
```

Where the host builds the strip, pass `style:` instead of `color:`. In the version from
`duo-bar-strip-fill.md` that is:

```dart
              Positioned.fill(
                child: _BarStrip(pose: pose, style: _stripStyle(context)),
              ),
```

If the strip has since been wrapped, for example in a builder that hides it while a
native sheet is up, keep the wrapper and change only the argument:
`color: sheet != null ? null : _stripColor(context)` becomes
`style: sheet != null ? null : _stripStyle(context)`.

Replace `_BarStrip` with:

```dart
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

`DuoTitleBand.of(context).contentTop` is the y position where the native title band ends
and page content begins. It comes from a native measurement
(`SystemVerticalBar.titleBand`), which arrives after the first frame and changes with
rotation and pane moves. The `ValueListenableBuilder` rebuilds the strip whenever it
changes. Both types are already imported in this file, through
`../../devices/duo/system_vertical_bar.dart` and `../../devices/duo/duo_layout.dart`.

## Step 3: keep the bar's shadow off the strip (iOS)

Two Swift files in
`packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/`
change.

### 3a. `Navigation/NativeBarAppearance.swift`

The navigation controller has to recognise the shadow image the package gives UIKit.
Drop `private` from it:

```swift
    /// A vertical fade from opaque to clear. As a template image, the
    /// appearance's shadowColor sets its strength.
    static let shadowImage: UIImage = {
```

### 3b. `Navigation/NativeNavigationController.swift`

Add two stored properties next to `navigationSafeAreaBackground`:

```swift
    private let stripShadowMask = CAShapeLayer()
    private weak var maskedShadow: UIView?
```

Call the new layout step in `viewDidLayoutSubviews`, before `completedLayout?()`:

```swift
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTransitionBackdrop()
        layoutNavigationSafeAreaBackground()
        layoutStripShadowMask()
        completedLayout?()
    }
```

Add these three methods to the class:

```swift
    /// Keeps the bar's shadow off the iPhone Duo vertical bar strip, so the
    /// bar runs straight into the strip below it. UIKit draws the shadow the
    /// full width of the bar; this masks out only the part over the strip and
    /// leaves the bar, its controls and the status cluster untouched.
    private func layoutStripShadowMask() {
        navigationBar.layoutIfNeeded()
        let shadow = Self.shadowView(in: navigationBar)
        if maskedShadow !== shadow {
            maskedShadow?.layer.mask = nil
            maskedShadow = shadow
        }
        guard let shadow, let strip = verticalBarStrip() else {
            shadow?.layer.mask = nil
            return
        }
        let cut = shadow.convert(strip, from: view).intersection(shadow.bounds)
        guard !cut.isEmpty else {
            shadow.layer.mask = nil
            return
        }
        let path = UIBezierPath(rect: shadow.bounds)
        path.append(UIBezierPath(rect: cut))
        stripShadowMask.fillRule = .evenOdd
        stripShadowMask.frame = shadow.bounds
        stripShadowMask.path = path.cgPath
        shadow.layer.mask = stripShadowMask
    }
    /// The strip the window keeps for the vertical bar, full height, in this
    /// view's coordinates, or nil where bars stay horizontal. Matches the
    /// Dart side: the safe-area inset where the system reserves one, the
    /// bar's own width in the leading Split View pane where it does not.
    private func verticalBarStrip() -> CGRect? {
        let edge = VerticalBarEdgeStreamHandler.edge(of: view)
        guard edge == "left" || edge == "right" else { return nil }
        let insets = view.safeAreaInsets
        let left = edge == "left"
        let inset = left ? insets.left : insets.right
        let width = inset > 0 ? inset : 84
        return CGRect(x: left ? view.bounds.minX : view.bounds.maxX - width,
                      y: view.bounds.minY, width: width, height: view.bounds.height)
    }
    /// The view UIKit draws the bar's shadow image in, found by the image the
    /// package hands it rather than by private class names.
    private static func shadowView(in view: UIView) -> UIImageView? {
        for child in view.subviews {
            if let image = child as? UIImageView,
               image.image === NativeBarAppearance.shadowImage { return image }
            if let found = shadowView(in: child) { return found }
        }
        return nil
    }
```

How it works:

* `verticalBarStrip()` decides the strip the same way `DuoLayout.resolvePose` does in
  Dart: the side comes from `UITraitCollection.verticalBarEdge` (read by the existing
  `VerticalBarEdgeStreamHandler.edge(of:)`), and the width is the safe-area inset on
  that side. Where there is no inset, which is the leading Split View pane, it uses 84,
  the same value as `kDuoVerticalBarWidth`. Keep the two in step.
* `shadowView(in:)` finds the image view UIKit draws the shadow in by comparing its
  image with `NativeBarAppearance.shadowImage`. It never matches private UIKit class
  names. When no such view exists (the bar has no shadow, or UIKit changes how it draws
  one), nothing is masked and nothing breaks.
* The mask is an even-odd path: the shadow view's bounds with the strip rectangle cut
  out. Only that one image view is masked. The bar's background, the title, the
  vertical bar's controls and the status cluster are never touched.
* It runs on every layout of the navigation controller, so it follows rotation, pane
  moves and UIKit replacing the shadow view after an appearance change. Off Duo, or in
  portrait where bars stay horizontal, `verticalBarStrip()` returns nil and any earlier
  mask is removed.

## Step 4: pass the gradient from the parent app

The app owns the colours. Start a vertical gradient at the bar colour; where it goes
from there is the app's choice. Heavier at the top and lighter at the bottom reads
best against a solid bar:

```dart
// lib/app/theme/palette.dart
const red = Color(0xFFB52132),
    redLight = Color(0xFFE2737F),
    // ...
```

```dart
// lib/app/meridian_app.dart
    theme: const AdaptiveThemeData(
      primaryColor: red,
      background: paper,
      barStyle: AdaptiveBarStyle.solid(
        red,
        foreground: Colors.white,
        shadow: true,
        plainButtons: true,
        duoStripGradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [red, redLight],
        ),
      ),
    ),
```

To go back to the solid strip, remove `duoStripGradient`. `fillsDuoStrip: false` still
turns the strip off completely.

## Rules

* Read the colours from `AdaptiveTheme`, never from constants in the package.
* Start the gradient at the bottom of the title band (`DuoTitleBand.of(context)
  .contentTop`), never at the top of the window, and keep the bar colour above it.
* Keep `_BarStrip` always built at the same position in the host's `Stack`, wrapped in
  `IgnorePointer` and below the hosted toolbar, as the first guide requires.
* Mask only the shadow image view. Do not mask, hide or recolour the navigation bar
  itself, its background or any of its other subviews: the Duo status cluster and
  vertical controls are drawn in the same area.
* Find the shadow view by its image, never by a private UIKit class name.
* Do not turn the bar's shadow off to solve this. The shadow over the page content is
  part of the design and must stay.
* Use a plain full-bleed band: no rounded corners, border or shadow on the strip.

## Verify

```sh
flutter analyze lib packages/adaptive_platform_ui/lib
```

Then run the app on the iPhone Duo simulator in landscape and take a screenshot. Crop
the corner where the top bar meets the strip and compare pixel colours down a column
inside the strip, across the bottom edge of the bar:

* the colour just below the bar matches the bar colour (allow 1 or 2 per channel for
  dithering), with no darker band where the bar ends;
* a column inside the page content, left of the strip, still shows the shadow fading
  from darker to the page background below the bar;
* further down, the strip lightens towards the gradient's end colour.

Also check:

1. Push a page and pop it, and switch tabs: the joint stays seamless.
2. Open a sheet: the strip hides while the sheet is up, as before.
3. A normal iPhone simulator: no strip, and the bar's shadow is unchanged across the
   full width.
4. The vertical bar's buttons stay readable on the lighter lower part of the gradient.
