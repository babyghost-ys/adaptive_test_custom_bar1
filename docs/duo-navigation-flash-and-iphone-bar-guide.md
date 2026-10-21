# Fix the Duo navigation-bar flash and set the iPhone bar to menu + search

This guide explains how to remove the flash that iPhone Duo shows in its
top navigation controls during a native push or pop. It also covers how to set
the standard iPhone bar to show the side menu on the left and search on the
right. It builds on
[adaptive-platform-ui-native-navigation-agent-guide.md](adaptive-platform-ui-native-navigation-agent-guide.md):
apply that guide first, then this one.

All package paths below are relative to
`PACKAGE_ROOT = packages/adaptive_platform_ui`. Swift sources live in
`PACKAGE_ROOT/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/`.

## Copy-ready prompt for the implementing AI

Remove the flash in the Duo side-rail controls during native push and pop,
and give the standard iPhone navigation bar a side-menu button on the left and
a search button on the right. Use the `adaptive_platform_ui` package as the
owner of all native chrome. First, diagnose the flash from recorded frames, not
from guesses. Fix the four root causes described in this guide where they
exist in the target. Do not hide, snapshot, or redraw the bars. Do not hardcode
bar heights. Keep native swipe-back working. Verify with recordings on a
standard iPhone simulator and on an iPhone Duo simulator. Do not commit.

## 1. Diagnose from frames, not from a single screenshot

The flash lasts 3 to 60 frames, so a screenshot rarely catches it. Record the
transition and inspect individual frames.

### Driving navigation on Duo

Simulator input automation targets Duo's inactive display. Taps from
XcodeBuildMCP and the simulator control tool never reach the app. To exercise
push and pop, add temporary, clearly marked instrumentation to the app's root
state. Remove it before you finish.

```dart
// TEMP-NAVDEMO: remove before finishing
@override
void initState() {
  super.initState();
  Future(() async {
    await Future.delayed(const Duration(seconds: 3));
    for (var i = 0; i < 20 && mounted; i++) {
      openPage(context, 'Profile', const ProfileContent());
      await Future.delayed(const Duration(milliseconds: 2500));
      if (!mounted) return;
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 2500));
    }
  });
}
```

Environment variables passed through `launch_app_sim` did not reach
`Platform.environment` in this setup, so make the loop unconditional while
diagnosing. `debugPrint` output does not appear in the XcodeBuildMCP logs. If
you need to confirm the loop runs, append to a file under
`Directory.systemTemp` and read it from the simulator's app container.

On a standard iPhone simulator, XcodeBuildMCP `tap` works for buttons, but its
`type_text` did not reach a focused Flutter text field. Use the simulator
control tool's `tap` and `text` actions for typing.

### Recording

XcodeBuildMCP's `record_sim_video` failed in this environment because AXe was
missing. Use the simulator's own recorder for diagnostic capture only; builds
and runs still go through XcodeBuildMCP:

```bash
xcrun simctl io <SIM_UDID> recordVideo --codec=h264 --force capture.mov
```

Stop it with `SIGINT` after a couple of cycles. The video has a variable frame
rate: it only stores frames that changed. Extract the real frames, then find
transitions as gaps in the timestamps:

```bash
ffmpeg -i capture.mov -fps_mode passthrough -vf "crop=iw*0.3:ih:iw*0.7:0,scale=110:-1" f/%03d.png
```

```bash
ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 capture.mov
```

Tile 20 to 40 frames from each transition (`tile=18x1`) and inspect the rail
and the status cluster. ffmpeg already applies the display rotation, so do not
add `transpose`. Crop the trailing edge for Duo's rail and the top 14% for the
iPhone bar.

## 2. The four root causes on Duo

The recordings showed four separate defects. Each one needs its own fix.

| Symptom in frames | Cause |
| --- | --- |
| On push, the menu button dims and its glass stretches upward into the status bubble for about 4 frames | (A) Root page treated as covered by a popup |
| On push, a tall glass capsule spans from the status bubble down past the menu button | (B) `hidesBottomBarWhenPushed` morphs Duo's vertical tab bar into the leading controls |
| On pop, the status icons and time turn dark for about 1 second, then return to white | (C) The revealed page has no Flutter child, so it uses the default status-bar style |
| The rail's glass lightens on both push and pop | (D) The bar background cross-fades between items that carry identical per-item appearances |

To confirm (B), temporarily set `hidesBottomBarWhenPushed = false`. The capsule
disappears, and that is the proof.

### A. Do not treat a native push as a popup (Dart)

`AdaptiveNavigator` routes have zero-duration Flutter transitions. For the
first frames of a push, the root route is not current and its
`secondaryAnimation` is still `dismissed`. That matches the scaffold's
"covered by popup" test, so the root bar is dimmed with an animated
`tintAdjustmentMode` change.

In `lib/src/widgets/adaptive_navigator.dart`, record each stack against its
root route and expose a query:

```dart
bool hasNativePageAbove(Route<dynamic>? route) {
  if (route == null) return false;
  final stack = route is _NativePageRoute<dynamic>
      ? route.stack
      : _NativeNavigation.instance._rootStacks[route];
  if (stack == null || stack.routes.isEmpty) return false;
  return !identical(stack.routes.last, route);
}
```

```dart
// in _NativeNavigation
final _rootStacks = Expando<_NativeStack>();

// in push(), after the stack is obtained
if (parentRoute != null && stack.rootRoute == parentRoute) {
  _rootStacks[parentRoute] = stack;
}
```

In `lib/src/widgets/ios26/ios26_scaffold.dart`, import `../adaptive_navigator.dart`
and exclude native pages from the covered state:

```dart
final coveredByPopup =
    !isCurrentRoute &&
    !isPopping &&
    !hasNativePageAbove(route) &&
    (route?.isActive ?? false) &&
    route?.secondaryAnimation?.status == AnimationStatus.dismissed;
```

A real sheet over a native page still counts as covered, because that page is
still the last route in its native stack.

### B. Hide Duo's vertical tab bar without UIKit's morph (Swift)

In `NativeNavigationHost.swift`, `showNativeRoute`, set
`hidesBottomBarWhenPushed` only for the regular layout:

```swift
next.hidesBottomBarWhenPushed = !verticalTabs
```

```swift
private var verticalTabs: Bool {
    tabs != nil && managedRoutes.first?.page?.nativeVerticalNavigation == true
}
```

Have `NativeNavigationController` report `willShow` through a callback,
`willShowRoute?(viewController)`, called from its delegate's
`navigationController(_:willShow:animated:)` while `usesManagedRoutes` is
true. Install it in `prepareNativePush` next to `completedNavigation`. Then
hide or show the tab bar with the tab bar controller's own API:

```swift
private func updateTabBar(for controller: UIViewController, in navigation: UINavigationController) {
    guard #available(iOS 18.0, *), let tabs else { return }
    guard verticalTabs else {
        if tabs.isTabBarHidden, managedRoutes.count <= 1 { tabs.setTabBarHidden(false, animated: false) }
        return
    }
    let hidden = controller !== managedRoutes.first?.content
    guard tabs.isTabBarHidden != hidden else { return }
    tabs.setTabBarHidden(hidden, animated: true)
    navigation.transitionCoordinator?.animate(alongsideTransition: nil) { [weak tabs] context in
        guard context.isCancelled else { return }
        tabs?.setTabBarHidden(!hidden, animated: true)
    }
}
```

Setting `tabBar.alpha` does not work: Duo draws its vertical rail outside the
tab bar view, and the rail stayed visible. The cancellation handler restores
the tab bar after a cancelled swipe-back.

### C. Keep the status-bar style while Flutter is detached (Swift)

The single Flutter view moves between `NativeNavigationContent` controllers.
During a pop, the revealed controller has `flutter == nil` until the transition
completes. At that point `childForStatusBarStyle` returns nil and UIKit falls
back to the default (dark) style. Store Flutter's style on detach:

```swift
private var retainedStatusBarStyle: UIStatusBarStyle?
override var childForStatusBarStyle: UIViewController? {
    drawerStatusBarStyle == nil && flutter != nil ? flutter : nil
}
override var preferredStatusBarStyle: UIStatusBarStyle {
    drawerStatusBarStyle ?? retainedStatusBarStyle ?? super.preferredStatusBarStyle
}

func detachFlutter() {
    guard let controller = flutter, controller.parent === self else { flutter = nil; return }
    retainedStatusBarStyle = controller.preferredStatusBarStyle
    // existing detach code
}
```

### D. Put the shared bar appearance on the bar, not on each item (Swift)

When every page's `UINavigationItem` carries its own copy of the same red
appearance, UIKit still cross-fades the bar background between them. In
`configure(_:)`, apply the source page's appearance to the navigation bar and
clear the per-item appearances:

```swift
applySharedAppearance(source, to: navigation)
assign(destination, \.standardAppearance, nil)
assign(destination, \.scrollEdgeAppearance, nil)
assign(destination, \.compactAppearance, nil)
assign(destination, \.compactScrollEdgeAppearance, nil)
```

`applySharedAppearance` writes to the bar only when the visible appearance
changes. Its key is the background colour plus the title colour, so
reassigning an identical appearance does nothing. It also caches the bar's
original appearances, so a page without a colour restores the default bar.
Pass the appearance through `AdaptiveNativeFonts.styled(_:)`; make that
function internal instead of private, so the configured font family is kept.
Set `NativeNavigationController.sharedBarColor` and use it as a fallback in
`layoutNavigationSafeAreaBackground()`; otherwise the safe-area colour fill
loses its colour.

`configure(_:)` does not run during a transition. If two pages in one stack use
different bar colours, the bar switches colour when the transition completes
instead of mid-animation.

## 3. Make leading controls morph instead of dissolve (Swift)

These changes are in `iOS26ToolbarPlatformView.swift`.

1. **Use a regular Back item on Duo as well.** Create the `chevron.backward`
   item whenever `hidesButtonBackground` is true, not only when
   `!verticalNavigation`. The system-generated Back item only appears after
   the push, so the outgoing menu glass dissolved first. On Duo the item keeps
   its glass, because `hidesSharedBackground` stays false in the vertical
   layout.
2. **Match leading items across pages on Duo only.** Give each page's first
   leading item the same iOS 26 `UIBarButtonItem.identifier`, so UIKit morphs
   one glass item from menu to Back:

   ```swift
   if #available(iOS 26.0, *), verticalNavigation {
       (leadingItems + leftGroup).first?.identifier = Self.leadingIdentifier
   }
   ```

   Do not set it on the standard iPhone layout. Without glass, matching only
   swaps the symbol to a chevron before the titles move, which looks like a
   snap.
3. **Do not recreate bar items on resync.** Dart sends `updateActions` and
   `setButtonBackground` again with `force: true` whenever a toolbar anchor is
   created, which happens during every push. Store the last `actions` array
   (`configuredActions: NSArray?`, set in `configureItems`) and skip
   `updateActions` when it is equal. In `setButtonBackground`, recreate the
   Back item only when the value actually changes. A new item instance
   restarts its glass, and that restart is visible.
4. **Readable rail controls.** On Duo, all bar actions can move into the side
   rail over page-coloured content. Apply `.label` tint to both left and right
   items when `hidesButtonBackground && verticalNavigation`; a white search
   glyph is nearly invisible on the light rail.

## 4. App changes: menu on the left, search on the right

In `lib/main.dart`, keep the menu action first with
`spacerAfter: ToolbarSpacerType.flexible`, so it stays on the left. Replace the
right-hand action with search:

```dart
AdaptiveAppBarAction(
  iosSymbol: 'magnifyingglass',
  icon: Icons.search,
  label: 'Search',
  tintColor: Colors.white,
  onPressed: () => openPage(context, 'Search', const SearchContent()),
),
```

The Profile action that was there before moves into the side menu: add
`{'id': 'profile', 'title': 'Profile', 'symbol': 'person.crop.circle'}` to the
`presentDrawer` items, add a matching `selection == 'profile'` branch, and add
a `menuLink` to the non-iOS Flutter drawer.

`SearchContent` is a native-pushed page with a `CupertinoSearchTextField` that
filters assets by symbol or name. Provide `prefixIcon: Icon(Icons.search)` and
`suffixIcon: Icon(Icons.cancel)`: the project does not bundle `cupertino_icons`,
so the default Cupertino glyphs render as "?" boxes.

On Duo the same actions appear in the rail: menu, then search.

## 5. Verification checklist

Build and run with XcodeBuildMCP on one standard iPhone simulator and on the
iPhone Duo simulator. For each, record at least two push and pop cycles and
inspect the tiled frames.

| Check | Expected |
| --- | --- |
| Duo push | Menu glass morphs into Back in place; no tall capsule; tab rail fades out |
| Duo pop | Back morphs into menu; time and status icons stay white; tab rail returns |
| Duo root rail | Menu and search glyphs are dark and readable on the rail |
| iPhone root bar | Menu on the left, title centred, search on the right, all white on red |
| iPhone push and pop | Menu and chevron cross-fade with the titles; no snap and no repeated fades |
| Search | Typing "nv" leaves only NVDA |
| Status bar during pop | No dark interval on either device |

Then remove the instrumentation:

```bash
grep -rn "TEMP-NAVDEMO\|EXPERIMENT" lib packages/adaptive_platform_ui
```

Run `flutter analyze` on the changed Dart files.

### Known limits from this implementation

- Native swipe-back on Duo, including a cancelled swipe, could not be
  driven by automation, so the reverse path in `updateTabBar` was not observed.
- Only the unfolded Duo posture was recorded.
- On a standard iPhone simulator, XcodeBuildMCP `type_text` did not reach the
  Flutter field; real HID input from the simulator control tool did.
