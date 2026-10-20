# Fix native app bars and menu presentation: app first, package second

This guide replaces the previous custom-header implementation guide completely.
It describes the decisions and fixes from this session, using this repository at
commit `0c9dc9f` as the implementation reference. It is a porting guide, not a
request to copy the whole demo app into another project.

## Copy-ready prompt for the implementing AI

Implement the native navigation fixes in this guide in the current project.
First inspect the application and its resolved `adaptive_platform_ui` dependency.
Fix app-level configuration and route ownership first. Modify the package only
for a demonstrated missing API or native integration defect. Preserve unrelated
features, state management, search, and navigation behavior.

Required result:

- Root tabs and pushed pages use real native navigation bars and titles.
- The intended red appearance persists on every tab, including Markets and
  Activity, and on details, both initially and after scrolling.
- Do not hardcode navigation-bar height. UIKit owns its height and layout.
- Standard iPhone navigation buttons are white without shared Liquid Glass
  backgrounds where the product requests that appearance. Duo keeps native
  Liquid Glass side controls with readable contrast.
- Native back-button navigation, completed swipe-back, and cancelled swipe-back
  work and keep the Flutter and native route stacks synchronized.
- The account menu overlays the live application, including overlapping native
  bars, with a neutral panel, top/bottom safe-area bleed, backdrop dimming, and
  a soft shadow. Uncovered native bars remain present behind the backdrop.
- Never draw, capture, or substitute a fake tab bar, navigation bar, title,
  back control, or copy of the underlying interface to conceal a presentation
  problem. Do not hide the real bars simply because the menu opens.

Read the target code before editing. Locate equivalent classes and methods;
never apply patches by line number. The snippets below assume the surrounding
bridge types in the reference project and must be merged into the target's
architecture. If a fix already exists, preserve it rather than duplicating it.

Use Build iOS Apps/XcodeBuildMCP to build and inspect the running app on a normal
iPhone and iPhone Duo. Inspect initial and scrolled states, menu presentation,
back navigation, and gesture cancellation. A successful build, screenshot
capture, or input-command return is not a passed visual check. Inspect the actual
composition and resulting screen. Fix visible defects before reporting success.
Use supported developer CLIs to diagnose unavailable MCP operations; do not
switch to Computer Use. Distinguish actual gestures from debugger-invoked actions.
If Duo input targets its inactive display, document the limitation and complete
all supported checks; never claim the gesture was verified.

Do not run test suites unless requested. Compilation and the simulator checks
explicitly requested by this prompt are authorized. Do not commit, push, publish,
or install on a physical phone unless separately authorized. Do not copy machine
IDs, signing identities, or absolute paths from another computer.

Deliver a short list of app changes versus package changes, the actual devices
and states inspected, and any remaining limitations. Do not claim universal
compatibility from a single simulator or from installation alone.

## 1. Establish which source the other computer actually uses

Inspect the working tree and local instructions before editing. Preserve existing
changes. Identify the app shell, root scaffold, tab selection, detail push helper,
menu opener, and native package source.

In this reference project the application uses a local fork:

```yaml
# pubspec.yaml, under dependencies
adaptive_platform_ui:
  path: packages/adaptive_platform_ui
```

The local path is relative to the application directory. Copying only
`lib/main.dart` does not transfer the Swift or Dart package fixes. Conversely,
editing a different checkout of the package does not update the app unless its
dependency resolves there. Inspect `pubspec.lock` and
`.dart_tool/package_config.json` after dependency resolution. Do not edit the
shared pub cache as a permanent solution.

For another computer, transfer the relevant source through the project's normal
Git workflow or a reviewed patch. Preserve the local package source and dependency
configuration together. Run dependency resolution using that computer's Flutter
SDK, then rebuild the native application. Dart hot reload cannot apply Swift
changes. Do not transfer DerivedData, simulator containers, caches, or signing
artifacts.

Reference history, if these commits exist in the available checkout:

- `b619294`: native red navigation bars and safe-area color continuation.
- `03b3326`: plain standard-phone navigation buttons with Duo adaptation.
- `0c9dc9f`: regular-tab toolbar ownership, native back gestures, and live native
  account drawer presentation.

Use `git show <commit> --stat` and `git show <commit> -- <path>` to inspect those
changes. Do not blindly cherry-pick app-specific commits into an unrelated app.

## 2. Fix the application's app bars and routes first

The app owns its title, colors, actions, current tab, and destinations. It should
express those choices through the native-backed package APIs.

### Root tabs

Use the existing root scaffold's `appBar`. Do not add another visual header:

```dart
appBar: AdaptiveAppBar(
  title: ['Portfolio', 'Markets', 'Watchlist', 'Activity'][state.tab],
  scrollController: navigation,
  navigationBarColor: red,
  hidesNavigationButtonBackground: true,
  tintColor: Colors.white,
  actions: existingActions,
),
```

This is an argument fragment: `state`, `navigation`, `red`, and `existingActions`
refer to the target app's existing state, scroll coordinator, color, and actions.
Preserve that app's actual tab labels and state management. In this demo,
`red = Color(0xFFB52132)` and the page color is `Color(0xFFF6F5F1)`.

Remove the application's hand-built title/header and its fixed-height sizing.
Do not set `customHeaderHeight: 64`, add a fake pinned title, or stack a Flutter
header above a native navigation bar. Do not manually add safe-area padding twice.
Do not remove package compatibility APIs merely because this app stops using them.

Use the existing `AdaptiveApp` integration, which installs the toolbar host in
this package version. If the target uses another shell, inspect its integration
and provide the host once, not once per page or twice around the app.

### Detail navigation

Use one native-backed route mechanism for the title, back control, and content:

```dart
void openPage(BuildContext context, String title, Widget content) =>
    AdaptiveNavigator.push<void>(
      context,
      (_) => AdaptiveScaffold(
        backgroundColor: paper,
        appBar: AdaptiveAppBar(
          title: title,
          navigationBarColor: red,
          hidesNavigationButtonBackground: true,
          tintColor: Colors.white,
        ),
        body: SafeArea(bottom: false, child: content),
      ),
    );
```

Reuse the target's existing imports and colors. Review its body inset behavior;
the `SafeArea` above is the reference app's usage, not a universal instruction to
add another inset to every existing screen.

Do not mix an independently animated `CupertinoPageRoute` with a separate native
bar transition. Keep profile, details, preferences, and statements as full-screen
push destinations. Do not replace them with sheets to avoid fixing navigation.

### Checkpoint before modifying the package

Build the app and inspect all tab titles and colors, initial/scrolled content,
and a pushed detail on both device layouts. If app configuration fixes the
problem, stop changing navigation infrastructure. If a correctly configured bar
still disappears on a tab switch, loses gestures, or leaves a safe-area gap,
trace the package's native ownership and layout next.

## 3. Change the package only where the app's intent is lost

Package-relative paths below use `PACKAGE_ROOT = packages/adaptive_platform_ui`
in this repository. Resolve the equivalent root on the other computer.

| File under PACKAGE_ROOT | Responsibility |
| --- | --- |
| `lib/src/widgets/adaptive_app_bar.dart` | Public appearance properties and `copyWith` |
| `lib/src/widgets/adaptive_scaffold.dart` | Forward app-bar configuration |
| `lib/src/widgets/ios26/ios26_scaffold.dart` | Forward configuration to native toolbar |
| `lib/src/widgets/ios26/ios26_native_toolbar.dart` | Initial channel parameters and subsequent updates |
| `lib/src/widgets/adaptive_navigator.dart` | Coordinate Flutter routes with native push/pop |
| `ios/adaptive_platform_ui/Sources/adaptive_platform_ui/iOS26ToolbarPlatformView.swift` | Native navigation item, appearances, buttons |
| `ios/adaptive_platform_ui/Sources/adaptive_platform_ui/NativeNavigationHost.swift` | Controller ownership, tab handoff, gestures, measured safe-area fill |
| `ios/adaptive_platform_ui/Sources/adaptive_platform_ui/SearchTabView.swift` | Native tab integration; preserve its real controls |
| `ios/adaptive_platform_ui/Sources/adaptive_platform_ui/NativeAccountDrawer.swift` | Current reference menu overlay; see ownership caveat below |

### A. Preserve the appearance contract end to end

Expose `Color? navigationBarColor` and
`bool hidesNavigationButtonBackground` (default false) on `AdaptiveAppBar`,
preserve them in `copyWith`, and forward them through the scaffold/toolbar layers.
Send both initial values and changes over the existing bridge. Encode colors
using `toARGB32()` and decode ARGB correctly in Swift, including alpha.

In `iOS26ToolbarPlatformView.configureNavigationAppearance`, the reference creates
an opaque appearance when a bar color is supplied:

```swift
let style = UINavigationBarAppearance()
style.configureWithOpaqueBackground()
style.backgroundColor = Self.colorFromARGB(value.intValue)
style.shadowColor = .clear
if let tint = configuredTint {
    style.titleTextAttributes = [.foregroundColor: tint]
    style.largeTitleTextAttributes = [.foregroundColor: tint]
}
```

Apply that appearance to all native states, not only the initial one:

```swift
navigationItem.standardAppearance = appearance
navigationItem.scrollEdgeAppearance = appearance
navigationItem.compactAppearance = appearance
navigationItem.compactScrollEdgeAppearance = appearance
```

Here `appearance` is the configured style, or nil when the app has no override.
Set the title through `navigationItem.title`. Retain the existing native title
collapse and scroll-coordination behavior; do not use a `UILabel` or Flutter
`Text` overlay as the navigation title.

### B. Continue color into a measured safe-area gap

The reference `NativeNavigationController.layoutNavigationSafeAreaBackground()`
runs from `viewDidLayoutSubviews`. A noninteractive, accessibility-hidden color
view sits below the real navigation bar and fills only the measured area above
it. It has no title, controls, or independently specified bar height:

```swift
guard !isNavigationBarHidden,
      let color = topViewController?.navigationItem.standardAppearance?.backgroundColor,
      navigationBar.frame.minY > view.bounds.minY else {
    navigationSafeAreaBackground.removeFromSuperview()
    return
}
navigationSafeAreaBackground.backgroundColor = color
navigationSafeAreaBackground.frame = CGRect(
    x: view.bounds.minX, y: view.bounds.minY,
    width: view.bounds.width,
    height: navigationBar.frame.minY - view.bounds.minY)
view.insertSubview(navigationSafeAreaBackground, belowSubview: navigationBar)
```

This is a background fill, not a replacement bar. Use the measured geometry in
the correct coordinate space. Recompute during layout changes; do not cache one
phone's dimensions or add an arbitrary top strip.

### C. Keep Duo's native glass and readable side controls

The reference toolbar already receives `verticalNavigation` from the package's
adaptive layout. Reuse that mechanism; do not identify devices by name, screen
width alone, or a hardcoded simulator ID.

```swift
if #available(iOS 26.0, *) {
    for item in (navigationItem.leftBarButtonItems ?? []) +
                (navigationItem.rightBarButtonItems ?? []) {
        item.hidesSharedBackground = hidesButtonBackground && !verticalNavigation
    }
}
if hidesButtonBackground && verticalNavigation {
    for item in navigationItem.leftBarButtonItems ?? [] {
        item.tintColor = .label
    }
}
```

The ordinary iPhone buttons sit on red and use the app's white tint. Duo's leading
controls sit in a side rail over page-colored content, so removing their glass
and leaving white icons made them difficult to see. Preserve native glass there.

The reference uses a real `UIBarButtonItem` with `chevron.backward` on ordinary
iPhone when suppressing the automatic back item's glass is required. It retains
its Back accessibility label and existing native back action. Duo retains the
system-generated back control. A native bar item is acceptable; a custom Flutter
back button floating over the page is not. Recheck swipe-back whenever changing
the native leading item.

### D. Preserve a shared root toolbar during regular tab switches

In this app one root scaffold reuses its toolbar anchor while the selected native
tab controller changes. Previously, looking up only the new controller's cached
anchor could yield nil, making the red bar disappear on Markets or Activity.

In `NativeNavigationHost.selectContent`, preserve the previous root anchor only
in the regular-tab fallback branch:

```swift
page = contentPages[ObjectIdentifier(next)]?.page
    ?? (previousExternal == nil && previousPage?.nativeNeedsBack == false
        ? previousPage : nil)
if let page { remember(page) }
```

Preserve the surrounding ownership guards: defer tab handoff while a native push
or pop is in progress or a detail owns the controller; keep Search's external
navigation ownership separate; let a genuine new tab-specific anchor replace the
fallback. Do not reuse a detail anchor or impose one title on all tabs. Dart must
still publish the selected tab's actual title.

### E. Restore native interactive back navigation

In the reference `NativeNavigationController`, gesture enablement follows the
managed route and pop permission state:

```swift
private func updatePopGestures() {
    let enabled = usesManagedRoutes && routePopEnabled
    interactivePopGestureRecognizer?.isEnabled = enabled
    if enabled { interactivePopGestureRecognizer?.delegate = self }
    if #available(iOS 26.0, *) {
        interactiveContentPopGestureRecognizer?.isEnabled = enabled
        if enabled { interactiveContentPopGestureRecognizer?.delegate = self }
    }
}

func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard usesManagedRoutes, routePopEnabled, viewControllers.count > 1,
          !transitioningBetweenRoutes, transitionCoordinator == nil else {
        return false
    }
    return true
}
```

The controller conforms to `UIGestureRecognizerDelegate`. Preserve any additional
valid target-app restrictions when merging; do not replace an unrelated delegate
blindly. A velocity gate at gesture begin rejected the native gesture in this
session and was removed. Do not unconditionally enable pop at the root or during
another transition.

Keep the package's route lifecycle intact: prepare native push, render the Flutter
destination, then let UIKit animate the destination controller. A cancelled swipe
must retain the Flutter route; a completed pop must synchronize it exactly once.
Do not replace native swipe-back with a Flutter horizontal-drag route pop.

## 4. Present the menu over live bars, never copies

### Rejected approaches: do not port these

- `tabBarHidden: menuOpen` removes the real tab bar instead of covering it.
- Hiding the navigation bar while the menu opens removes uncovered chrome.
- Clipping/masking/reparenting the tab bar to make room for a Flutter drawer did
  not reliably contain the native glass in the observed layout.
- A rendered image/snapshot of the tab bar is a fake bar even if it looks close.
  The user explicitly rejected it. Do not use one during animation either.
- A second fake header or fixed-height strip is not a safe-area fix.

### Reference implementation

The app's `_openAccounts` invokes `presentDrawer` on the existing
`adaptive_platform_ui/navigation` method channel. It sends the menu title,
subtitle, selected account, width, and item IDs/titles/SF Symbols. The native host
adds one `NativeAccountDrawer` above the live root controller hierarchy in its
own window. It does not hide, snapshot, reparent, or recreate the underlying bars.

The returned string is an application action ID such as `account:1`,
`preferences`, or `statements`. The app updates its BLoC or pushes a destination
only after menu dismissal. The native presenter does not implement portfolio
business logic.

The implementation uses:

- Real `UIButton` menu actions in a scrolling `UIStackView`.
- A full-window dimming `UIControl` behind the panel; backdrop tap dismisses.
- A neutral panel background extending to the window edges; its content respects
  the window safe-area insets.
- Panel width capped at `min(320, availableWidth * 0.82)` in this app. This is a
  menu-width choice, not a navigation-height constant.
- A soft shadow: opacity 0.3, radius 22, offset `(8, 0)` in the reference. It is a
  shadow, not an accent stripe or a border painted on one side.
- Animated presentation/dismissal and a leftward dismissal pan. The recognizer
  begins only for predominantly horizontal leftward movement so vertical menu
  scrolling remains possible.
- Dynamic fonts, selected-row traits, modal accessibility, and Escape dismissal.
- A light interface style for the reference's light panel. Its status-bar style
  override is restored on dismissal; check actual contrast on each layout.

On iOS, avoid also opening the Flutter `Drawer` underneath this native overlay.
The reference retains that drawer for non-iOS fallback and disables its automatic
iOS edge-open gesture. It supports menu-button opening and native swipe dismissal;
**edge-swipe opening was not restored by this change**. If the other app requires
edge-swipe opening, implement and verify that explicitly against native back
navigation rather than silently enabling the old Flutter drawer again.

### Ownership caveat for reuse

The current `NativeAccountDrawer.swift` is located in the package, but its account
menu naming, styling, and divider-before-item-4 convention are app-specific. This
is a working reference, not an ideal generic package API.

For a reusable integration, keep account labels, actions, selection, styling,
section/group definitions, and business logic in the app. Put only generic native
overlay presentation/dismissal and safe-area integration in the package, or keep
the specialized native menu in the app's iOS target. If moving it, update method
channel registration so there is one owner; do not install competing handlers on
the existing navigation channel. Generalize deliberately instead of copying
Meridian's account assumptions into every consumer.

## 5. Verify in this order on the other computer

Discover available devices and runtimes locally. In XcodeBuildMCP inspect session
defaults, set the correct workspace/scheme/simulator, and build/run. Repeat on the
normal iPhone and Duo. Inspect folded and expanded Duo when those layouts are
available; record exactly which postures were checked.

| Scenario | Required observation |
| --- | --- |
| Each root tab, initial | Correct native title and red appearance; no duplicate title or top gap |
| Each root tab, scrolled | Title stays visible using native behavior; color persists; content is not clipped |
| Switch tabs repeatedly | Markets/Activity retain the bar and correct title; Search ownership stays correct |
| Push a detail/profile/menu destination | Native title, back item, and content transition together |
| Back button | Returns once to the correct preceding page and preserves expected state |
| Completed native swipe-back | Route and native stack both return correctly; no stranded title or controls |
| Cancelled native swipe-back | Detail remains usable; title, buttons, and gestures recover |
| Push again after cancellation | No disabled gesture or stuck transition flag |
| Menu at top and after scrolling | Panel bleeds into safe areas; live uncovered bars remain behind the scrim |
| Menu dismissal and selection | Tap outside, swipe dismiss, account selection, and destination push behave correctly |
| Menu content scrolling | Last item is reachable; vertical scrolling does not accidentally dismiss it |
| Duo controls | Native side placement and glass remain; symbols are readable and touch targets are unobstructed |
| Layout/posture change | Safe-area fill and overlay resize; no copied old-size chrome or clipped content |

Use screenshots and, for interactive transitions, recordings or observed frames.
Inspect the result itself: spacing, overlap, contrast, clipping, scroll limits,
and title visibility. Do not treat an accessibility snapshot alone as visual proof.

In this session, regular-iPhone menu selection, Preferences navigation, native
swipe-back, and menu swipe dismissal were exercised. Expanded Duo menu composition
was visually inspected, but automation touch routing targeted the inactive
folded display; the menu was opened through its existing native action using the
debugger. That established presentation, not a successful finger gesture on Duo.
Folded Duo, gesture cancellation, rotation, accessibility, and every target-app
screen still require their own acceptance checks after porting. Do not inherit
this repository's verification claims as proof for a different app or computer.

When diagnosing unavailable controls, use supported developer tools, report the
specific limitation, and continue independent checks. Do not invent undocumented
fold/unfold commands or substitute a normal phone for requested Duo coverage.

## 6. Finish and hand off

Review the final diff for accidental fixed navigation heights, duplicate headers,
bar snapshots, hidden-bars-on-menu flags, and unrelated changes. Make clear which
fixes live in the app and which live in the local package fork. Rebuild after
native changes and repeat checks affected by the last edit.

If physical installation is authorized, build/sign using the receiving computer's
available team and device, then install the final verified build. Installation is
not visual verification of the physical device. Do not capture the physical
screen or logs without authorization unless required to diagnose a failed deploy.

The intended order is: app configuration and routes → narrow package corrections
→ live native overlay presentation → normal-iPhone and Duo verification →
authorized device deployment. Do not start by rewriting the entire package.
