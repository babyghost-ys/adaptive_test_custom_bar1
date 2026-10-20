# AI agent implementation brief: native navigation with a custom solid header

Update the `adaptive_platform_ui` package by implementing the changes below. Keep UIKit responsible for native tabs, detail navigation, Back buttons and interactive gestures. Support an explicitly requested custom Flutter header on the tab root without title overlap, white corner gaps or scroll-edge shading during swipe-back.

This is an implementation instruction for an AI coding agent, based on the working code in this project. Read the target package before applying it. If a change already exists, preserve it instead of adding a second implementation. Do not apply snippets by line number: locate the named class or method.

## 1. Scope and expected result

Implement all of these behaviours together:

1. Root tabs may use a solid custom Flutter header. In Meridian its height is 64 logical points, excluding the top safe area, and its color is `0xFFB52132`.
2. Detail pages use the package's native navigator and native navigation items. The content and navigation controls must transition together.
3. During a completed swipe, the outgoing title and Back button must not remain over the root header.
4. During cancellation, the detail title, native Back button, content and interaction must return intact.
5. The exposed surface behind UIKit's rounded transition cards must match the root's header and page colors. In particular, do not leave a white wedge at the top-right corner of the returning red header.
6. The custom header must stay solid. Disable the native top scroll-edge effect for this header rather than adding a second pale layer or dark stripe.
7. Preserve native Liquid Glass tabs, Duo side controls, the overlay side drawer and ordinary iPhone safe areas.

Do not recreate native tabs or Back buttons as Flutter button rows. Do not remove UIKit's private transition views, change private corner masks, replace the native gesture with a Flutter imitation, or hide a visible defect behind an arbitrary delay.

The custom header is an explicit product choice in this project. Do not use this brief as permission to replace native navigation titles in unrelated apps.

## 2. Locate the package and distinguish application changes

This project's `pubspec.yaml` points to a local package copy:

```yaml
adaptive_platform_ui:
  path: packages/adaptive_platform_ui
```

Use `packages/adaptive_platform_ui` as `PACKAGE_ROOT` in the file list below. Paths beginning with `lib/main.dart` belong to the application, not the package.

| File | Required responsibility |
| --- | --- |
| `lib/main.dart` | Declare the custom root header and push details with `AdaptiveNavigator` |
| `PACKAGE_ROOT/lib/src/widgets/adaptive_scaffold.dart` | Expose and forward custom-header metadata and page background |
| `PACKAGE_ROOT/lib/src/widgets/ios26/ios26_search_tab_scaffold.dart` | Publish root appearance through the native channel |
| `PACKAGE_ROOT/lib/src/widgets/adaptive_navigator.dart` | Coordinate Flutter routes with the native controller stack |
| `PACKAGE_ROOT/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/SearchTabView.swift` | Decode appearance metadata, retain it on root controllers, measure Duo safe areas |
| `PACKAGE_ROOT/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/NativeNavigationHost.swift` | Own native transition state, backing colors, visibility and cancellation |

The sibling `adaptive2` project is not automatically updated by changes to this copy. If asked to upstream the fix, port the package changes into that project's actual package source and validate its examples separately. Do not copy this investment application's BLoC, assets or screens into a reusable package.

## 3. Fix the application's route entry point first

Audit every detail push. Do not combine a `CupertinoPageRoute` content animation with a native title and Back button supplied by `AdaptiveScaffold`. That creates two independently controlled transitions.

Use this complete helper from the application. It depends on the existing `paper` constant and the package import; it is a replacement for the existing `openPage`, not a standalone application.


```dart
import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

const paper = Color(0xFFF6F5F1);

void openPage(BuildContext context, String title, Widget content) =>
    AdaptiveNavigator.push<void>(
      context,
      (_) => AdaptiveScaffold(
        backgroundColor: paper,
        appBar: AdaptiveAppBar(title: title),
        body: SafeArea(bottom: false, child: content),
      ),
    );
```

When replacing the existing helper, reuse the application's existing imports and `paper` constant rather than declaring them twice.

`AdaptiveApp` already installs `AdaptiveToolbarHost` in this package. If integrating with another app shell, inspect that integration and provide the toolbar host once; do not blindly nest duplicate hosts.

Keep the existing `AdaptiveNavigator` route lifecycle. On iOS it prepares the native push, renders the Flutter destination, then lets UIKit push the destination controller. A cancelled native swipe must not pop the Flutter route. A completed native pop sends `didPop` to Dart, which updates the Flutter stack and acknowledges the restored route.

### Declare the custom root header

On the existing root `AdaptiveScaffold`, use these properties. This is an argument fragment, not a second scaffold to place around the application:

```dart
backgroundColor: paper,
customHeaderBackgroundColor: menuOpen
    ? Color.alphaBlend(Colors.black54, red)
    : red,
customHeaderHeight: 64,
scaffoldKey: drawerKey,
useFixedToolbar: false,
tabBarHidden: menuOpen,
onDrawerChanged: (open) => setState(() => menuOpen = open),
```

`menuOpen`, `red` and `drawerKey` are existing fields/constants in `_InvestmentHomeState`. Preserve the drawer's current dimming colour. Keep the custom header outside the scrolling list.

On a normal iPhone the Flutter header's container height is `64 + MediaQuery.paddingOf(context).top`; its top padding is that same safe-area value. The native `customHeaderHeight` remains **64**, not 64 plus safe area. Native backing layout adds its own safe-area inset once.

## 4. Extend the scaffold-to-native appearance contract

In `AdaptiveScaffold`, retain the existing optional `customHeaderBackgroundColor` and `customHeaderHeight` API. Forward the page's `backgroundColor` as well:

```dart
IOS26SearchTabScaffold(
  bar: bar!,
  headerBackgroundColor: widget.customHeaderBackgroundColor,
  headerHeight: widget.customHeaderHeight,
  backgroundColor: widget.backgroundColor,
  hidden:
      widget.tabBarHidden ||
      !(ModalRoute.of(context)?.isCurrent ?? true),
  builder: (context) => _buildPage(context, omitBottomBar: true),
)
```

This expression belongs to the existing native-tabs branch of `AdaptiveScaffold`; retain that branch's validation and fallback logic.

Replace the `IOS26SearchTabScaffold` widget declaration with the following complete class. Preserve its imports and the existing `_SearchTabsState` implementation.


```dart
class IOS26SearchTabScaffold extends StatefulWidget {
  const IOS26SearchTabScaffold({
    super.key,
    required this.bar,
    required this.builder,
    required this.hidden,
    this.headerBackgroundColor,
    this.backgroundColor,
    this.headerHeight = 0,
  });

  final AdaptiveBottomNavigationBar bar;
  final WidgetBuilder builder;
  final bool hidden;
  final Color? headerBackgroundColor;
  final Color? backgroundColor;
  final double headerHeight;

  @override
  State<IOS26SearchTabScaffold> createState() => _SearchTabsState();
}
```

Replace `_SearchTabsState._configuration()` with the complete method below:


```dart
  Map<String, Object?> _configuration() => {
    'items': widget.bar.items!
        .map(
          (item) => {
            'title': item.label,
            'symbol': item.icon is String ? item.icon : null,
            'selectedSymbol': item.selectedIcon is String
                ? item.selectedIcon
                : null,
            'isSearch': item.isSearch,
            'badge':
                item.badgeText ??
                (item.badgeCount != null && item.badgeCount! > 0
                    ? '${item.badgeCount}'
                    : null),
          },
        )
        .toList(),
    'selectedIndex': widget.bar.selectedIndex,
    'placeholder': widget.bar.search?.placeholder ?? 'Search',
    'isDark': CupertinoTheme.brightnessOf(context) == Brightness.dark,
    'tint':
        (widget.bar.selectedItemColor ??
                CupertinoTheme.of(context).primaryColor)
            .toARGB32(),
    'hidden': widget.hidden,
    'pageColor': widget.backgroundColor?.toARGB32(),
    'transitionHeaderHeight': widget.headerHeight,
    'headerColor': widget.headerBackgroundColor?.toARGB32(),
    'headerHeight': (ModalRoute.of(context)?.isCurrent ?? true)
        ? widget.headerHeight
        : 0,
  };
```

The two heights have different jobs:

| Channel key | Meaning |
| --- | --- |
| `headerColor` | Actual custom-header color, including drawer dimming when applicable |
| `pageColor` | Root body/background color exposed behind native transition cards |
| `headerHeight` | Visible Duo side-lane extension; zero while the root is not current |
| `transitionHeaderHeight` | Persistent root-header metadata; retained while a detail is current |

Do **not** set `transitionHeaderHeight` to zero simply because a detail covers the root. UIKit needs the destination root's appearance before Flutter makes that root current again.

Continue publishing configuration through the existing channel on dependency/widget updates. Do not introduce a second navigation channel just for these values.

## 5. Decode and retain appearance on native root controllers

In `SearchTabView.swift`, insert/replace this block in the existing configuration handler before `let wasHidden = hidden`. It uses the class's existing `headerHeight`, `headerColor` and `pages` members.


```swift
        headerHeight = CGFloat((args["headerHeight"] as? NSNumber)?.doubleValue ?? 0)
        headerColor = (args["headerColor"] as? NSNumber).map { value in
            let argb = value.int64Value
            return UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                           green: CGFloat((argb >> 8) & 255) / 255,
                           blue: CGFloat(argb & 255) / 255,
                           alpha: CGFloat((argb >> 24) & 255) / 255)
        }
        let pageColor = (args["pageColor"] as? NSNumber).map { value in
            let argb = value.int64Value
            return UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                           green: CGFloat((argb >> 8) & 255) / 255,
                           blue: CGFloat(argb & 255) / 255,
                           alpha: CGFloat((argb >> 24) & 255) / 255)
        }
        for page in pages {
            page.transitionHeaderColor = headerColor
            page.transitionHeaderHeight = CGFloat((args["transitionHeaderHeight"] as? NSNumber)?.doubleValue ?? 0)
            page.transitionPageColor = pageColor
        }
```

Colors arrive as ARGB integers. Preserve alpha; do not decode these integers as RGBA. A nil background falls back to the native system background where it is consumed.

These assignments belong to the tab root `pages`. Newly created native detail controllers do not inherit the root's custom-header height.

## 6. Disable shading only for the custom header

In `NativeNavigationContent`, add or update these stored properties. `backingScroll` is the existing native scroll view used to coordinate Flutter content with UIKit.


```swift
    var transitionHeaderColor: UIColor?
    var transitionPageColor: UIColor?
    var transitionHeaderHeight: CGFloat = 0 {
        didSet {
            if #available(iOS 26.0, *) {
                // A solid custom header already separates content from the
                // status area; native scroll-edge shading washes out its red.
                backingScroll.topEdgeEffect.isHidden = transitionHeaderHeight > 0
            }
        }
    }
    var hidesNativeNavigationBar = false
```

The specific shading fix is:

```swift
backingScroll.topEdgeEffect.isHidden = transitionHeaderHeight > 0
```

This is a **package change**, not an application overlay. It uses the public iOS 26 scroll-edge effect API with an availability check. A page with no custom header has height zero and keeps its normal top edge effect. Do not disable all edge effects globally or alter the native tab bar material.

The header color and the transition backing color alone are insufficient: the native scroll-edge effect can wash out the retained root image while the backing remains solid red, producing the pale header plus contrasting strip seen in the rejected result.

## 7. Record the root's real header policy

In `NativeNavigationHost.prepareNativePush`, inside the existing `if managedRoutes.count <= 1` branch, use:

```swift
content.hidesNativeNavigationBar = content.transitionHeaderHeight > 0 ||
    page == nil || navigation.isNavigationBarHidden
```

Keep the rest of that branch: initialize the root `NativeRouteState`, set `managedNavigation`, enable `usesManagedRoutes` and install `completedNavigation`.

Do not infer the root's policy solely from `navigation.isNavigationBarHidden`. During debugging, the red custom-header root had that flag false even though it should not show a native bar. Its custom-header color and height were present, but transition handling was skipped because the policy was wrong.

The explicit custom-header declaration must therefore participate in the decision.

## 8. Coordinate the native transition and its backing surface

The complete current `NativeNavigationController` implementation is below. Replace the matching class when porting to a source version with the same surrounding types. If the target has additional behaviour, merge these methods/properties rather than deleting unrelated support.

This class depends on the existing `NativeNavigationContent` type and UIKit import. It is not a separate application controller to create alongside the package's controller.


```swift
private final class NativeNavigationController: UINavigationController, UINavigationControllerDelegate {
    var completedLayout: (() -> Void)?
    private let transitionHeaderBackdrop = UIView()
    private weak var backdropContent: NativeNavigationContent?
    private weak var backdropContainer: UIView?
    var requestedBack: (() -> Void)?
    var completedNavigation: ((UINavigationController, UIViewController) -> Void)?
    private(set) var transitioningBetweenRoutes = false
    var usesManagedRoutes = false {
        didSet { updatePopGestures() }
    }
    var routePopEnabled = true { didSet { updatePopGestures() } }
    private func updatePopGestures() {
        let enabled = usesManagedRoutes && routePopEnabled
        interactivePopGestureRecognizer?.isEnabled = enabled
        if #available(iOS 26.0, *) { interactiveContentPopGestureRecognizer?.isEnabled = enabled }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        updatePopGestures()
    }
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        topViewController?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }
    override func popViewController(animated: Bool) -> UIViewController? {
        if !usesManagedRoutes, viewControllers.count > 1, let requestedBack { requestedBack(); return nil }
        return super.popViewController(animated: animated)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTransitionBackdrop()
        completedLayout?()
    }
    private func layoutTransitionBackdrop() {
        guard let content = backdropContent,
              let color = content.transitionHeaderColor,
              content.transitionHeaderHeight > 0 else {
            transitionHeaderBackdrop.removeFromSuperview()
            return
        }
        let container = backdropContainer ?? view!
        container.backgroundColor = content.transitionPageColor ?? .systemBackground
        transitionHeaderBackdrop.backgroundColor = color
        transitionHeaderBackdrop.isUserInteractionEnabled = false
        transitionHeaderBackdrop.accessibilityElementsHidden = true
        let headerFrame = CGRect(x: 0, y: 0, width: view.bounds.width,
                                 height: view.safeAreaInsets.top + content.transitionHeaderHeight)
        transitionHeaderBackdrop.frame = view.convert(headerFrame, to: container)
        if transitionHeaderBackdrop.superview !== container {
            container.insertSubview(transitionHeaderBackdrop, at: 0)
        }
    }
    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        guard usesManagedRoutes else { return }
        transitioningBetweenRoutes = true
        let hidesBar = (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar ?? false
        // UIKit rounds its transition cards. The surface exposed behind a
        // custom-header root must use that page's colors, not system white.
        backdropContent = hidesBar ? viewController as? NativeNavigationContent : nil
        backdropContainer = transitionCoordinator?.containerView
        layoutTransitionBackdrop()
        // The root owns a Flutter header. Finish the native bar handoff now:
        // Duo's detached title otherwise outlives the interactive content slide.
        // Keep Flutter rebuilds from restoring the outgoing bar mid-transition.
        setNavigationBarHidden(hidesBar, animated: hidesBar ? false : animated)
        if let coordinator = transitionCoordinator {
            let source = coordinator.viewController(forKey: .from) as? NativeNavigationContent
            let sourceHidesBar = source?.transitionHeaderHeight ?? 0 > 0
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard context.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.transitioningBetweenRoutes = false
                    self.backdropContent = sourceHidesBar ? source : nil
                    self.layoutTransitionBackdrop()
                    self.setNavigationBarHidden(sourceHidesBar, animated: false)
                }
            }
        }
    }
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        if usesManagedRoutes {
            backdropContent = (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar == true
                ? viewController as? NativeNavigationContent : nil
            layoutTransitionBackdrop()
            setNavigationBarHidden(
                (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar ?? false,
                animated: false)
        }
        // didShow can precede UIKit's interactive-transition cleanup. Moving
        // the shared Flutter surface here can carry its temporary rounded mask
        // into the restored page. Keep the retained destination visible until
        // the coordinator finishes, then transfer the live surface next turn.
        let finish: () -> Void = { [weak self, weak viewController] in
            DispatchQueue.main.async { [weak self, weak viewController] in
                guard let self, let viewController,
                      self.topViewController === viewController else { return }
                self.transitioningBetweenRoutes = false
                self.completedNavigation?(self, viewController)
            }
        }
        if let coordinator = transitionCoordinator,
           coordinator.animate(alongsideTransition: nil, completion: { _ in finish() }) {
            return
        }
        finish()
    }
}
```

### Requirements the implementation must preserve

- `usesManagedRoutes` and `routePopEnabled` control the real UIKit edge/content pop recognizers.
- `willShow` selects the destination's header policy and records transition activity before Flutter can rewrite the outgoing bar.
- The backdrop is an ordinary noninteractive view, inserted behind content in the **public transition coordinator's container**. It is a background fill, not a fake navigation bar; it contains no text or controls.
- The header backing uses the same color and logical height as the custom root. The remaining backing uses the page background color.
- Convert the header rectangle into the selected container's coordinate system. Do not assume the navigation view and transition container have identical origins.
- A cancelled gesture restores source-bar visibility after the coordinator finishes. Restoring it only when interaction ends can be overwritten while UIKit completes the reversal.
- `didShow` forwards the completed controller after coordinator completion and a main-queue turn. Do not add a guessed 300 ms/one-second delay.
- Preserve native title APIs and UIKit-owned transition cards. The implementation does not identify or mutate private card classes.

The current cancellation classification uses a positive custom-header height to identify a custom-header source. If extending this package to native-bar-free screens without custom headers, audit that additional source type explicitly; do not assume this project's source classification covers every possible navigation design.

## 9. Prevent Flutter rebuilds from fighting a transition

At the beginning of `NativeNavigationHost.configure(_:)`, retain these guards and the detail controller's bar policy assignment:


```swift
    private func configure(_ page: NativeNavigationPage) {
        guard pendingPush == nil, !preparingPop else { return }
        guard externalNavigation == nil else { return }
        let navigation = regularNavigation ?? self.navigation
        guard (navigation as? NativeNavigationController)?.transitioningBetweenRoutes != true else { return }
        let source = page.nativeNavigationItem
        let destinationController: UIViewController = tabs == nil ? rootContent : content
        // The platform anchor may arrive after routeShown. Once it supplies
        // a native bar, cancellation must restore that bar on this controller.
        (destinationController as? NativeNavigationContent)?.hidesNativeNavigationBar = false
        let destination = destinationController.navigationItem
```

This excerpt is the beginning of the existing method. Keep all subsequent native navigation-item, search, tint and layout configuration.

The transition guard is necessary because a Flutter rebuild can republish an outgoing page while UIKit is animating a pop. Reapplying its title or bar visibility during that interval causes the title/back overlap.

The `hidesNativeNavigationBar = false` assignment is also necessary: a native page anchor can arrive after the new controller is created. Once that anchor supplies a native bar, the controller must remember that policy for cancellation.

In `completedNativeNavigation`, retain the existing push-completion branch. When the shown controller is still the last managed route and there is no pending push completion, reapply the existing page after cancellation:

```swift
} else if let page {
    // A cancelled interactive pop keeps this route. Restore its
    // native item after UIKit finishes reversing bar visibility.
    configure(page)
    layout()
}
```

That fragment belongs immediately after the existing `if let completion = pushCompletion` body, inside `if index == managedRoutes.count - 1`. It is not an independent `else` to attach elsewhere.

Do not change a cancelled gesture into a Dart pop. Keep the same route, BLoC state, watchlist selection and scroll position.

## 10. Preserve the shared Flutter-surface handoff

The package uses one live Flutter surface. Native controllers retain page images while another controller hosts that live surface. Preserve these responsibilities:

1. Before pushing, retain the root's rendered content.
2. Render/register the incoming Flutter page before configuring its native item.
3. Move the live surface to the new native content controller and let UIKit animate the push.
4. On a successful native pop, select the destination controller, move the live surface back and retain the destination cover until Dart has restored its route and geometry.
5. Notify Dart of the completed pop; wait for rendered frames and `routeShown` before revealing the live destination.
6. On cancellation, leave the route stack and live detail intact and restore its native controls.

Do not delete retained images early to hide the shading. That can expose the outgoing Flutter content on the returning root. Do not leave a retained image permanently over the live page: it intercepts input by design.

The earlier attempt to change only cleanup timing did **not** solve the reported white wedge on the physical phone. Treat timing coordination as lifecycle management, not proof that the corner-color defect is fixed. The observed wedge required correcting root policy and the exposed backing colors; the pale header required disabling the root's top scroll-edge effect.

## 11. Preserve Duo layout and the drawer

Keep the existing `SearchTabView` safe-area measurement. The hosted Flutter view may already be narrower than the window because UIKit owns the Duo side controls. Only report the remaining inset within that hosted surface:

```swift
let frame = flutterView.map { $0.convert($0.bounds, to: window) } ?? window.bounds
let safeFrame = window.bounds.inset(by: window.safeAreaInsets)
let safeLeft = max(0, safeFrame.minX - frame.minX)
let safeRight = max(0, frame.maxX - safeFrame.maxX)
let safeTop = max(0, safeFrame.minY - frame.minY)
```

These expressions use the existing `flutterView` and `window` from the layout method. Do not apply the window's whole right inset again in Flutter.

The visible Duo header extension and the transition backing are separate views with separate lifetimes:

- The side-lane extension fills only the exposed lane beside the Flutter header. Its visible `headerHeight` becomes zero on detail pages.
- The transition backing fills behind native transition content using persistent root metadata. It does not move or replace system side controls.

Keep the drawer as a side overlay, not a permanently reserved navigation column. Meridian limits its width to `min(320, availableWidth * 0.82)`, hides native tabs while it is open and dims the native header extension to match the Flutter scrim. Preserve Material ancestors for Material drawer/list widgets even though the app uses native iOS chrome.

## 12. Visual acceptance procedure for the implementing agent

Build and run with Build iOS Apps/XcodeBuildMCP. Inspect actual pixels, not only successful tool output or accessibility snapshots. Do not claim an injected swipe worked unless the screen visibly transitioned.

Use regular iPhone and folded Duo. Check expanded Duo when that posture is available; if tooling cannot switch posture or addresses the inactive display, state exactly which layout was not inspected. Do not silently substitute a different device.

### Inspect each scenario

| Scenario | Required result |
| --- | --- |
| Root at initial position | Red header fills its intended safe area; no duplicate native title |
| Root scrolled to holdings/allocation | Header stays fixed; no top shading, overflow or clipped controls |
| Push a holding | Native title/Back belong to the detail, and content transitions with them |
| Slow full-content swipe back | No stranded native title over the custom root; exposed backing matches root colors |
| Final swipe frames | No white top-right wedge after outgoing content leaves; no pale header/dark stripe |
| Short cancelled swipe | Same detail remains, title and native Back restored, actions still work |
| Push again after cancellation | No stuck transition flag or disabled gesture |
| Repeated pushes across different holdings | Correct symbol/title each time; no stale prior title |
| Return to scrolled root | Original scroll state retained, content still responds to input |
| Drawer open/close | Side overlay and scrim consistent with native extension; tabs restore |
| Duo root/detail | Native side controls stay in place; no doubled horizontal safe area |

Do not run automated tests unless the user requests them. Compilation and requested runtime visual checks remain necessary. If the user authorizes installation, install the final signed build on their physical phone. Do not inspect or record the physical device merely to claim verification without authorization.

### Simulator input fallback used in this project

The bundled `axe` CLI in the installed XcodeBuildMCP toolchain successfully drove interactive gestures when the higher-level gesture calls did not. Locate the installed binary; do not hardcode another machine's npm cache hash.

The following shell sequence is executable after setting the two environment variables to the installed tool and the selected simulator. Coordinates are for the observed 402-point-wide regular-iPhone layout; obtain current geometry before using them on another device.

```sh
: "${AXE_BIN:?Set AXE_BIN to the installed XcodeBuildMCP bundled axe executable}"
: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to the simulator under inspection}"
"$AXE_BIN" swipe \
  --start-x 80 --start-y 450 \
  --end-x 395 --end-y 450 \
  --duration 1 --delta 2 \
  --udid "$SIMULATOR_UDID"
```

In this CLI, `--delta` is the spacing between touch samples, not the total swipe distance. The 2-pixel spacing mattered. Do not interpret a command's successful exit as visual verification.

For a short cancellation attempt, use a much shorter horizontal stroke and inspect that the route actually remains and its controls restore. A short stroke alone is not proof of cancellation: watch the recording or inspect the transition.

Capture simulator video with `xcrun simctl io "$SIMULATOR_UDID" recordVideo --force /private/tmp/navigation-review.mp4`, stop it with Ctrl-C, and inspect frames around the gesture and its completion. Keep recordings out of source control unless explicitly requested.

## 13. Porting and delivery requirements

When updating another copy/version of `adaptive_platform_ui`:

1. Inspect its existing native navigator and toolbar host; preserve unrelated search and accessibility behaviour.
2. Add the Dart API/channel changes and native decoding together. A Swift-only patch cannot infer the app's background/header colors reliably.
3. Apply custom-header root policy, transition coordination, cancellation restoration and top-edge-effect opt-out as one coherent update.
4. Change example/demo route entry points to `AdaptiveNavigator` where they still mix Flutter route animation with native navigation chrome.
5. Keep the custom header opt-in. Native-only screens should continue using their normal navigation items and effects.
6. Review initial, scrolled, interactive, completed and cancelled states on the actual supported simulator layouts.
7. Report observed results separately from assumptions and unverified physical-device behaviour.
8. Commit only when requested; do not push or publish a package release without authorization.

### What to say in the delivery note

Name the changed package files and the application route change. State which devices and gestures were actually inspected. State whether the physical build was installed, and do not equate installation with a visual pass on the physical phone.

### Known limits of the reference implementation

- The reviewed product is a light-theme investment proof of concept with a solid custom root header. Other header materials, unusual heights, native-bar-free detail routes and different app shells need their own review.
- The UI evidence described here comes from simulator inspection plus user-supplied physical-phone screenshots. It is not a claim of exhaustive OS/device coverage.
- The package copy in this repository is the source of truth for this guide. The snippets are implementation excerpts, not a separately compiled sample application.
- Do not attribute an observed UIKit behaviour to Apple design guidance without checking current official documentation. The diagnosis here is based on runtime view inspection and recordings, not a claim that Apple requires this app's custom header design.
