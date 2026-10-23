# iOS 26: drawer over the tab bar, and slow tab switching

Instructions for an AI agent. Two problems in `adaptive_platform_ui` show on iOS 26 only.
iOS 27 does not have either. Both fixes are in the package's Swift code. Nothing changes
in Dart or in the app.

1. **The tab bar's glass covers the drawer.** With the side menu open, the floating tab
   bar's Liquid Glass capsule is drawn across the menu panel. The tab icons under the
   panel are cut away, but the capsule stays.
2. **Switching tabs is slow.** Tapping a tab that has not been opened yet changes the
   title and the selected tab at once, but the page underneath keeps showing the old tab
   for about 0.6 seconds before the new one appears. Going back to a tab already opened
   is quick.

## Result

* iOS 26: while the drawer is open the tab bar is hidden. It comes back as it was when
  the drawer closes. The navigation bar is still cut open where the panel is, as before.
* iOS 26: a newly selected tab shows its page within a frame or two, the same as iOS 27.
* iOS 27 and later: the tab bar stays visible and is cut open at the panel's edge, as
  before. Tab switching was already instant and is unchanged.
* iPhone Duo: unchanged. Its bar is vertical, and the cut-out keeps it intact.
* Earlier iOS versions: unchanged. The tab bar there is drawn by Flutter, not UIKit.

## 1. Hide the tab bar on iOS 26 while the drawer is open

### Why it happens

On iOS 26 and later the tab bar is a native UIKit view, drawn above everything Flutter
draws, including the drawer panel. `NativeDrawerCover` makes the panel look as if it is
above the bars: it masks each bar view with a shape that has a hole where the panel is.

On iOS 27 that works for the tab bar. On iOS 26 the tab bar's glass ignores it. The
capsule stays whole even when:

* the tab bar's container, the tab bar, its platter view and every glass layer inside it
  (`CABackdropLayer`, `CASDFLayer`, `CAPortalLayer`) are masked;
* the tab bar's container is clipped with `masksToBounds` to the area beside the panel
  (this removes the tab icons under the panel, but not the capsule);
* the `_GlassGroupView` layer, the scroll edge effect views and the
  `FloatingBarContainerView` are set to opacity 0.

The only thing the capsule honours is hiding the tab bar's container view. So on iOS 26
the tab bar is hidden while the panel is out.

### Change: `ios/.../Navigation/NativeDrawerCover.swift`

Add a property for the tab bars it hides, next to `targets`:

```swift
    private var targets: [(view: UIView, mask: CALayer?, interaction: Bool, hidden: Bool)] = []
    /// Tab bars hidden while the panel is out, and whether each was hidden
    /// before.
    private var hiddenBars: [(view: UIView, wasHidden: Bool)] = []
```

At the end of `mask(_:)`, hide each cut view that holds a `UITabBar`, on iOS 26 only:

```swift
    /// Starts cutting [views] open; [update] moves the opening.
    func mask(_ views: [UIView]) {
        guard targets.isEmpty else { return }
        targets = views.map { ($0, $0.layer.mask, $0.isUserInteractionEnabled, $0.accessibilityElementsHidden) }
        for view in views {
            // Touches in the opening must reach the Flutter panel below.
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }
        // Before iOS 27 the tab bar's Liquid Glass is drawn whole whatever
        // masks, clips or fades its views: the mask cuts its items open but
        // the glass capsule stays over the panel. Hidden is the one state it
        // honours, so the tab bar goes while the panel is out.
        if #unavailable(iOS 27) {
            func hasTabBar(_ view: UIView) -> Bool {
                view is UITabBar || view.subviews.contains(where: hasTabBar)
            }
            hiddenBars = views.filter(hasTabBar).map { ($0, $0.isHidden) }
            for bar in hiddenBars { bar.view.isHidden = true }
        }
    }
```

`#unavailable(iOS 27)` also covers versions before iOS 26. On those, the cover is never
created for a tab bar, because the tab bar is drawn by Flutter, so nothing happens there.

In `restore()`, put each one back as it was:

```swift
    /// Puts every cut view back as it was.
    func restore() {
        for target in targets {
            target.view.layer.mask = target.mask
            target.view.isUserInteractionEnabled = target.interaction
            target.view.accessibilityElementsHidden = target.hidden
        }
        for bar in hiddenBars { bar.view.isHidden = bar.wasHidden }
        hiddenBars = []
        targets = []
        panel = nil
    }
```

`mask(_:)` runs when the drawer starts to open. `restore()` runs once it has fully closed
(`clearDrawerCover` from Dart). So the tab bar disappears at the first frame of the
drawer opening and comes back once the drawer has gone.

The views passed to `mask(_:)` are found in `NativeNavigationHost.swift` under
`case "setDrawerCover":`. That code walks up from Flutter's view and takes every sibling
at each level, which is how `_UITabBarContainerWrapperView` (the tab bar's container)
gets into the list. Nothing needs to change there.

## 2. Show a newly selected tab straight away on iOS 26

### Why it happens

All tabs share one Flutter view. On a tab switch `NativeNavigationHost.selectContent`
moves it into the new tab's `NativeNavigationContent`. The page is then held back until
two things have happened:

* `NativeNavigationHost.layout()` has measured the new page's top inset and sent it to
  Dart (`onNavigationMetrics`). Until then the Dart scaffold keeps the page invisible:
  `scaffold_native.dart` wraps the body in a `Visibility` keyed on `contentTopInset`.
* Flutter has been told it has appeared in its new place
  (`completeFlutterAppearance()`). Until then it keeps showing its last frame, which is
  the tab being left.

Both of these waited for the new page's `viewDidAppear`: `layout()` returned early on
`guard content.hasCompletedAppearance`, and `restoreAppearance()` is called from
`viewDidAppear`.

On iOS 26 a tab tap runs inside a UIKit transition, so the selected tab's glass can
animate across. The new page is in the window and in its final place from the start of
that transition. But UIKit only calls its `viewDidAppear` once the transition ends, about
0.6 seconds later. Timings from a log on an iOS 26.2 simulator:

| Event | Time after the tap |
| --- | --- |
| `didSelectTab` (transition coordinator present) | 0 ms |
| new page `viewWillAppear` (animated) | 14 ms |
| new page `viewDidAppear` | 680 ms |
| inset reported to Dart (before the fix) | 685 ms |

iOS 27 does not run that transition, so `viewDidAppear` comes almost at once.

Returning `nil` from `tabBarController(_:animationControllerForTransitionFrom:to:)` does
not help. On iOS 26 the tab bar controller does not ask its delegate for this transition.

### Change 1: `ios/.../Navigation/NativeNavigationHost+Layout.swift`

In `layout()`, replace

```swift
        guard content.hasCompletedAppearance else { return }
```

with

```swift
        // A tab switch shows the new page in place straight away, but on
        // iOS 26 UIKit only completes its appearance when the switch's
        // transition ends, about 0.6s later. Measure it as soon as it is in
        // the window instead, so the page is not held back until then.
        let switchingTabs = tabs?.transitionCoordinator != nil && content.view.window != nil
        guard content.hasCompletedAppearance || switchingTabs else { return }
        // Until Flutter has appeared here it keeps showing its last frame,
        // which is the tab being left.
        if switchingTabs { content.completeFlutterAppearance(early: true) }
```

`tabs` is the host's `UITabBarController`. Its `transitionCoordinator` is only non-nil
while a tab switch is running, so pushes, pops, search and sheets keep their existing
paths. Those are handled earlier in `layout()` by `deferForNavigationTransition`.

### Change 2: `ios/.../Navigation/NativeNavigationContent.swift`

Let `completeFlutterAppearance` run before the page's own appearance has completed, when
asked to:

```swift
    /// With [early], Flutter appears before this page's own appearance has
    /// completed: during a tab switch, which shows the page in place at once
    /// but only completes its appearance when the switch's transition ends.
    func completeFlutterAppearance(early: Bool = false) {
        guard hasCompletedAppearance || early, !flutterAppeared, !forwardingDisappearance,
              let flutter, flutter.view.window != nil else { return }
        flutter.beginAppearanceTransition(true, animated: false)
        flutter.endAppearanceTransition()
        flutterAppeared = true
    }
```

It is safe to call it again later. When `viewDidAppear` arrives and
`restoreAppearance()` calls `completeFlutterAppearance()`, `flutterAppeared` is already
true, so nothing happens. Tab content does not set `coordinatesManagedTransition`, so
`viewWillAppear` does not start a second appearance transition.

`restoreAppearance()` in `NativeNavigationHost.swift` stays as it is. It still finishes
the job for any switch where the early path did not run.

## Verify

Use one iOS 26 simulator and one iOS 27 simulator. Every simulator in the default Xcode
list may be iOS 27, so check the runtime column in `list_sims` and pick an iOS 26.x
device for the first two checks.

1. **Drawer, iOS 26:** open the drawer. The tab bar is gone, the panel shows from top to
   bottom with nothing over it, and the rest of the screen is dimmed. Close it. The tab
   bar returns with the same tab selected.
2. **Tab switch, iOS 26:** launch fresh and tap each tab once. Record the screen at
   30 fps. The new page replaces the old one within one to three frames of the selected
   tab changing. Before the fix the old page stayed for about 18 frames.
3. **iOS 27:** open the drawer. The tab bar stays visible and is cut open exactly at the
   panel's edge. Tab switching is still instant.
4. **iPhone Duo:** open the drawer. The vertical bar stays intact, and the top band is
   cut open where the panel is. Tab switching is instant.
5. `flutter analyze` and `flutter test` in the package still pass. Neither covers this
   native code, so the checks above are what prove it.
