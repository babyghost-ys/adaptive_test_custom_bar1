# Sheet rotation cut on a real phone: failed attempts

Attempts 19 to 21 (2026-11-02), and the builds that narrowed the remaining cut
down to sheets shorter than the screen in landscape, are in
[sheet-rotation-cut-attempts-19-20.md](sheet-rotation-cut-attempts-19-20.md).

## Attempt 19 (2026-11-02): nothing hidden; the old frame stays where the picture shows it

**Status: installed on the iPhone 18 Pro (iOS 27.2) as a signed Release build, not launched,
not judged.** Built on Flutter main (3.50.0-1.0.pre, engine `eede6c7e`), to which the user
had moved the project. Attempt 18's hide is removed; nothing is hidden or covered.

The reading of all earlier recordings behind this attempt: on the phone the old-screen
picture is a layer the size of the new window at the window's origin, holding the old screen
unscaled, fading over the first 0.1 to 0.2 s of the turn. It is invisible wherever what lies
under it is the same pixels. A native view qualifies at the start of the turn (it animates
from its old frame). Flutter's view did not: `FlutterMetalLayer` has the default
`contentsGravity` (`resize`), so the old frame was *stretched* to the view's animating
bounds from the first frame, and the picture's edge at 402 pt showed as old above, stretched
below. A UIKit sheet did not either: UIKit moved it towards its new frame from the first
frame. POC build 9 set `contentsGravity = .topLeft` on the layer, which on iOS pins to the
*bottom* left (the gravity constants are named for macOS's flipped axis), so that build
pinned the wrong corner and looked "really bad"; the idea itself was never tested.

The change, all public API, no snapshots, no timers on the engine:

- **Page:** `NativeNavigationContent.attachFlutter` sets the Flutter view's
  `contentMode = .topLeft` (UIKit picks the right gravity for iOS) and gives it the page
  background colour. While the screen turns the last frame stays unscaled at the top left,
  where the picture shows it; the engine's own half-way metrics hold is untouched, so the new
  layout arrives at the half-way point as before, now without the stretch before it. The band
  the view grows by shows the page colour instead of smeared pixels.
- **Bar metrics in the same frame as the size:** `iOS26ToolbarPlatformView` tags every
  `onNavigationMetrics` reading with the size of the Flutter view it was measured against;
  `_NativeToolbarState` (now a `WidgetsBindingObserver`) holds a reading measured for a size
  the view is not drawing yet and applies it in `didChangeMetrics`, when that size arrives.
  The page is laid out once per turn, size and bar together: no frame at the old size under
  the new bar (attempt 16's frames 89 to 92), no title wrap.
- **Sheet (UIKit, one engine per sheet, unchanged):** `NativeWidgetSheet.freezeForTurn`
  pauses the presented view's layer (`speed = 0`, `timeOffset` = now) from the sheet window
  root's and the sheet controller's `viewWillTransition`, before UIKit adds the turn's
  animations, so the sheet lies exactly where the picture shows it while the picture fades.
  At `transitionDuration / 2` plus a frame (when the sheet engine draws its new size)
  `snapAfterTurn` runs the layer clock past the animations' end (`speed = 1`, `timeOffset`
  moved ahead by the duration, never reset, so later animations are undisturbed): the sheet
  takes its new frame at once, together with its new Flutter layout. The coordinator's
  completion, a dismissal and a startup failure also snap, so no paused animation can block
  a dismissal. The sheet's Flutter view gets `contentMode = .topLeft` too. The dimming view
  and the window keep UIKit's animation.
- Removed: `SheetWindow` (frame-setter hide), `CMMotionManager` pose watching, the device
  orientation and scene geometry observers, `hideForTurn` / `revealAfterTurn`.

What the turn should look like: the old screen (page, bars in the picture, sheet) turns
rigidly with the window for the first half while UIKit's picture fades over an identical
image; at the half-way point page and sheet take their new layout in one step; the UIKit
bars animate throughout, as native bars do. Not covered: Flutter overlay views (Flutter
content drawn above a platform view on the page) still autoresize with the view.

## Attempt 18 (2026-10-30): UIKit sheet again, hidden while the screen turns

**Status: seventh build judged 2026-10-31 (user: "visually, seems it's less obvious").** The
sheet is gone from the turn. The user's slow-motion frame of the landscape to portrait turn shows
no sheet; what still splits is the page itself: UIKit's old-screen picture (the top-left square
of the old landscape page, tab bar and all) fading over the new portrait layout. That picture is
the one attempts 1 to 10 could not remove, hide or fill from inside the process, and it is there
on every turn with or without a sheet; at normal speed it reads as the crossfade. Signed Release
build installed on the iPhone 18 Pro (iOS 27.2) without launching it. No simulator build or run
was made for the seventh build (the cut only shows on the phone).

What the user established before this attempt: the full-screen sheet always turns clean; every
shorter sheet cuts. That fits one mechanism. On an iPhone in landscape (compact height)
`UISheetPresentationController` offers only the large detent, so a partial sheet changes
region during the turn while a full sheet keeps its region. UIKit's old-screen picture lies
over the new layout for the fade; over a sheet that moved, its edge reads as a cut. Apple's
own partial sheets vanish for the turn and come back after it.

The change:

- `AdaptiveNativeSheet.show` on iOS (`AdaptiveStyle.native`) goes back to the UIKit sheet with
  one Flutter engine per sheet (`present` on `adaptive_platform_ui/widget_sheet`, attempt 11's
  architecture, which was still in the tree). Detents, dimming, grabber and drag dismissal are
  UIKit's. The full-screen sign-in stays a Flutter page route, the one path known clean.
  Other platforms keep the stock `showModalBottomSheet`.
- `NativeWidgetSheet.hideForTurn` sets every presented sheet's view
  (`presentationController.presentedView`, the drop-shadow container with the corners and
  grabber) hidden with `alpha = 0`, and `revealAfterTurn` shows it again with a 0.2 s fade.
  The dimming view is UIKit's and stays. Only the page lies under the picture during the turn,
  the case judged clean.
- **First build (user: "I am still seeing it"):** the hide ran only from
  `viewWillTransition` on the presented `SheetViewController`. Whether UIKit's live-resize
  path reaches a presented controller in a separate window was never confirmed, so the
  second build fires the hide from four places, any of which may be the first or the only
  one to run: `viewWillTransition` on the sheet controller and on the sheet window's root
  controller, `UIDevice.orientationDidChangeNotification` filtered to a portrait/landscape
  pose the interface does not show yet, and KVO on `UIWindowScene.effectiveGeometry` when
  its `interfaceOrientation` changes. The reveal runs from the coordinator's completion when
  one exists, else 0.6 s after the last signal. Installed on the phone 2026-10-30, not judged.
- **Second build (user: "the hiding is not fast enough, so I still see the cut"):** every
  signal above runs after UIKit has laid out, and may have drawn, the first new-size frame.
  The third build hides from the earliest synchronous point in the process after the
  picture: the sheet window is a `SheetWindow` subclass whose `frame` and `bounds` setters
  call `hideForTurn` when the width changes, before any layout pass; the window root's
  `viewWillLayoutSubviews` does the same on a width change as a second early point. The
  later signals stay for the reveal. Installed on the phone 2026-10-30, not judged.
- **Third build (user: portrait to landscape is now fast enough, landscape to portrait is
  not):** the asymmetry is the picture's geometry, not timing. The picture sits at the
  window's origin, unscaled, clipped to the top-left 402 by 402 square of the new window.
  Portrait to landscape shows only the top of the old portrait screen, so the partial sheet
  at the bottom is clipped out, and hiding the new sheet is enough. Landscape to portrait
  shows the left half of the old landscape screen at full height, which holds the left half
  of the full-height landscape sheet, crisp, ending in a hard edge at 402 pt. That edge is
  inside the picture and no hide can remove it. Fourth build, chosen by the user:
  `SheetWindowRootController.supportedInterfaceOrientations` returns `.landscape` while the
  scene is landscape (the sheet window is key, so its root decides), `.all` otherwise. A sheet
  up in landscape holds landscape until dismissed; portrait to landscape stays free.
  **Fourth build result (user's screenshot):** the sheet window held landscape, but the page
  window beneath turned to portrait on its own, so the landscape sheet sat over a sideways
  page. A window root's mask only governs its own window. Fifth build: the sheet manager
  keeps `NativeWidgetSheet.supportedInterfaceOrientations` (`.landscape` while a sheet is up
  in landscape, `.all` otherwise, recomputed on present, after each turn and on close), the
  plugin exposes it as `AdaptivePlatformUiPlugin.supportedInterfaceOrientations`, and the
  Runner's `AppDelegate` returns it from `application(_:supportedInterfaceOrientationsFor:)`,
  which UIKit intersects with every window's root.
  **Fifth build result (user: "it locks to horizontal"):** once the sheet went the mask opened
  to `.all`, but UIKit only turns when the current orientation stops being allowed, so a page
  left in landscape stayed there until the phone moved again. Sixth build: on release, when
  the phone already lies portrait, the mask is `.portrait` for one turn and opens to `.all`
  0.7 s later; the device pose is read before the orientation notifications stop. Installed
  on the phone 2026-10-30, not judged.
  **Sixth build result (user: "huge fail", session interrupted):** the orientation hold was
  dropped altogether. The user restated the aim: keep the UIKit sheet, hide it when the
  orientation changes, nothing else.
- **Seventh build (2026-10-31): hide before the turn begins.** Builds 4 to 6 (the window
  root's orientation mask, `NativeWidgetSheet.supportedInterfaceOrientations`, the plugin's
  static property and the Runner `AppDelegate` override) are removed. Since the picture is
  taken by the render server as the turn begins, the only way to keep the landscape sheet out
  of it is to have hidden the sheet before the turn. UIKit turns from the accelerometer, at
  about 45 degrees of tilt and only after the pose has held for a moment. The sheet manager
  now reads `CMMotionManager` accelerometer updates (60 Hz, light low-pass, started with the
  first sheet, stopped with the last) and, while the interface is landscape, calls
  `hideForTurn` as soon as the phone has tilted within 30 degrees of the portrait axis
  (`atan2(|x|, |y|)`, ignored while the phone lies flat). `hideForTurn` now also calls
  `CATransaction.flush()` so the hide leaves for the render server at once instead of at the
  end of the run loop turn. The reveal is unchanged: the coordinator's completion, else 0.6 s
  after the last signal; while the tilted pose holds the hide is re-signalled every sample,
  and if no turn has come after 1.5 s the sheets come back and stay until the pose returns past
  60 degrees (orientation lock, or a pose the app does not turn to). Portrait keeps the frame-
  setter hide of the third build only, judged fast enough, and gets no early hide, so a locked
  phone never blinks its sheet. Raw accelerometer access needs no usage string.
- What no app code can do: the old-screen picture is taken by the render server before
  anything in the process runs, so it always holds whatever was on screen at that moment.
  The sheet therefore has to be gone before the turn, not merely hidden during it.

Not changed: the fit detent and its deferred replacement (attempt 13), the separate
presentation window per sheet, the page engine and native bars.

## Final state (2026-10-29): stock Flutter sheet, given up on the cut

**Not fixed. Closed by the user as "trying too much, I gave up".** After 17 attempts in the main
project and 19 POC builds, the user took POC build 19 as the final shape and asked for the main
app to match it. The cut itself is not removed; it is simply the configuration the user accepted.

What the main app now does (`adaptive_native_sheet.dart` in the package):

- `AdaptiveNativeSheet.show` uses Flutter's stock `showModalBottomSheet` on every platform, iOS
  included: root navigator, scroll controlled, safe area, drag handle when dismissible, 36 pt
  top corners, fill from `backgroundColor` or the system background. Non-fit detents go to
  `AdaptiveBottomSheet`. The full-screen path (sign-in) is unchanged.
- The attempt 15 `_FloatingSheet` (the Flutter-drawn iOS 26 floating panel that followed the
  native bar's bottom) is removed from the package. The dormant UIKit path (`bootstrap`,
  `AdaptiveNativeSheetContent`, `nativeSheetMain`, `NativeWidgetSheet.swift`) is left as it was.
- Adaptive native controls (`AdaptiveSegmentedControl`, `AdaptiveSlider`, date picker) still
  sit inside the sheet as platform views; the Activity, Markets, Orders and Watchlist filter
  sheets and the date and accounts sheets all go through this path. The Holdings filter keeps
  `AdaptiveFilterSheet` (UIKit content).

Checked on 2026-10-29 through XcodeBuildMCP, Debug builds: iPhone 17 Pro simulator (iOS 27.0)
and iPhone Duo simulator (iOS 27.1). On both the Activity filter opens as the stock sheet, the
native tab bar steps aside, the navigation bar dims over it, and the expanded section shows the
native `UISlider` inside the sheet. On the Duo the sheet draws in the content panel beside the
native side strip. The simulator never shows the rotation cut, so these runs only confirm the
sheet opens and lays out; they say nothing about the cut. A signed Release build was installed
on the iPhone 18 Pro afterwards without launching it.

The original adaptive sheet guide and the README were left untouched on the user's instruction.


## Current lead (2026-10-28): adaptive controls inside the sheet content

**Not resolved (2026-10-29, after POC build 18).** Eighteen POC builds on 2026-10-28 and 29, listed in the table under "POC builds, all failed", changed the control, its hosting, the sheet (Flutter or UIKit), dimming, the bars, the Flutter view's place in the host, the layer's stretch, the engine's rotation hold and the scene's resize mode. None removed the cut. The user judged them all huge fails.
The new phone comparisons point toward the controls and their composition inside the sheet,
particularly the segmented control. They do not yet prove that one particular widget or rendering
mechanism is the cause: the first failing comparison changed both the segmented control and the
Apply button, and the later attempts also changed how the segmented control was hosted.

The comparisons below were made on the iPhone 18 Pro using separate Release builds. The user
opened and rotated the apps and reported the results; no recordings or frame-by-frame measurements
were supplied for these POC runs.

1. A small standalone adaptive POC with a short sheet showed **no reported split**. It already
   contained an adaptive native button inside the sheet, so a native button by itself is not shown
   to be sufficient to cause the problem in every layout. A separate plain Flutter POC was also
   created, but no phone rotation result for it was reported.
2. The adaptive POC was changed to closely match the original Activity page and its short,
   collapsed filter sheet, including the native toolbar and tab bar. The sheet retained the
   original Flutter Material chips and Apply button. The user reported **no problem**.
3. In that Activity sheet, the All/Bought/Dividends chip row was replaced with an
   `AdaptiveSegmentedControl`, and the Apply button was also changed to `AdaptiveButton`. Both
   use native iOS views in this configuration. The user reported the **cut appeared** and
   identified the segmented control as a suspected cause. Since both controls changed at once,
   that comparison does not isolate the segmented control alone.
4. The POC kept the native Apply button but replaced the segmented control's Flutter `UiKitView`
   embedding with a real `UISegmentedControl` hosted directly in a UIKit window and positioned
   from Flutter. The user reported **the cut remained**. This did not establish whether the
   window-hosted control stayed aligned throughout the turn, or whether the segmented control,
   the Apply button, or their surrounding composition caused the cut.
5. The POC kept that window-hosted native segmented control and restored the original Flutter
   Material Apply button. The user again reported **the cut remained**. This makes the Apply
   button's sheet `UiKitView` unnecessary for reproducing the latest result, but does not by
   itself prove that the segmented control is the sole cause.

6. (2026-10-28, build 3, unverified on the phone) The window-hosted diagnostic was removed. The
   sheet uses the package's `AdaptiveSegmentedControl` (a Flutter platform view) again, and the
   package's `iOS26SegmentedControlView` sets opaque background and divider images through
   `UISegmentedControl`'s public appearance API, so the control is a real `UISegmentedControl`
   without the Liquid Glass selection backdrop. Reasoning: every configuration that showed the
   cut held a `UISegmentedControl` with its default selection, whose backdrop
   (`UISegmentedControlSelectedSegmentVibrancyEffect`) samples the Flutter surface beneath it;
   the configurations without the cut held only Flutter chips or a filled native button, which
   have no backdrop. **FAILED on the phone:** the user reported "even worse": the cut was
   still there, and the control had collapsed to a thin 3 pt bar, since `UISegmentedControl`
   takes its intrinsic height from its background image (the 3 by 3 pt resizable image). The
   Liquid Glass selection backdrop is therefore not the cause, or not the only one. Build 4
   restores the package's original `iOS26SegmentedControlView.swift` and keeps
   `AdaptiveSegmentedControl` in the sheet. What still separates the failing from the passing
   builds: a `UISegmentedControl` of any appearance in the sheet area fails; Flutter chips, and
   (in a different, shorter layout) a filled native `UIButton`, pass. Whether any plain UIKit
   view at that spot fails, or only `UISegmentedControl`, has not been tested.
7. (2026-10-28, build 4) **FAILED.** The reverted build, with the package's
   `AdaptiveSegmentedControl` as an ordinary Flutter platform view (default Liquid Glass
   appearance, red tint) and the Flutter Apply button, was installed on the iPhone 18 Pro. The
   user reported the cut is still there and asked to stop. So the smallest reproduction so far
   is: the Activity page with native toolbar and tab bar, the Flutter-drawn fit sheet, and one
   `AdaptiveSegmentedControl` inside it. No further attempt was made.
8. (2026-10-28, POC build 5, unverified on the phone) Rebuilt from the top instead of patching
   the control: the Activity filter is now `AdaptiveFilterSheet`, the UIKit sheet whose content
   UIKit draws (`NativeFilterSheet.swift`), the one sheet design recorded above as turning
   without the cut. The engine never leaves the page and nothing Flutter draws sits in or over
   the sheet. The native sheet gained a content-fitting detent, an `AdaptiveFilterDate`
   (compact `UIDatePicker`) and an `AdaptiveFilterSection` disclosure row so the Activity sheet
   keeps its design: segmented kind, symbol chips, and date, period and amount behind the row.
   **FAILED on the phone:** the user reported the cut is still there. A sheet with no Flutter in
   it and no platform view cuts too, so neither Flutter content in the sheet nor the
   platform-view hosting of the control is the cause, and the earlier note that a sheet with
   native UIKit content turns without the cut does not hold on this build.
9. (2026-10-28, POC build 6, unverified on the phone) Build 5 with the kind control as native
   chips instead of a `UISegmentedControl`; nothing else changed. This is the isolation test
   for the control itself inside a UIKit sheet. **FAILED on the phone:** the cut is still
   there, and the user noticed it shows once the sheet is expanded (date, period and slider
   visible) and so tall enough to cross the 402 pt line. The `UISegmentedControl` is cleared.
   Reading of all builds so far: every clean build drew the sheet in Flutter, so it stretched
   with the page while the engine held the old frame for the first half of the turn and matched
   UIKit's fading old-screen picture; every cut build had a UIKit view (sheet or control) over
   the Flutter view, which UIKit laid out at its new place at once, so the picture's edge
   crossed it as old above, new below.
10. (2026-10-28, POC build 7, unverified on the phone) Two comparisons in one install: the
   filter icon opens build 6's UIKit sheet undimmed (`dims: false`, no `UIDimmingView`); the
   toolbar's search icon opens the same filter as a Flutter-drawn sheet with Flutter chips and
   slider only, expanded so it crosses the 402 pt line. The first tests the dimming view; the
   second tests whether a tall sheet that stretches with the page stays clean. **FAILED on the
   phone (2026-10-29):** both sheets cut. The user's frame of the Flutter-drawn sheet shows the
   old picture of the sheet fading over the new layout, offset, chips doubled. So a tall sheet
   drawn by Flutter with no UIKit view in it cuts too, and the undimmed UIKit sheet cuts. Dimming
   is cleared, UIKit views over the page are cleared, and the "stretches with the page" reading
   in finding 9 is wrong. What is left: every clean sheet was short enough to stay below the
   402 pt line in portrait; every tall sheet, Flutter or UIKit, cut. The plain page is judged
   clean, yet it crosses that line too, so sheet content (white, high contrast, straight edges)
   may only make the same crossfade visible.
11. (2026-10-29, POC build 8) No fix. The UIKit filter sheet is back to its design:
   `UISegmentedControl` at the top, dimming on; the search icon no longer opens the comparison
   sheet. Installed on the iPhone 18 Pro.
12. (2026-10-29, POC build 9, unverified on the phone) First change to the Flutter side of the
   collision: `RotationViewController`, a `FlutterViewController` subclass set in the storyboard,
   sets the Flutter view's layer and its subviews' layers to `contentsGravity = .topLeft` in
   `viewWillTransition` and restores them when the coordinator completes. The old frame stays
   unscaled at the top-left during the turn, the same pixels as UIKit's old-screen picture,
   instead of stretching to the animating bounds. Attempt 9 tried this with cover views; this
   applies it to the layer itself. **FAILED on the phone:** "still really bad".
13. (2026-10-29, POC build 10, unverified on the phone) Build 9 plus the engine's half-way hold
   released: `RotationViewController` clears `shouldIgnoreViewportMetricsUpdatesDuringRotation`
   right after `viewWillTransition`, so the layout pass that follows sends the new metrics at
   once and Flutter renders the new size from the first frame, unscaled at the top-left, the way
   a UIKit view lays out under the fading picture. **FAILED on the phone:** "still no".
14. (2026-10-29, POC build 11, unverified on the phone) `UIRequiresFullScreen = YES` again
   (attempt 8's key), now on the single-view app with no engine hand-over or covers of our own,
   plus builds 9 and 10's `RotationViewController`. Per TN3192 the scene resizes discretely
   from iOS 27, so no live resize and no old-screen picture. **FAILED on the phone:** "still
   no"; the user saw the cut a little smaller once the sheet nearly filled the screen. The key
   and the view-controller subclass wiring are removed again.
15. (2026-10-29, POC build 13, unverified on the phone) The host keeps the Flutter view inside
   `NativeFlutterScrollView`, the navigation controller's content scroll view, and re-pinned
   its viewport to the scroll bounds only in `layoutSubviews`. During a turn UIKit changes that
   scroll view's offset as the bars change height, so between that change and the next layout
   pass the Flutter surface sat displaced, which fits the offset ghost in the user's build 7
   frame and attempt 16's "offset grows each frame". The scroll view now re-pins the viewport
   in its `bounds` and `contentOffset` setters. **FAILED on the phone:** "still really bad".
16. (2026-10-29, POC build 14, unverified on the phone) The Flutter viewport is no longer inside
   the host's scroll view at all: the page's view is a plain container holding the scroll view
   and, beside it, the viewport with the Flutter view. No offset change can move the surface.
   **FAILED on the phone:** "still no".
17. (2026-10-29, POC build 15, unverified on the phone) Bisecting the native pieces. The toolbar
   and the tab bar are Flutter platform views on the page (`iOS26ToolbarPlatformView`,
   `iOS26TabBarPlatformView`), so every build so far composited the page through Flutter's
   platform-view path. Build 15 keeps `AdaptiveScaffold`, the native host and build 14's layout,
   and drops `appBar` and `bottomNavigationBar`. Sheet as build 8. **Still cut on the phone:**
   the bars are cleared.
18. (2026-10-29, POC build 16, unverified on the phone) Build 15 with the filter as a stock
   `showModalBottomSheet` holding the Flutter-only content, opened expanded. No UIKit sheet, no
   bars, no platform view; only the adaptive app and its native host container remain. The
   user asked for adaptive controls in the sheet instead; no rotation result was given.
19. (2026-10-29, POC build 17, unverified on the phone) Build 16 with the package's Flutter-drawn
   `AdaptiveNativeSheet` holding adaptive controls: `AdaptiveSegmentedControl` at the top and
   an `AdaptiveSlider` in the open section, both native platform views. Bars still off. The
   user asked for the bars back before giving a rotation result.
20. (2026-10-29, POC build 18, unverified on the phone) Build 17's sheet with the native toolbar
   and tab bar restored: the app as designed, with the package's Flutter-drawn sheet and
   native controls inside it. **FAILED on the phone (2026-10-29):** the user judged builds
   9 to 18 "all huge fails".
21. (2026-10-29, POC build 19, unverified on the phone) The user pointed out that no build had
   shown Flutter's own stock sheet with adaptive native controls inside it: build 16 was the
   stock sheet with Flutter-only content and no rotation result, builds 17 and 18 used the
   package's `AdaptiveNativeSheet` route. Build 19 opens the filter with
   `showModalBottomSheet` (root navigator, scroll controlled, white, 36 pt top corners, drag
   handle) holding `ActivityFilterContent` with `AdaptiveSegmentedControl` and
   `AdaptiveSlider`, opened expanded; native toolbar and tab bar on. No package sheet code is
   involved. Installed on the iPhone 18 Pro (first install attempt hit a connection reset,
   the retry succeeded).

## POC builds, all failed (2026-10-28 to 2026-10-29)

Every build was a signed Release build installed on the iPhone 18 Pro (iOS 27.2) and rotated
by the user with the Activity filter sheet open. "Cut" is the user's report.

| Build | Sheet | What changed | Result |
| --- | --- | --- | --- |
| chips | Flutter route, Material chips, short | baseline | clean |
| 1 | Flutter route | `UISegmentedControl` hosted in the window, glass | cut |
| 2 | Flutter route | window-hosted control, opaque images | not reported |
| 3 | Flutter route | `AdaptiveSegmentedControl` platform view, opaque images (collapsed to 3 pt) | cut |
| 4 | Flutter route | `AdaptiveSegmentedControl` platform view, default glass | cut |
| 5 | UIKit (`AdaptiveFilterSheet`) | whole sheet rebuilt in UIKit, `UISegmentedControl`, fit detent | cut |
| 6 | UIKit | build 5 with native chips instead of the segmented control | cut |
| 7 | UIKit undimmed + tall Flutter route | dimming off; tall Flutter-only sheet on the search icon | both cut |
| 8 | UIKit | segmented control and dimming restored; no fix | cut |
| 9 | UIKit | `RotationViewController`: Flutter layer `contentsGravity = .topLeft` during the turn | cut |
| 10 | UIKit | build 9 plus engine's half-way metrics hold released at turn start | cut |
| 11 | UIKit | build 10 plus `UIRequiresFullScreen` (discrete resize, TN3192) | cut, a little smaller when the sheet nearly filled the screen |
| 12 | stock Material | stock-Flutter-only comparison, dropped at the user's request, not built | |
| 13 | UIKit | Flutter viewport re-pinned in the host scroll view's `bounds` and `contentOffset` setters | cut |
| 14 | UIKit | Flutter viewport moved beside the host scroll view, not inside it | cut |
| 15 | UIKit | no app bar, no tab bar (no platform view on the page) | cut |
| 16 | stock Material | no bars, stock Flutter bottom sheet | no result; user wanted adaptive controls |
| 17 | package Flutter route | no bars, `AdaptiveSegmentedControl` and `AdaptiveSlider` inside | no separate result |
| 18 | package Flutter route | bars restored, build 17's sheet | cut |
| 19 | stock Material (`showModalBottomSheet`) | bars on, `AdaptiveSegmentedControl` and `AdaptiveSlider` inside | taken as final by the user; cut not reported fixed |

What the table rules out as the sole cause: the segmented control (6), the platform-view
hosting (1, 5), Liquid Glass (3), Flutter content in the sheet (5, 6), the dimming view (7),
the bars and their platform views (15), the Flutter view's place inside the host scroll view
(13, 14), the layer stretch during the turn (9), the engine's half-way hold (10), and live
resize itself if `UIRequiresFullScreen` took effect on the phone (11). The only clean
configuration remains a short sheet that stays below the 402 pt line in portrait; every tall
sheet, Flutter or UIKit, with or without native controls, with or without bars, cut.

What was never isolated: the native host container itself (`NativeNavigationHost`,
`NativeNavigationController`, `UITabBarController`) with nothing native visible, and a
stock Flutter app with no package code, which the user considers known clean. The
difference between those two is the last untested split.

**State of the POC after build 18:** package sheet (`AdaptiveNativeSheet`, Flutter route)
with `AdaptiveSegmentedControl` and `AdaptiveSlider` inside, bars on, Flutter viewport beside
the host scroll view (build 14), scroll view re-pinning (build 13), `RotationViewController`
present in `AppDelegate.swift` but not wired, `UIRequiresFullScreen` removed. The package
copies in `poc_adaptive/` and on the Desktop match except a pre-existing tab bar difference.
The main project's package is untouched by all of this.

The current POC is at `poc_adaptive/` in this workspace and as the **Adaptive Sheet Rotation
POC** folder on the Desktop. Its copied adaptive package is independent of the original project;
the window-hosted control experiment is POC-only. The POC is a changing working copy, not a
preserved snapshot of every version above. The original project's working-tree sheet code also
contains changes beyond commit `3cc3a20`; the POC copied that working-tree package.

The agent did not launch or inspect these builds on the physical phone; the reports above are
the user's observations. A simulator run of the Activity POC showed a blank page with the native
tab bar, including when started through Flutter; its cause was not resolved, so the sheet and
rotation could not be checked there. Build and installation success do not establish a fix.

## Previous state (2026-10-27): not resolved

**Not resolved.** The code at that point was attempt 15 (commit `3cc3a20`). The user tested it on
the iPhone 18 Pro and said it is better than the earlier attempts but still not good enough, so it
is not the fix. Attempts 16 and 17 were built on it and the user judged both failed. Their code
is reverted; only these notes remain.

Attempt 15 stops putting Flutter content in UIKit sheets for now. On iOS, `AdaptiveNativeSheet`
shows each sheet as a Flutter route on the root navigator:

- The native tab bar steps aside while a sheet is up.
- The sheet's top stays below the native navigation bar, and longer content scrolls inside it.
- The full-screen sign-in is an opaque page route, and the navigation bar hides once it covers
  the screen.

The UIKit sheet code (`NativeWidgetSheet.swift`, `nativeSheetMain`) is still in the project but
not used.

What remains on the phone was described by the user after attempt 16, which differed from
attempt 15 only in how the sheet follows the native bar during a turn, and is recorded in
`HVYU3067.MP4` (see attempt 16):

- "a slight cut off in the middle": during each turn a picture of the old screen fades out over
  about 11 to 14 frames, and its straight edge crosses the new layout;
- "the background content seems not behaving correctly when turning": the old page shows
  through that picture over the new sheet, and in the first frames of a turn Flutter draws the
  page in a layout that matches neither orientation.

**Attempts 1–14, 16 and 17: FAILED.** None of those attempts resolved the reported rotation
problem, and neither does attempt 15. Each was installed as a Release build on the iPhone 18 Pro.
The user reported that attempt 14 was "way worse."

**Attempt 11 (2026-10-25): independent sheet engines — FAILED.** Implementation
described below and in [native-sheet-engines.md](native-sheet-engines.md).
The user confirmed that the problem remains on the phone and requested
documentation only, with no retry. No further implementation changes were made.

**Attempt 12 (2026-10-26): system `CAMetalLayer` presentation — FAILED.** After
installation, the user confirmed that the problem remains on the phone and
requested documenting the failure with no retry. Only documentation was updated
after that report.

## The bug

A Flutter widget shown in a real UIKit sheet (`AdaptiveNativeSheet` →
`NativeWidgetSheet.swift`, for example the Watchlist filter sheet) is cut in two when the phone
turns. The user's recording is `JXWK3978.MP4`.

- In both directions (portrait → landscape and landscape → portrait), a straight line crosses the
  screen about 46% of the way down. 402 pt is the short side of the screen, and 402 / 874 = 46%.
- Above the line is the old screen, unscaled. Below it is the live content, stretched.
- The line crosses the sheet and the page behind it alike, and turns with the content.
- The iOS Simulator never shows it. The Debug simulator build looks right.
- A plain Flutter page with no sheet, and a sheet with native UIKit content, turn without the cut.

## The idea behind these attempts

iOS 26+ treats a rotation as a live resize of the window scene. In UIKitCore (iOS 27),
`-[UIWindowScene _computeMetricsAndCrossFadeInLiveResize:withTransitionContext:]` does this:

1. It returns without a picture unless `_effectiveUISettings.inLiveResize` is set and
   `_UISceneLiveResizeSnapshotsEnabled()` returns true. That function requires the `UIKit` /
   `live_scene_resize` feature flag and
   `[[_UISceneLiveResizePrototypeSettingsDomain rootSettings] snapshottingEnabled]`.
2. It picks the top scene-sized window with a root view controller.
3. It calls `_makeUISceneViewForLiveResize`, which calls `_UISnapshotScreenAtViewRectAfterCommit`. That makes a render-server
   picture through `_UISnapshotLayerIdRectAfterCommit`. The picture has autoresizing on, takes no
   touches, and has `disableUpdateMask` set.
4. `-[UIWindow _insertLiveResizeSnapshot:]` (a direct call, not `objc_msgSend`) adds the picture
   with `addSubview:` and keeps it in `UIWindow._lowestLiveResizeSnapshot`. The scene keeps it in
   `_liveResizeSnapshot`.
5. It lays the scene out at its new size (`_computeMetrics:withTransitionContext:`).
6. `_scheduleResizeFinishedActionAndFadeOutSnapshot` fades the picture out.

The idea: the picture keeps its old size and content while the window takes its new one, so it is
cut where the two overlap. That would give a straight edge at 402 pt.

## Attempt 1 (earlier session): hide the picture at `viewWillTransition`

Scanned `windowScene.windows` in the top sheet's `viewWillTransition(to:with:)` and hid any subview
whose class name contains `Replicant`, takes no touches, and resizes with the window.

**Result: no change on the phone.**

## Attempt 2 (earlier session, kept only in `git stash@{0}`): hook `-[UIWindow didAddSubview:]`

Added a `didAddSubview:` override to `UIWindow` through the Objective-C runtime. While a sheet was
up, it hid any added subview that matched the same test (`Replicant` class, no touches, resizes
with the window). It never caught the picture: UIKit adds it through a direct call, and the class
check may not match what the device makes.

**Result: no effect.**

## Attempt 3 (this session): turn the setting off

```swift
// LiveResizeSnapshots.suppress(true) when the first sheet opens, false when the last closes
let settings = [_UISceneLiveResizePrototypeSettingsDomain rootSettings]   // via class_getClassMethod
settings.snapshottingEnabled = false                                        // restored afterwards
```

- The first build crashed as soon as a sheet opened. `unsafeBitCast(AnyClass, to: NSObject.self)`
  sent a message to Swift's wrapper around the Objective-C class, not to the class itself.
- The second build, calling `+rootSettings` through `class_getClassMethod`, did not crash.

**Result: the cut is unchanged.**

## Attempt 4 (this session): wrap the method that makes the picture

Replaced the implementation of
`-[UIWindowScene _computeMetricsAndCrossFadeInLiveResize:withTransitionContext:]`, which UIKit
calls through `objc_msgSend`. Both arguments were passed through as raw pointers. After the
original ran, and while a sheet was up, the wrapper hid:

- the view in the scene's `_liveResizeSnapshot`,
- the view in each window's `_lowestLiveResizeSnapshot`,
- or, if neither was found, any view just added to a window that takes no touches and resizes with
  the window.

**Result: the cut is unchanged. Confirmed on the phone.**

## What this shows

Two separate ways of stopping UIKit's live-resize picture, one at its setting and one right after
it is made, had no visible effect. So the cut is not UIKit's live-resize snapshot, or not only
that, and that idea is dropped. The cause has to be found in how the layers are rendered: what each
Flutter view's layer shows while the engine draws into another view, how a layer whose content is
a different size from its bounds is drawn while the window turns, and why this differs between the
simulator and the phone.

The attempt 4 code is removed from `NativeWidgetSheet.swift` before the next attempt.

## Rendering findings (Flutter 3.47.8 engine source and UIKitCore, iOS 27)

**How a Flutter view shows a frame.** `FlutterView`'s layer is `FlutterMetalLayer`, on a device and
on the simulator alike (`GetCoreAnimationLayerClassForRenderingAPI`). It is a plain `CALayer`:

- The engine renders into an IOSurface, and `presentOnMainThread:` sets it as `layer.contents`
  inside its own `CATransaction`.
- The layer never sets `contentsGravity`, so the default `resize` applies: a frame of another size
  is stretched to the layer's bounds of the moment.
- `presentTexture:` drops any frame whose size is not the layer's current `drawableSize`.
- A view only gets new frames while its controller is `engine.viewController`. `surfaceUpdated:`
  points the engine's platform views controller and surface at that view.

**Native views inside a Flutter view.** The platform views controller adds them as subviews.
Flutter content drawn above them goes into `FlutterOverlayView`s:

- Each overlay is a wrapper view with `clipsToBounds`, framed in points to the overlay rect, and
  holds an inner view the size of the whole Flutter view.
- No autoresizing is set, and frames are only updated when the engine composites that view.
- There is one pool per engine, so overlays and native views follow `engine.viewController`.

**Rotation in Flutter.** `FlutterViewController viewWillTransitionToSize:` holds the new size back
from the engine for half the turn (`shouldIgnoreViewportMetricsUpdatesDuringRotation`, issue
16322). So a Flutter page stretches its last frame for the first half, then shows frames of the
new size.

**Rotation in UIKit (iOS 26+, device only).** A rotation is a live resize of the window scene.
`_computeMetricsAndCrossFadeInLiveResize:withTransitionContext:` takes a render-server picture of
the whole screen, status bar included, and adds it to the top visible scene-sized window that has a
root view controller. That window is found with
`_enumerateWindowsIncludingInternalWindows:onlyVisibleWindows:…`, so it can be one of UIKit's own
windows, such as the text effects window, which `UIWindowScene.windows` does not list. The picture
is kept in that window's `_lowestLiveResizeSnapshot`. UIKit then lays everything out at the new
size, and the sheet's `viewWillTransition` runs inside that layout pass. Finally it fades the
picture over 0.1 s. On the simulator the render-server ids are missing and no picture is taken.

**Why the recording shows a seam.** The crisp region holds the old page, the old sheet and the old
status bar. It lasts as long as UIKit's fade, about 6 to 8 frames, and turns about a different
centre from the app content. That makes it UIKit's screen picture, in a window of its own. Attempts
1 and 4 looked only in `UIWindowScene.windows`, and attempt 4 also relied on a guessed field name,
`_liveResizeSnapshot` on the scene, which has no exported symbol. So the picture was most likely
never found.

**Why a normal sheet looks fine.** With a native sheet, the engine stays with the page and nothing
is drawn as the turn starts. The page layer keeps the frame the picture shows, only stretched, so
the picture's edge lines up with what is under it and its 0.1 s fade goes unnoticed. With this
sheet, the turn starts with a lot of work:

- The sheet is pictured with `drawHierarchy`. For a Flutter view that is an engine screenshot from
  the raster thread.
- The engine is lent to the page.
- Dart draws the page at its new size. FlutterMetalLayer shows that frame at once, squeezed into
  bounds that are still nearly the old shape.

So the frame beside the picture's edge is a different frame, and the edge reads as a cut until the
fade has run. The main-thread work at that moment also delays the fade.

## Attempt 5: hide the picture where UIKit actually keeps it

**Status: FAILED. Confirmed on the phone: the cut is unchanged.**

- Read `UIWindow._lowestLiveResizeSnapshot`. That field name is confirmed by the exported symbol
  `_OBJC_IVAR_$_UIWindow._lowestLiveResizeSnapshot`.
- Read it on every window of the scene, UIKit's own included:
  `-[UIWindowScene _allWindowsIncludingInternalWindows:onlyVisibleWindows:]` with `YES, NO`.
- Hide the picture both right after `_computeMetricsAndCrossFadeInLiveResize:…` returns and in the
  top sheet's `viewWillTransition`. Both run in the transaction that added the picture.
- The scene field guess and the "new subviews" fallback from attempt 4 are dropped.

**What its failure shows.** Five attempts at UIKit's live-resize picture have failed. The last one
read a field whose name is confirmed, in every window including UIKit's own, at both points where
the picture must already exist. So the crisp old-size region on the phone is not something this
app can reach as UIKit's in-app live-resize picture. Either it is drawn outside the app, or it is
not that picture at all. Hiding pictures is therefore abandoned as a direction. The next attempt
works on what the app's own layers show during the turn.

## Attempt 6: show no new-size frame while the old-screen picture is up

**Status: FAILED. Confirmed on the phone: the cut is still there.** Keeping old frames until half
way did not remove it, so the cut is not caused by which frame the layers show early in the turn.
Patching the timing of the engine hand-over between view controllers is abandoned. The design
itself (one engine moved between several `FlutterViewController`s, with pictures standing in for
the views it has left) is what is being replaced.

The recording shows what lies under the picture's edge. At the start of portrait to landscape
(frame 76), the page below 402 pt shows its *new* landscape layout, squeezed into the
still-portrait bounds: the tall, narrow AAPL row. At the start of landscape to portrait (frames
193 to 197), the sheet below the line shows its *new* portrait layout, stretched: the large
"Losers" chip. Above the line, both are their old frames, unscaled. The committed code
(`ac8b4fc`) made that happen on purpose as the turn starts:

- `freeze` pictured the sheet with `drawHierarchy`.
- `redrawPageAsTurnStarts` lent the engine to the page, released Flutter's half-turn metrics hold
  (`releaseMetricsHold`), and had Dart draw the page at its new size.
- The sheet got the engine back and its picture went as soon as a new-size frame reached it.

Flutter on its own, and a native sheet over a Flutter page, show no new-size frame until half way
through the turn. Their layers keep the frame the picture shows, so its edge lines up and nothing
is seen.

The change restores the half-way scheme kept in `stash@{0}`, without that stash's snapshot hooks
(`LiveResizeSnapshotHider` and `hideLiveResizeSnapshots`, the same idea as attempt 2):

- Nothing is drawn or pictured as the turn starts. The page and the sheet keep their old frames,
  stretched, as Flutter does.
- Half way through the turn (`transitionDuration / 2`, Flutter's own moment), the page and the top
  sheet are covered by what they show: their surfaces (`layer.contents`) plus `snapshotView`s of
  their native subviews. Each cover copies UIKit's animation of the layer it covers.
- The engine is lent to the page and back. Dart draws both at their new sizes, and both covers go
  together.
- During the turn, `setHeight` lays the sheet out at once and the covers follow it.

All of attempt 5's `LiveResizeSnapshots` code is removed.

## Against Flutter's official docs

- **Native views inside Flutter** ("Host native iOS views in your Flutter app with platform views"):
  the package follows it. Dart uses `UiKitView`. Swift implements `FlutterPlatformViewFactory` and
  `FlutterPlatformView`, and the plugin registers all 14 factories in `register(with:)`.
- **Flutter inside native screens** ("Multiple Flutter screens or views", and `FlutterEngine.h`:
  "A FlutterEngine can only have one `FlutterViewController` at a time"): the widget sheet broke
  this. It kept several `FlutterViewController`s on one engine on screen at once and moved
  `engine.viewController` between them. It also called Flutter's private `surfaceUpdated:` and
  `setShouldIgnoreViewportMetricsUpdatesDuringRotation:`, and drove `viewWillAppear` and
  `viewDidAppear` by hand. Flutter's supported route for several visible Flutter screens is one
  engine per screen (`FlutterEngineGroup`). iOS multi-view, one engine drawing several views, is
  not implemented (flutter/flutter#176993).
- `NativeNavigationHost` also places native bars around Flutter's view outside the platform view
  API. That is unchanged here.

## Attempt 7: rewrite the sheet as a Flutter route in the app's own view

**Status: FAILED. Confirmed on the phone: the cut is still there during a rotation.** The rewrite
also introduced a new fault. In landscape, on the Activity filter sheet, the iOS 26 tab bar's Liquid
Glass capsule (Portfolio, Markets, Watchlist, Activity, Orders) is drawn over the sheet, across its
apply button. The tab bar is a native UIKit view and sits above everything Flutter draws, and it
did not step aside for this route. So drawing the sheet in Flutter neither removes the cut nor keeps
the native bars behind the sheet. Like the drawer, a Flutter-drawn sheet would also need the native
bars cut open or hidden where it lies (`NativeDrawerCover`).

**State left in the working tree (uncommitted):** the rewrite. `adaptive_native_sheet.dart` is
rewritten, `NativeWidgetSheet.swift` is deleted, and the plugin and `AdaptiveToolbarHost` are
updated. The last commit (`5d67af1`) still has the UIKit sheet design.

**Still open for a future attempt.** The cut survived seven attempts:
- hiding UIKit's live-resize picture four ways;
- holding new frames until half way;
- moving the sheet into the app's own Flutter view.

So its source is still unidentified.

Following the user's choice, `AdaptiveNativeSheet` no longer uses UIKit sheets:

- On iOS each sheet is a modal route on the nearest navigator, drawn in the app's single Flutter
  view. It uses the same pieces as `AdaptiveBottomSheet`, the sheet that already rotates fine on
  the phone:
  - the iOS 26 floating panel: 8 pt inset, 36 pt corners, grabber;
  - `SheetSurface` for native views behind it;
  - nested sheets darken their own fill.
- Detents: fit (content height, capped below the native navigation bar, scrolls when taller),
  short, full, and half that drags to full. `isDismissible: false` gives no grabber, no drag and
  no tap-outside. Full screen is a full-screen dialog page that the back gesture cannot close.
- The page's native bars react through the package's existing covered logic: the tab bar steps
  aside, the navigation bar dims and ignores touches.
- The engine never leaves the page's view, so nothing is handed over or pictured, and a rotation
  redraws the sheet like any page.
- `NativeWidgetSheet.swift` is deleted along with its `adaptive_platform_ui/widget_sheet` channel.
  `AdaptiveNativeSheet.drawn`, `isShowingNow` and `AdaptiveNativeSheetLayer` are removed, and the
  Duo strip always draws.

## Attempt 8: `UIRequiresFullScreen` (discrete scene resizing)

**Status: FAILED. Confirmed on the phone: the cut is unchanged.**

Apple's TN3192 (revised 2026-08-13) and WWDC26 session 278 say that from iOS 27, an app
built with the iOS 27 SDK that sets `UIRequiresFullScreen` to `YES` is resized
*discretely* instead of live, the mode meant for apps that render into one surface. The
idea: if an iPhone rotation is a live resize of the window scene, this would take it off
that path and no old-screen picture would be taken. The key was added to
`ios/Runner/Info.plist`, built with Xcode 27.1 (iPhoneOS 27.1 SDK; the built bundle carried
`UIRequiresFullScreen = true`) and installed as a Release build on the iPhone 18 Pro,
iOS 27.0.1. No Swift or Dart changed.

**What its failure shows.** Either an iPhone rotation on the device is not governed by the
scene's user resizability (the key may only matter where a person drags the window: iPad,
iPhone Mirroring), or the picture is not the live-resize one. The key is removed again:
on iPadOS 26 it still means full-screen compatibility mode, and on iPadOS 27 and the
iPhone Duo it would make split-view resizes discrete.

## Attempt 9: pin the covers at their own size while the picture is up

**Status: FAILED. Confirmed on the phone: the cut looks the same.**

Geometry of the picture, from the recording (`GJMZ8480.MP4`): in both directions it is the
top-left 402 by 402 square of the window's *new* coordinate space, it shows the old screen
at its natural size from the window's origin, and it turns with the window like everything
else. So it is a layer the size of the new window at the window's origin, holding the old
screen's pixels unscaled. Under it, the committed code showed the page's and the sheet's
new-size frames squeezed into bounds that were still nearly the old shape (frames 87 and
170 of the recording), and a plain Flutter view would show its old frame stretched. Neither
matches the picture, so its bottom edge reads as a cut.

The change: as the turn starts the page and the top sheet are each covered by the frame
their layer shows (`layer.contents`, no `drawHierarchy`), with `contentMode = .topLeft`, so
the old frame stays at its own size from the view's top-left corner instead of stretching
with the view. Under the picture that is pixel for pixel what the picture shows. The engine
hand-over proceeds under the covers as before (page drawn at its new size, then the sheet),
and both covers go together once both are drawn and the picture has had time to fade
(0.2 s after the first display refresh of the turn: UIKit's 0.1 s fade plus the frames
before it starts). The strip of a view beyond its old frame, which grows as the bounds
animate, shows the view's own layer underneath.

**What its failure shows.** If the covers were in place from the first frame, the page under
the picture showed the old frame unscaled from the window's origin, which is what the
picture was taken to be, and the picture's edge should have vanished over the page. It did
not. So either the picture is not an unscaled old-screen layer at the window's origin, or
the covers were not what was on screen under it. The next step is to read the phone's own
UIKitCore (iOS 27.0.1, from Xcode's device support symbols) rather than the simulator's,
to find where the picture is made and inserted on the device.

## Attempt 10: fill the scene's picture slot

**Status: FAILED. Confirmed on the phone: the cut is unchanged.**

From the phone's own UIKitCore (iOS 27.0.1, Xcode's device support symbols, full symbol
table), not the simulator's:

- `-[UIWindowScene _computeMetricsAndCrossFadeInLiveResize:withTransitionContext:]` takes
  the picture only when `_effectiveUISettings.inLiveResize` is set, when
  `_UISceneLiveResizeSnapshotsEnabled()` is true (the `live_scene_resize` feature flag and,
  read on every call, `snapshottingEnabled` on `[_UISceneLiveResizePrototypeSettingsDomain
  rootSettings]`), **and when the scene's `_liveResizeSnapshot` ivar (offset 408 on this
  build) is nil**. It then calls `_makeUISceneViewForLiveResize` on the top scene-sized
  window with a root view controller (`+[UIWindow _topVisibleWindowPassingTest:]`, all
  windows, internal ones included) and `-[UIWindow _insertLiveResizeSnapshot:]` as a direct
  call, which `addSubview:`s the picture to that window and keeps it in
  `UIWindow._lowestLiveResizeSnapshot` (offset 720).
- `-[UIWindowScene _scheduleResizeFinishedActionAndFadeOutSnapshot]` runs right after the
  metrics are computed: it empties the scene's slot, then animates the picture's `alpha` to
  0 over `LiveResizeCrossFadeDuration` and, on completion, calls
  `[[picture window] _removeLiveResizeSnapshot:picture]`, which returns at once for a nil
  window.

The change (`LiveResizePicture` in `NativeWidgetSheet.swift`): while a sheet is up the
scene's `_liveResizeSnapshot` slot holds an empty hidden view that is in no window, so UIKit
takes no picture; the slot is filled again after each turn (UIKit empties it at the fade),
and the prototype setting `snapshottingEnabled` is turned off as well. Both are undone when
the last sheet closes. The hand-over code is back to `ac8b4fc` (attempt 9's covers removed).
`UIRequiresFullScreen` is not in the plist.

**What its failure shows.** With the scene's `_liveResizeSnapshot` slot filled and
`snapshottingEnabled` off, `_computeMetricsAndCrossFadeInLiveResize:withTransitionContext:`
cannot take the picture, yet the cut is the same. So either that method is not where the
device's picture comes from (a rotation on the phone may not run through the live-resize
path at all, and the picture is made elsewhere), or the slot and setting were not what UIKit
read at the time. Ten attempts have now been made against this picture: hiding it five ways,
holding old frames, moving the sheet into Flutter, discrete resizing, pinned covers, and
filling UIKit's own slot. None changed what the phone shows. The code is reverted to
`ac8b4fc`; only these notes remain.

## Attempt 11: independent Flutter engine for each UIKit sheet

**Status: FAILED.** After installing the signed Release build on the iPhone 18 Pro
on 2026-10-25, the user reported: "still not working." The sheet-cut problem
remains unresolved. No simulator run or test
suite was used. The first install connection reset; reconnecting and retrying
installed `com.peterleung.meridian` successfully. The app was not launched by the
agent and no physical-device UI or logs were collected.

Read all ten prior attempts before making this change. The new recording,
`NYAQ7106.MP4` (1206 × 2622, 218 frames), shows the same split across the entire
composed screen. At approximately 2.458 s, the old landscape sheet and native
navigation bar stay crisp above the boundary while the new portrait content
stretches underneath. The old composition fades across both the page and sheet.
That observation does not identify the producer of the old image and does not
justify another attempt at suppressing UIKit's private snapshots.

The change removes the app's engine handoff architecture instead:

- Each sheet gets an engine from `FlutterEngineGroup` and keeps its own
  `FlutterViewController`, platform views, metrics and rendering surface.
- The original page engine never detaches. Covered sheets keep rendering too.
- All page/sheet freezing, surface copying, frame watchers, manual lifecycle
  calls, `drawLayer`, and private rotation metric manipulation are removed.
- Named routes and codec-safe inputs/results bridge the engines' separate
  isolates. Existing content widgets, controls, filters and nested flows remain.
- Sheet engines register the native controls without replacing the main
  engine's global navigation or drawer channels.
- UIKit still owns the real sheet, grabber, dimming, detents and drag dismissal.

**What its failure shows.** Replacing the shared-engine handoff with separate
engines, removing the app's snapshot covers and private rotation calls, and
keeping each visible view attached to its own engine did not solve the reported
phone defect. Independent engines alone are not a proven fix. The failure does
not identify the cause or establish that the cut is unavoidable. No new recording
or runtime evidence was collected after this report, so differences in timing,
severity, stretching or background appearance are not established.

**State left in the working tree:** the independent-engine implementation remains
in place; it was not reverted. The user explicitly requested documenting this
failure and no retry. Only documentation was updated after that instruction;
no further build, install, simulator run, test or device inspection was performed.

## Attempt 12: use system CAMetalLayer instead of FlutterMetalLayer

**Status: FAILED.** The signed Release build compiled and installed on the iPhone
18 Pro on 2026-10-26. The user subsequently reported: "still not working."
The sheet-cut problem remains unresolved. The packaged Info.plist was
read before installation and contains Boolean `FLTUseFlutterMetalLayer=false`.
`devicectl` reported successful installation of `com.peterleung.meridian`.
The agent did not launch the app, run simulators or tests, or collect device
screenshots or logs. Build and install success do not establish a rotation fix.

All eleven previous attempts were read first. This changes the engine's surface
presentation backend, not sheet geometry, snapshots, rotation timing or engine
ownership. The independent engines from attempt 11 remain in place.

### Evidence for a distinct path

The installed Flutter 3.47.8 SDK uses engine revision
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. Its source and the bundled Release
framework both contain `FLTUseFlutterMetalLayer`:

- `FlutterMetalLayer.mm`, `+enabled`, reads the main bundle's Info.plist once.
  Missing key defaults to true; an explicit Boolean false disables that layer.
- `rendering_api_selection.mm`, `GetCoreAnimationLayerClassForRenderingAPI`,
  selects Apple's `CAMetalLayer` when that setting is false.
- `FlutterOverlayView.mm`, `+layerClass`, uses `FlutterView.layerClass` too, so
  Flutter drawing around native platform controls takes the same path.
- The custom `FlutterMetalLayer` presents by assigning an IOSurface to
  `CALayer.contents`; the system layer uses Metal drawables. Impeller remains
  enabled, and this is not software rendering or a switch to Skia.
- The app/package's current iOS code has no remaining `layer.contents` access
  dependent on the old IOSurface representation. The drawer uses masks instead.

The Flutter maintainer also recommends this option for investigating other
device presentation problems in
[flutter/flutter#175790](https://github.com/flutter/flutter/issues/175790).
That issue is not proof that it fixes this rotation defect.

### Change and limits

`ios/Runner/Info.plist` now sets `FLTUseFlutterMetalLayer` to Boolean false.
The setting applies from process startup to the page engine, all sheet engines
and their Flutter overlays. UIKit sheets, native controls, filter state, detents,
safe areas, window topology and normal rotation lifecycle are unchanged in code.
No snapshot hooks, forced viewport timing, frozen background, stretch cover or
replacement controls are introduced.

The hypothesis was that bypassing the custom surface-presentation path might
remove the cut that persisted across engine ownership changes.

**What its failure shows.** Installing the build configured with
`FLTUseFlutterMetalLayer=false`, while retaining the independent sheet engines,
did not solve the reported phone defect. This configuration change is not a
proven fix and must not be repeated as an untried approach. The packaged setting
and source selection logic were checked; the active layer classes were not
inspected on the phone. This result does not identify the root cause or establish
that the cut is unavoidable. No new recording or runtime evidence was collected
after the report, so changes in timing, severity, stretching or background
appearance are not established.

**State left in the working tree:** `FLTUseFlutterMetalLayer=false` remains in
`ios/Runner/Info.plist`, and the independent-engine implementation remains in
place. Neither was reverted. The user explicitly requested documentation only
and no retry. Only documentation was changed after that instruction; no further
build, install, simulator run, test or device inspection was performed.

## Attempt 13: defer fit-height changes during native transitions

**Status: FAILED.** The signed Release build compiled and installed on the
iPhone 18 Pro on 2026-10-26. The user subsequently reported: "still no" and
requested documentation only, with no further attempts. The sheet-cut problem
remains unresolved. The agent did not launch the app, run a simulator or tests,
or collect device UI or logs. Compilation and installation did not establish
the visual result.

The fit sheet previously replaced its selected custom detent immediately when
Flutter reported a new measured content height, even while a rotation
coordinator was active. That could introduce a second sheet geometry change
during the rotation. The native-only filter sheet has fixed detents and does not
perform that same mid-transition replacement; this difference alone does not
prove it causes the recorded cut across the composed screen.

The sheet now keeps its committed height through presentation and active
transitions, coalesces new measurements, and applies the latest height after
the transition completion, outside its animation transaction. It checks the page
and sheet coordinators and retains normal UIKit and Flutter lifecycle handling.
On cancellation or closure, pending changes are handled against the remaining
live sheets. Existing per-level detent replacement is retained: the earlier
implementation documented that `invalidateDetents()` could also resize a
covered sheet. No frozen images, fake controls, forced viewport timing, or
changes to the page's rendering are introduced.

Research in the internal browser included Apple's
[transition coordinator documentation](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/animate(alongsidetransition:completion:)),
which says its completion runs after a transition and may still run even if
animation registration returns false, and
[custom detent invalidation documentation](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/invalidatedetents()).
The latter is a supported API, but was not substituted here because of the
previously documented lower-sheet regression. Flutter's earlier
[rotation issue](https://github.com/flutter/flutter/issues/16322) was also
reviewed; its delayed viewport-size change is already present in the installed
engine and is not repeated as a new fix.

**What its failure shows.** Deferring measured fit-height changes until after
native transitions, while retaining attempt 11's separate sheet engines and
attempt 12's `CAMetalLayer` setting, did not solve the reported phone defect.
The result does not identify the cause or establish that the cut is unavoidable.
No new recording or runtime evidence was collected after the report, so changes
in timing, severity, stretching or background appearance are not established.

**State left in the working tree:** the attempt 13 code remains in place, along
with the settings and architecture from attempts 11 and 12; none were reverted.
After the user's request to stop, only this documentation was updated. No
further retry, build, installation, simulator run, test or device inspection was
performed.

## Attempt 14: UIKit sheet container in the page's window

**Status: FAILED; reported worse.** The signed Release build compiled and
installed on the iPhone 18 Pro on 2026-10-27. The user subsequently reported
"way worse" and requested documentation only, with no further attempts today.
The agent did not launch it, run a simulator or tests, or collect device UI or
logs. After attempt 13 failed, the user requested another attempt. The documented
observation that the native-content filter sheet rotates without the cut
motivated this change in presentation hierarchy; it did not establish the cause
of the artifact or guarantee a fix.

The first widget sheet is presented from the page's existing window, like the
native filter sheet. UIKit presents a plain container view controller as the
real sheet, with a dedicated-engine Flutter view controller contained as its
child. Flutter still renders the actual supplied widgets; UIKit owns the sheet,
detents, gestures, and dismissal. Nested sheets retain separate presentation
windows to avoid the previously documented shrinking of a covered sheet.
The independent engines and deferred fit-height handling remain in place.

The first sheet was previously presented in the page window when the app lent
one engine among controllers, and attempt 7 put a Flutter-drawn route in the
page itself; both failed. This combination of original-window presentation,
UIKit container, and independent sheet engines has not been reported as tried.
No screenshot overlays, fake controls, or private rotation hooks were added.

**What its failure shows.** The original-window presentation, UIKit container,
and independent sheet engines did not resolve the problem; the user reported the
result was worse. The report did not specify which visual details worsened, and
no new recording or runtime evidence was collected to establish the mechanism,
timing, stretching, or background behavior. Compilation and installation did
not establish visual success.

**State left in the working tree:** after the user requested a revert, attempt
14's UIKit container and original-window presentation were removed. The code
was restored to the attempt 13 state; earlier attempt changes remain. A signed
Release build of that restored state was installed on the iPhone on 2026-10-27.
This was a rollback, not another fix attempt. No simulator run, test, or device
inspection was performed.

## Attempt 15 (2026-10-27): Flutter-drawn sheet below the native bars — NOT A FIX

Commit `3cc3a20`, the code in the project, described under "Current state" above. The user found
it better on the phone than attempts 1–14, but "still not good enough". Attempts 16 and 17 were
built on it.

## Attempt 16 (2026-10-27): the sheet follows the bar only at the size it is drawn at — FAILED

**Status: FAILED.** The signed Release build was installed on the iPhone 18 Pro (iOS 27.2) on
2026-10-27. The user recorded `HVYU3067.MP4` and reported: "still has a slight cut off in the
middle, and the background content seems not behaving correctly when turning". The code is
reverted.

The user's request: attempt 15 is better but not good enough; use Flutter's original sheet, which
renders best when the screen turns, or find a better way.

Checked before the change:

- `CupertinoSheetRoute` / `showCupertinoSheet` in Flutter 3.47.8
  (`packages/flutter/lib/src/cupertino/sheet.dart`). It is always nearly full height (`topGap`
  is a fixed ratio of the screen height, 0.08 by default) and scales the page behind it down. It
  has no fit-to-content detent, so the filter sheets would lose their designed height, and the
  native navigation bar, a UIKit view above Flutter, cannot scale down with the page. Not used.
- github.com/szymdzie/iphone_duo_ui_pro, for a fix. It uses Flutter's stock
  `showModalBottomSheet(useSafeArea: true)` and `showCupertinoModalPopup`, has no native controls
  inside its sheets and no rotation handling, and has only been tried on simulators, where the
  cut never shows. Nothing for this problem.

What was found: as a turn starts, UIKit lays the bars out for the new size and
`NativeNavigationHost.layout()` sends the bar's bottom edge (`onNavigationMetrics`) straight away,
while Flutter may still be drawing the old size. `_FloatingSheet` caps its height with that
value, so the sheet could be laid out again mid-turn against the wrong bar, and once more when
Flutter drew the new size.

The change:

- Every `onNavigationMetrics` message carried the size of the Flutter view the bar was measured
  at (`NativeNavigationPage.nativeNavigationLayout(contentInset:barBottom:viewSize:)`).
- Dart filed the readings under that size (`NavigationBarBottoms` in `native_toolbar.dart`: one
  set for the window, one per `AdaptiveNavigationScrollController`).
- `_FloatingSheet` read the reading for the size it was drawn at (`MediaQueryData.fromView`) and
  was rebuilt only when that value changed.
- On the window's root, `NativeNavigationController.viewWillTransition(to:with:)` registered an
  `animate(alongsideTransition:)` block that laid the window out and sent the bar's bottom for the
  new size (`onNavigationBarBottom`) while a sheet covered the page.

What the recording shows (`HVYU3067.MP4`: 1206 × 2622, 60 fps, 242 frames; Activity filter sheet
up, portrait to landscape at about 1.47 s, back to portrait at about 3.0 s):

- Portrait to landscape starts at about frame 88. From frame 89 a crisp picture of the old screen
  lies over the live content and fades out over about 11 frames (0.18 s, gone by frame 100).
- Frames 89 to 92, under that picture, show a Flutter frame laid out like neither orientation: the
  page has moved up into the navigation bar, and the first row's title, "Dividend · VOO", wraps
  onto two lines.
- From frame 93 the live content is the landscape layout. The picture's straight edge crosses
  the new sheet, and the old page rows show through it over the white sheet.
- Landscape to portrait: the straight line at 402 pt is already in frame 180, before the turn
  can be seen. The content above and below it is offset by a few pixels, and the offset grows
  each frame. Frames 183 to 186 show a second, displaced copy of the sheet's chips. From about
  frame 186 the portrait layout lies under a fading picture of the old landscape sheet, gone by
  about frame 194.
- The earlier notes measured the crisp phase at 6 to 8 frames. Here the picture is visible for
  11 to 14 frames.
- The landscape layout appears about 5 frames into a turn that takes about 13 frames. That
  suggests Flutter's half-way metrics hold did not apply to this turn; not verified.
- No vertical-bar strip appears in any frame, so the iPhone Duo pose
  (`DuoLayout.resolvePose`) did not switch mid-turn.

**What its failure shows.** Keeping the sheet's own layout steady through a turn did not remove
the cut. The page behind the sheet still changed mid-turn, and the old-screen picture was still
drawn over everything for 11 to 14 frames.

## Attempt 17 (2026-10-27): every bar metric and the safe area at the size Flutter draws — FAILED

**Status: FAILED.** The signed Release build was installed on the iPhone 18 Pro (iOS 27.2) on
2026-10-27; the agent did not launch it. The user then judged attempts 16 and 17 failed ("I would
consider all these are failed attempt") and asked for the code to be reverted. No recording of
this build was provided.

Built on attempt 16. It aimed at the page's mid-turn layout. The page body's top inset is
`contentTopInset - padding.top` (`native_scaffold.dart`), and UIKit's `contentTopInset` for the
new size could reach Dart while Flutter still laid out the old size. That fits the page moving
up into the bar in frames 89 to 92.

The change:

- `_NativeToolbarState` became a `WidgetsBindingObserver`. It held an `onNavigationMetrics`
  reading measured for a size Flutter was not drawing yet and applied it in `didChangeMetrics`,
  in the same frame as the new size. Readings for the size Flutter was drawing at applied as
  before.
- `NativeNavigationHost.settleForSizeTransition()` replaced attempt 16's bar report and ran from
  the root's `animate(alongsideTransition:)` block for every page, not only while covered. It
  laid the window out, called `synchronizeFlutterSafeArea(window)`, then sent the page's metrics
  for the new size, with the resting inset cached for that geometry (`geometryKey`, the key
  `layout()` uses). With no cached inset it sent only the bar's bottom, and only while a sheet
  covered the page.

**What its failure shows.** Nothing was measured: there is no recording of this build. It does
not show whether the in-between Flutter frames went away. The old-screen picture was not touched
by either attempt, and no attempt so far has been able to remove it.

**State left in the working tree:** the code of attempts 16 and 17 is reverted to commit
`3cc3a20` (attempt 15). Only this documentation changed. A signed Release build of the reverted
state was installed on the iPhone on 2026-10-27, without launching it. This was a rollback, not
another fix attempt.
