# Sheet rotation cut: attempts 19 to 22 (2026-11-02)

Continues [sheet-rotation-cut-failed-attempts.md](sheet-rotation-cut-failed-attempts.md)
(attempts 1 to 18). Read that first for the bug, the old-screen picture iOS 26+
lays over a turn, and everything already ruled out. This file records the
2026-11-02 session: what attempt 19 fixed, the builds that isolated what it
did not fix, and attempt 20, which is installed but not judged.

Every build here was a signed Release build on Flutter `main`
(3.50.0-1.0.pre, engine `eede6c7e`), installed on the iPhone 18 Pro
(iOS 27.2) without launching it. "Clean" and "cut" are the user's reports.

## Status

- **Fixed (user: "fixed perfectly"):** the Markets and Orders filter sheets
  turn without a cut since attempt 19 (commit `801e350`).
- **Fixed after content changes (commit `8a76596`):** the Activity sheet.
- **Still cut at the end of the session:** any sheet that is **shorter than
  the screen in landscape**. The Watchlist sheet is one; a cut-down Activity
  sheet is another. Everything else about the page, tab, content and sheet
  configuration was eliminated one build at a time (table below).
- **Attempt 20 (user: "now that works"):** every custom detent resolved to
  full height in compact height, so no sheet was short in landscape. It
  removes the cut, but the user rejected it as a workaround: in landscape the
  sheet then covers the navigation bar even when the content is short. Its
  resolver is removed again; it stays the proven fallback.
- **Attempt 21 (user: "the cut is still here for that page"):** the page
  window's content is held still for the first half of a turn the way the
  sheet already is, so the navigation bar no longer grows under the picture.
  Short sheets are short again in landscape. Kept in; not enough on its own.
- **Attempt 22 (user: "still has the issues"):** the bar-coloured strip the
  package keeps above the navigation bar is no longer added and removed in
  layout, which no hold can pause; it stays in place and only its frame
  changes. Kept in; not the cause, or not the only one.
- **Open.** The short-sheet cut is not fixed. The next session starts from
  [sheet-rotation-retry-prompt.md](sheet-rotation-retry-prompt.md).

## Attempt 19 (commit `801e350`): nothing hidden, old frame held where the picture shows it

The reading behind it: the picture is the old screen unscaled at the window
origin, fading over the first 0.1 to 0.2 s of a turn. It is invisible wherever
what lies under it is the same pixels. Flutter's view stretched its last frame
to the animating bounds (`FlutterMetalLayer` has the default `resize`
gravity), and UIKit moved a sheet towards its new frame from the first frame.
Both parted from the picture, and its edge at 402 pt showed.

Changes, all public API:

- **Page:** `NativeNavigationContent.attachFlutter` sets the Flutter view's
  `contentMode = .topLeft` and the page background. The last frame stays
  unscaled at the top left while the bounds animate; the engine's own
  half-way metrics hold is untouched.
- **Gravity gotcha:** `CALayer.contentsGravity = .topLeft` pins the visual
  *bottom* left on iOS (the constants are named for macOS's flipped axis).
  POC build 9 (2026-10-29) set the layer gravity and so tested the wrong
  corner; the idea itself was never tested until now. `UIView.contentMode`
  picks the right constant.
- **Bar metrics with the size:** `iOS26ToolbarPlatformView` tags each
  `onNavigationMetrics` reading with the Flutter view size (`viewWidth`,
  `viewHeight`); `_NativeToolbarState` (a `WidgetsBindingObserver`) holds a
  reading measured for a size the view is not drawing yet and applies it in
  `didChangeMetrics`. One layout per turn, size and bar together.
- **Sheet:** UIKit sheets with one engine per sheet are kept (attempt 18's
  shape); the accelerometer, orientation and geometry hide is removed.
  `freezeForTurn` pauses the presented view's layer (`speed = 0`,
  `timeOffset` = now) and `snapAfterTurn` runs the layer clock past the
  animations' end at `transitionDuration / 2` plus a frame (`clockOffset`
  accumulates, never reset). Dismissal and startup failure snap too.
- Flutter `main` moved `ChangeNotifier` and friends to the `listen` package;
  `flutter pub get` has to run inside `packages/adaptive_platform_ui` as well
  or the analyser reports hundreds of false errors.

**Result:** Markets and Orders clean. Watchlist and Activity still cut.

## Content builds (commit `8a76596`)

The two sheets that still cut were the two with plain Flutter content whose
height depends on width: `ChipGroup` (a `Wrap` of chips, one row in landscape,
two or three in portrait) and `OpenSection` (an `AnimatedSize` body). Their
fit height differed per orientation and animated after the snap.

- Both sheets rebuilt from `AdaptiveSegmentedControl`, `SwitchLine`
  (`AdaptiveSwitch`) and `AdaptiveSlider`; `ChipGroup` removed. **Activity
  clean, Watchlist still cut.**
- The collapsible section removed from both; every control always shown;
  `OpenSection` deleted. **Activity clean, Watchlist still cut.**

## Isolation builds on the Watchlist tab

| # | Change on top of the previous build | Result |
| --- | --- | --- |
| 1 | `isModalInPresentation` off for every sheet; a non-dismissible sheet refused in `presentationControllerShouldDismiss` instead | cut |
| 2 | Watchlist sheet dismissible like the others (grabber, drag, tap outside, reset icon) | cut |
| 3 | The Following/Discover `AdaptiveSegmentedControl` removed from the Watchlist page (no native control left on the page) | cut |
| 4 | `WatchlistTab` builds the Activity page itself (`const Activity()`): same rows, same full sheet, same `activity` route | **clean** |
| 5 | Same, with a short sheet (`activityShort` route: kind control, amount slider, apply) | cut |
| 6 | Sheet paused from `SheetWindow`'s `frame`/`bounds` setters (the earliest point in a turn) instead of `viewWillTransition`; the coordinator only times the snap; 0.5 s fallback snap | cut |

Also added in build 4: `FlutterTurnPinning.pinOverlays` clears the flexible
autoresizing the engine gives `FlutterOverlayView`s and sets their
`contentMode`, from `attachFlutter` and `viewWillTransition` (page and sheet).
Overlays carry Flutter pixels drawn over a native control; a page with a
visible native control had one. Kept; it changed nothing for this cut.

**What the table says.** Dismissal configuration (1, 2), a native control on
the page (3), the tab, the page content and the sheet's own content (4) are
not the cause. The one variable that flips the result is the sheet's height
in landscape: a sheet that reaches the top of the screen (Markets, Orders,
Activity, build 4) is clean; a sheet that stops short of the top (the original
Watchlist sheet, build 5) cuts. The user put it this way: "once the sheet is
shorter and not reached to the nav bar when it's landscape, the cut happens".

**Why height matters, two readings, not separated by any build:**

1. The pause does not hold the sheet. A full-height sheet's top edge moves
   only ~50 pt between orientations, so a leak is invisible; a short sheet's
   top edge moves ~470 pt, so even a frame of movement shows against the
   picture. Build 6 pausing from the frame setter did not change the result,
   so either UIKit drives the sheet's frame per frame (not with a CA
   animation `layer.speed` can pause), or the paused view is not the one
   UIKit moves.
2. With a full-height sheet the picture of the old landscape screen holds only
   the sheet. With a short sheet it also holds the page's top: the UIKit
   navigation bar, which animates its height (32 pt in landscape to 103 pt
   with the status bar in portrait), the dimming view, and the pinned page.
   The bar's growth under the picture would show as an edge above the sheet.

Attempt 20 removes the condition instead of deciding between the readings.

## Attempt 20 (2026-11-02): full height in compact height. Works, rejected as a workaround

`NativeWidgetSheet.fullInCompactHeight`: every custom detent (`fit`,
`short`) resolves to `context.maximumDetentValue` when
`context.containerTraitCollection.verticalSizeClass == .compact`, that is on
an iPhone in landscape. UIKit's own medium sheets already do this. Portrait
is unchanged: the sheet fits its content. In landscape a short sheet now fills
the height, with its content at the top, exactly the configuration the user
judged "fixed perfectly" for Markets and Orders.

Everything from attempt 19 and the isolation builds stays in (pause from the
frame setter, overlay pinning, delegate-based refusal).

**Result (user): "now that works".** No cut on the short-sheet test rig. But
the fix is a change of design: in landscape the sheet always covers the
navigation bar, even when the content is short and the portrait sheet is
small. The user asked for a better way, so the resolver
(`fullInCompactHeight`) was removed again. It is the one configuration known
to turn clean with a short sheet, and the fallback if attempt 21 fails.

**What attempt 20 proves.** With the sheet held still (attempts 19 and the
isolation builds) and the page's top hidden behind a full-height sheet, the
turn is clean. With the same hold and the page's top visible above a short
sheet, it cuts. So the remaining cut is in the page's top region under the
picture, not in the sheet: reading 2 above. The one thing there that still
moves during the first half of the turn is UIKit's navigation bar (and on the
tab bar's side, the tab bar), which animates its height from 32 pt in
landscape to 103 pt with the status bar in portrait while the Flutter content
beneath it is pinned. The bar's bottom edge sweeps down over content the
picture shows unchanged, which reads as a cut line. On the plain page the
same thing happens; it was never re-judged after attempt 19.

## Attempt 21 (installed 2026-11-02, not judged): the whole page window turns discretely

New `Navigation/TurnHold.swift`: one object that pauses a layer's clock
(`speed = 0`, `timeOffset` = now) before UIKit adds the turn's animations,
and at `transitionDuration / 2` plus a frame (when Flutter draws the new
size) runs the clock past the animations' end (`timeOffset` moved ahead by
the duration, never reset), with a 0.5 s fallback and a snap on the
coordinator's completion. The sheet's `Level` now owns a `TurnHold` on its
presented view (same behaviour as before, less code).

The new part: `NativeNavigationHost.pageTurnHold` holds the **page window's
root view layer** (the tab controller's view, or the navigation controller's
when there are no tabs). `NativeNavigationController.viewWillTransition`
calls it before `super` forwards the turn to the page's Flutter controller,
so the pause is in place before UIKit's animated layout. For the first half
of the turn every UIKit view in the page window keeps its old frame: the
navigation bar, the tab bar, the scroll view that holds Flutter, the Flutter
view itself (so its `contentMode` pin only matters for the frame or two after
the snap). At the half-way point all of it jumps to the final layout, in the
same frame Flutter's new layout arrives. The window keeps its own animation
(bounds and rotation), so the content turns rigidly with the screen; the
band the window grows by shows the window's background, now set to
`systemBackground` in `NativeNavigationHost.init`.

This is the discrete resize iOS offers single-surface apps, done for the
whole window, page and sheet alike: old screen rigid under the fading
picture, one snap, rotation completes. Nothing is hidden or copied.

**Result (user): "the cut is still here for that page."** Committed as
`e8c9bbc` together with the test rig. The hold stays in: the discrete turn
is right in principle, and it pauses everything that is an animation. It
cannot pause what is not one, which is where attempt 22 looks.

## Attempt 22 (2026-11-02): no view is added or removed as a turn begins. FAILED

A layer hold pauses animations. Adding or removing a view is not an
animation: a view added during the first layout of a turn is on screen at
its final frame from the first frame, under the picture. The package did
exactly that in the page's top region.

`NativeNavigationController.layoutNavigationSafeAreaBackground` keeps a
bar-coloured strip above the navigation bar (for the Duo's vertical layout,
where UIKit's opaque bar background can leave a safe-area gap). On an
iPhone it is inserted whenever the bar's `minY` is above the view's top, that
is in portrait (59 pt, under the status bar), and removed in landscape, where
the bar starts at 0. It runs from `viewDidLayoutSubviews`, which UIKit calls
with the new geometry at the start of the turn:

- Landscape to portrait: the strip is inserted at frame 1, 59 pt tall and
  red, below the bar, which the hold keeps at its landscape height of 32 pt.
  The band from 32 to 59 pt is red at once, where the picture shows dimmed
  page content. A short sheet in landscape starts at about 100 pt, so that
  band is in view; a full-height sheet covers it. That is the one condition
  every build in the table shares.
- Portrait to landscape: the strip is removed at frame 1, but UIKit's own bar
  background, held at its portrait geometry, still covers the status bar
  area, so nothing changes there. The user described the cut in terms of the
  landscape sheet, which fits.

The change: the strip stays in the hierarchy and only its frame changes
(height 0 when the bar is hidden or starts at the top), so the change is an
animation, paused by the hold and finished at the snap with everything else.
It is inserted once, below the bar, and only while the bar is in the
hierarchy (UIKit removes a hidden bar). The drawer cover still finds it
through `safeAreaBackground`; a 0 pt frame masks nothing.

Other add-or-remove work in the same layout paths was checked and does not
run during a plain turn: `transitionHeaderBackdrop` (route transitions with
a Flutter header only), `largeTitleBackdrop` (large-title pages only), the
search transition glass (search only), the Duo strip shadow mask (Duo only).

**Result (user): "still has the issues."** Not committed at the time of
writing (working tree on top of `e8c9bbc`). The change is correct on its own
and stays.

What has never been measured in this series: whether the holds take effect
on the phone at all (the pause of the sheet view, of the page root view),
and what exactly moves in the page's top region during the first frames of
a landscape-to-portrait turn with a short sheet. Every build since attempt
19 was judged by eye at normal speed. A slow-motion recording of that turn,
read frame by frame, is the missing evidence; the retry prompt asks for it
first.

## Test scaffolding left in the tree

Committed together with attempt 21 so the test rig is reproducible; it must
be undone before shipping:

- `lib/features/watchlist/view/watchlist_page.dart`: `WatchlistTab` builds
  `const Activity(shortSheet: true)`; the real `Watchlist` widget is still in
  the file but unused, and its Following/Discover control is removed.
- `lib/features/activity/view/activity_filter_sheet.dart`: `short` flag and
  the `activityShort` route; `lib/app/native_sheet_app.dart` has the route;
  `lib/features/activity/view/activity_page.dart` has `shortSheet`.
- `lib/features/watchlist/view/watchlist_filter_sheet.dart`: dismissible
  with a reset icon (was `isDismissible: false` with a close icon).

Package changes that should stay: delegate-based refusal, overlay pinning,
`SheetWindow` hold, `TurnHold`, the page root hold, the persistent safe-area
strip. Attempt 20's detent
resolver is removed; its code is in this document's history if needed.

To restore the Watchlist page: `git checkout 49ea038 -- lib/features/watchlist/view/watchlist_page.dart`
and revert the `short` plumbing in the three Activity files and the sheet app.

## Attempt 23: start the page hold at the tab controller

The owner asked to proceed without a new recording. `SearchTabsController`
now starts the existing page-root `TurnHold` in `viewWillTransition` before
calling `super`, ahead of forwarding the transition to the selected navigation
controller. The navigation controller's existing hook remains for pages
without tabs. This does not change the sheet height, cover anything or add a
timer.

This is an unverified timing hypothesis: the earlier callback may still occur
after the relevant UIKit layout, and there is no frame-by-frame evidence that
the page hold is the cause of the remaining cut.

**Result: failed.** The signed Release build was installed on the iPhone 18
Pro without launching it; the owner reported that the cut remains and supplied
`GZPJ2967.MP4` and `IMG_0342.PNG`.

## Attempt 24: hold the sheet presentation container

The recording is a 60 fps screen recording. Frame numbers below are zero-based.
Landscape is intact at frame 240. At frame 241, as the landscape-to-portrait
turn starts, a sharp edge splits the sheet at the old picture's boundary: its
top edge, segmented control, slider and apply button are displaced together on
the two sides. The difference grows through frames 242–244, and the bar title
also splits. Frames 245–251 show the old sheet fading against the moving live
sheet; portrait has settled by about frame 257. The opposite turn begins around
frame 127, with the landscape layout settling around frame 143.

The visible cut is therefore not confined to the page's top region, contrary to
the stronger claim under attempt 20 above. The video shows that the sheet and
old picture do not stay aligned; it does not identify which UIKit layer moves,
whether the hold fires early enough, or whether the motion is a pausable layer
animation.

The sheet's existing `TurnHold` now targets the presentation controller's
`containerView` layer, an ancestor of the presented sheet, instead of the
presented view alone. This can also pause animations applied to that container,
which includes the dimming view. `TurnHold` retains a weak reference to the
layer it actually paused, so it resumes that same layer if presentation changes.
The existing timing hooks and sheet detents are unchanged. This remains a
hypothesis: an ancestor outside the container or a non-animated layout change
would not be held.

**Status: installed, not judged.** The signed Release build was installed on
the iPhone 18 Pro without launching it; configuration was returned to Debug.
