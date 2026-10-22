# Phase 1 baseline: current visual state and plain example app

No package code (`lib/`, `ios/`, `android/`) and no root app `lib/` was changed. The only new source is `packages/adaptive_platform_ui/example`.

All screenshots are under `docs/rewrite/baseline/<device>/`, JPEG-sourced PNGs at 368x800 (Duo 800x562). Each one was viewed individually. Debug builds, system light mode, simulators only.

## Devices actually used

| Slug | Simulator | Runtime | Notes |
| --- | --- | --- | --- |
| `ios27-iphone17pro` | iPhone 17 Pro | iOS 27.0 | The only iOS 27.x phone runtime installed is 27.0. |
| `ios26-iphone17pro` | iPhone 17 Pro | iOS 26.2 | |
| `ios18-iphone16pro` | iPhone 16 Pro | iOS 18.5 | |
| `iphone-duo-ios27.1` | iPhone Duo | iOS 27.1 | Landscape single-display posture, 800x562 capture, status/menu/tab controls in a right-hand side strip. Posture could not be changed. Input was ineffective (see Duo section), so only the initial state of each app was captured. |

No runtime was missing and none was installed.

## The example app

`packages/adaptive_platform_ui/example` (`flutter create --platforms=ios,android --org com.peterleung`, path dependency `../`, iOS deployment target 15.0). It uses only the public API, with no `SafeArea`, no MediaQuery maths, no platform checks, no `Material` wrapper, no private channels, no theme mode.

- Root `AdaptiveScaffold`, default `AdaptiveAppBar` (no colour, tint or `navigationBarColor`), one `AdaptiveAppBarAction` (menu, opens the drawer through `scaffoldKey`), three-destination `AdaptiveBottomNavigationBar` (`house`, `star`, `gear`), `drawer:`.
- Tab 1 "Large": `AdaptiveAppBar(title: 'Large', largeTitle: true, scrollController: <AdaptiveNavigationScrollController>)`; plain `ListView.builder` of 40 coloured rows with the same controller passed as `controller:`. Tapping a row calls `AdaptiveNavigator.push` to a detail page (plain `AdaptiveAppBar`, plain `ListView` of 40 rows).
- Tab 2: `CustomScrollView` + `SliverList` of 40 rows, plain app bar.
- Tab 3: `Column` with "TOP EDGE", a Material `ListTile`, an `AdaptiveSwitch`, `Spacer`, "BOTTOM EDGE".

Two things were needed in the example that are not about layout:

1. `localizationsDelegates` (Material, Cupertino, Widgets) on `AdaptiveApp`. Without them the app shows a red "No MaterialLocalizations found" error from `DrawerController` on every iOS tab (`ios27-iphone17pro/example-00-plain-no-localizations.png`). Android's `MaterialApp` supplies them; the iOS path does not.
2. Tappable rows are wrapped in `Semantics(button: true)` purely so UI automation can tap them (text rows were otherwise not exposed as tap targets). Detail-page rows have no `InkWell`, because an `InkWell` there throws "No Material widget found" (`ios27-iphone17pro/example-07-detail-no-material-error.png`: a pushed `AdaptiveNavigator` page has no Material ancestor).

Large title wiring: the documented route is one controller shared with the page's scroll view. The README says the scroll view should be `AdaptiveListView`; the brief asked for a plain `ListView`, so the plain `ListView` got the same controller. The title and its collapse work natively, but the plain `ListView` does not receive the native content inset, so Row 1 sits under the expanded large title (see below). No other non-obvious step was needed; the controller has to be disposed by the page, and `largeTitle`/`scrollController` have to be set to null/false for the other tabs (the app bar is rebuilt per tab).

## Per-device results: example app

Paths are relative to `docs/rewrite/baseline/<device>/`. "Hidden" means covered by native chrome and unreachable by scrolling unless stated.

### iOS 27.0, iPhone 17 Pro (`ios27-iphone17pro`)

| State | Screenshot | Observation |
| --- | --- | --- |
| Tab 1 initial | `example-01-tab1-large-initial.png` | Large title "Large" drawn over Row 1; Row 1 starts at y=0 under the bar, so the title and the row text collide. |
| Tab 1 scrolled a little | `example-01b-tab1-large-scrolled-a-little.png` | Title collapses to a centred inline "Large"; glass blur and scroll-edge fade at top. Row 1 faded under the bar. |
| Tab 1 bottom | `example-02-tab1-bottom.png` | Row 40 fully visible above the tab bar (bottom inset applied by `ListView` from the scaffold's rewritten MediaQuery). |
| Tab 2 initial | `example-03-tab2-initial.png` | Row 1 hidden under status bar and nav bar, Row 2 half covered. |
| Tab 2 bottom | `example-04-tab2-bottom.png` | Row 40 cut by the floating tab bar (the sliver list has no bottom inset). |
| Tab 3 | `example-05-tab3.png` | "TOP EDGE" under the status bar and clock; Material `ListTile` beside the nav title under the bar; "BOTTOM EDGE" behind the tab bar. `ListTile` does not throw here (root page has Material). |
| Drawer open | `example-06-drawer-open.png` | Flutter drawer sits under the native bar controls: title "Static", menu button and tab bar float over it, and the scrim does not cover them. The drawer's own content is empty at the top edge. |
| Pushed detail | `example-08-detail-initial.png` | Plain bar, Row 1 below the bar, no tab bar. Correct. |
| No localizations | `example-00-plain-no-localizations.png` | Red `MaterialLocalizations` error, app unusable. |
| Detail with `InkWell` | `example-07-detail-no-material-error.png` | Red "No Material widget found" error on the pushed page. |

### iOS 26.2, iPhone 17 Pro (`ios26-iphone17pro`)

| State | Screenshot | Observation |
| --- | --- | --- |
| Tab 1 initial | `example-01-tab1-large-initial.png` | Same as 27.0: large title overlaps Row 1. |
| Tab 1 scrolled a little | `example-01b-tab1-large-scrolled-a-little.png` | Collapses to inline title with glass blur at the top. |
| Tab 1 bottom | `example-02-tab1-bottom.png` | Row 40 above the tab bar, soft fade at the bar. |
| Tab 2 initial | `example-03-tab2-initial.png` | Row 1 under the nav bar and Dynamic Island. |
| Tab 2 bottom | `example-04-tab2-bottom.png` | Row 40 behind the tab bar. |
| Tab 3 | `example-05-tab3.png` | "TOP EDGE" under the status bar, "BOTTOM EDGE" behind the tab bar. |
| Drawer open | `example-06-drawer-open.png` | Same as 27.0: native bars over the drawer, not dimmed. |
| Pushed detail | `example-08-detail-initial.png` | Correct. |

### iOS 18.5, iPhone 16 Pro (`ios18-iphone16pro`)

| State | Screenshot | Observation |
| --- | --- | --- |
| Tab 1 initial | `example-01-tab1-large-initial.png` | Classic large title; Row 1 almost fully hidden beneath it (only a sliver above Row 2). |
| Tab 1 scrolled a little | `example-01b-tab1-large-scrolled-a-little.png` | Collapses to centred inline title with a hairline and translucent bar. |
| Tab 1 bottom | `example-02-tab1-bottom.png` | Row 40 fully visible above the tab bar. |
| Tab 2 initial | `example-03-tab2-initial.png` | Rows 1 and 2 hidden under the bar. |
| Tab 2 bottom | `example-04-tab2-bottom.png` | Last visible row is a cut Row 39; Row 40 is behind the tab bar. |
| Tab 3 | `example-05-tab3.png` | "TOP EDGE", the `ListTile` and "BOTTOM EDGE" are all hidden under the opaque bars; only the switch is visible. |
| Drawer open | `example-06-drawer-open.png` | Drawer is clipped between nav bar and tab bar; bars stay undimmed and on top. |
| Pushed detail | `example-08-detail-initial.png` | A blank band of about 47 pt between the bar and Row 1: top inset applied twice. |

### iPhone Duo, iOS 27.1 (`iphone-duo-ios27.1`)

Posture: landscape single display (800x562), right-hand side strip with clock, menu button and the three tab icons. I could not switch posture.

| State | Screenshot | Observation |
| --- | --- | --- |
| Example, Tab 1 initial | `example-01-tab1-large-initial.png` | Large title top-left; Row 1 sits below it and is not covered (unlike the phones). Rows stop at the side strip, so no content under the strip. Row 11 is cut at the bottom edge, which is normal scrolling. |
| Meridian, Portfolio initial | `meridian-01-portfolio-initial.png` | Red bar spans the full width including above the side strip; content respects the strip. |

Input limitation: taps and swipes against both apps had no effect (screen unchanged, clock advanced so the frame was live). The accessibility tree reports frame coordinates taller than the 562 pt screen (a swipe started at y=581), so input is probably being mapped into a different display or orientation. Nothing past the initial state on the Duo was verified: no scroll, tab switch, drawer, push or Preferences.

## Native bar: large title and plain default

What was checked: Tab 1 uses the plain native bar with `largeTitle: true`; other tabs and the detail page use the plain default bar.

| Device | Large title expanded | After a small scroll | System or imitation? |
| --- | --- | --- | --- |
| iOS 27.0 | System large title, left aligned, bold system font, no fill (transparent glass bar). Row 1 collides with it. | Collapses to the centred inline title; glass blur with scroll-edge fade; menu button and back button are glass capsules. | System UIKit. The collapse is driven by scroll offset the way UIKit does it. The glass capsules are UIKit's. The only fault is content not being inset below the expanded title for a plain `ListView`. |
| iOS 26.2 | Same as 27.0. | Same as 27.0. | System UIKit. |
| iOS 18.5 | Classic UIKit large title (34 pt bold, left); menu button is a plain blue SF Symbol bar button. Row 1 almost hidden. | Collapses to centred inline title with the classic translucent bar and hairline. | System UIKit classic bar, not an imitation. |
| Duo | Large title in the top-left, content below it, no overlap. | Not verified (input). | Looks like the system title; collapse not verified. |

Plain default bar on Tabs 2 and 3 and on the detail page: a standard `UINavigationBar`; glass on 26/27, classic translucent on 18. No colour, tint or custom background was set anywhere in the example.

Findings specific to the large title:

- A plain `ListView` with the controller attached collapses the title correctly but does not get the native top inset; the first row sits under the expanded title on all three phones. The README's requirement for `AdaptiveListView` is real, not optional.
- Switching tabs recreates the page (the example's body is a `switch`), so the large title is expanded again each time. Scroll offset is not retained in this setup.

## Baseline: Meridian (root app)

Same screenshot set per device where input worked. Meridian uses `navigationBarColor: red`, a native `presentDrawer`, `SafeArea(bottom: false)` and manual bottom padding.

| Device | Portfolio initial | Portfolio bottom | Markets | Drawer | Asset detail | Preferences | Observed defects |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iOS 27.0 | `meridian-01-portfolio-initial.png` | `meridian-02-portfolio-bottom.png` | `meridian-03-markets.png` | `meridian-04-drawer-open.png` | `meridian-05-asset-detail.png` | `meridian-06-preferences.png` | None visible. Content clears the red bar; last Portfolio section (Allocation) fully above the floating tab bar; drawer is a full-height native panel over the bars with a dimmed scrim. The status bar shows a "back to previous app" chip from launching via the tool; ignore it. |
| iOS 26.2 | same names | same | same | same | same | same | None visible; as 27.0. |
| iOS 18.5 | same names | same | same | same | same | same | None visible. Classic tab bar, red bar with white title, content correct, Allocation clears the tab bar. |
| Duo 27.1 | `meridian-01-portfolio-initial.png` | not captured | not captured | not captured | not captured | not captured | Initial only (input limitation). Red bar runs full width above the side strip, title left; cards respect the strip. No visible defect in the one state captured. |

On the iOS 27.0 run Markets was captured after a drawer/Preferences round trip; the Markets screenshot is the plain tab state.

## Which Meridian workarounds the example proves are required

Evidence is the example failing on all three phones without them.

| Meridian workaround | Required? | Evidence |
| --- | --- | --- |
| `SafeArea(bottom: false)` around tab content (`lib/main.dart:338`, `:104`) | Yes for non-scrolling and sliver content. | Tab 3: "TOP EDGE" under the status bar, "BOTTOM EDGE" behind the tab bar, and on iOS 18 the whole `Column` edge content is hidden under opaque bars. Tab 2: Row 1 hidden at the top and Row 40 behind the tab bar. |
| Manual `MediaQuery.paddingOf(context).bottom + N` (`:362`, `:475`) | Yes for slivers and any non-`ListView` scroll view. | Tab 2 bottom: Row 40 cut by the tab bar on 26, 27 and 18. Plain `ListView` (Tab 1) gets a bottom inset on 26/27 and 18, so only `ListView` is covered. |
| Top inset handling | Yes, and it is inconsistent. | Top inset is absent for Tab 2/3 (rows under the bar), absent for the large-title `ListView` (Row 1 under the title), but doubled on the pushed detail page on iOS 18 (about 47 pt blank band). |
| `Material(type: transparency)` wrapper (`:350`, `:467`, `:673`) | Yes. | A pushed `AdaptiveNavigator` page has no Material ancestor: an `InkWell` there throws "No Material widget found" (`example-07`). `ListTile` only works on the root page. |
| `localizationsDelegates` on the app | Yes on iOS. | Plain `AdaptiveApp` shows a red `MaterialLocalizations` error from the Drawer (`example-00`). |
| Private `adaptive_platform_ui/navigation` `presentDrawer` channel (`:201`) | Yes for a drawer that looks right. | The public `drawer:` renders a Flutter drawer under the native nav bar and tab bar on every phone: bars float over it undimmed on 26/27, and on 18 the drawer is clipped between the bars. |
| Per-page bar styling (`navigationBarColor`, tint, shadow) | Not exercised. | The example intentionally uses the default bar, which renders correctly on all three phones. This is cosmetic, not a layout dependency. |
| Large-title `AdaptiveListView` | Yes. | A plain `ListView` with the controller collapses correctly but Row 1 sits under the expanded title. |

## Build issues and how they were resolved

- `flutter create` generated a `test/widget_test.dart` referencing `MyApp`, which breaks `flutter analyze`; the file was deleted.
- First run showed the `MaterialLocalizations` error; `flutter_localizations` was added to the example (see above).
- Rows were not tappable by the UI automation until wrapped in `Semantics(button: true)`.
- The example needs no CocoaPods (the iOS project builds via Swift Package Manager integration); no `pod install` was run. The first Xcode build of the example took about 36 s and later ones about 10 s.
- Meridian built unchanged from the repository.
- Each app was built once through XcodeBuildMCP on the iOS 27.0 simulator, the `.app` copied, and installed on the other simulators with `install_app_sim`; this avoids a rebuild per device and ensures identical binaries.
- The screenshot tool returns a stale frame for several seconds after an action. Capture followed this routine: action, wait up to 10 s, screenshot, read it, and re-shoot if the content did not match the accessibility snapshot. A stale frame was once saved by mistake (Meridian iOS 26.2 asset detail) and was replaced after viewing.
- Flutter `Debug` configuration was used throughout, on simulators only; nothing was installed on a physical phone and no tests were run.
