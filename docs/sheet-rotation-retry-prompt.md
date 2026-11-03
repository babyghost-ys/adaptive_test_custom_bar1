# Prompt: fix the rotation cut for a short native sheet on iPhone (iOS 26+)

Paste everything below this line into the new session. It assumes the
session runs in this repository (`native_widgets_on_duo`) with the same
tools (XcodeBuildMCP, a connected iPhone 18 Pro). Edit the "Rules" section
if you want to allow the new AI to do things the previous sessions were not
allowed to do (instrumentation, simulator runs, recordings of its own).

---

You are taking over a rendering bug that 22 recorded attempts over ten days
have not fixed. Read this whole prompt before touching anything, then read
the three documents it names. Do not repeat an attempt the record marks as
failed. Your first deliverable is evidence, not a fix.

## Rules (from the project owner; they override your defaults)

- British English. No emojis anywhere. Never end a reply with a question or
  an offer; state what you did and stop.
- Trust the reported bug; the owner's eyes on the phone are the test. Do
  not reproduce it on the simulator (the simulator never shows it) and do
  not add probe apps, logging builds or temporary instrumentation unless
  the owner agrees to it first for a named measurement. Ask once, in plain
  terms, before adding any.
- Build with XcodeBuildMCP only: `session_set_defaults` (workspace
  `ios/Runner.xcworkspace`, scheme `Runner`, the connected iPhone's id,
  configuration `Release`), `build_device`, `get_device_app_path`,
  `install_app_device`, then set the configuration back to `Debug`. Install
  on the phone after every code change, do not launch it, do not screenshot
  it. Never run `xcodebuild` or `xcrun` yourself.
- No hiding, no snapshots, no cover views, no placeholder fills, no fake
  controls, no timers that guess at UIKit's timing. The owner rejected every
  one of these. Fix what is actually drawn.
- Keep the UIKit sheet (`UISheetPresentationController`, one Flutter engine
  per sheet) and keep a short sheet short in landscape. Making every sheet
  full height in landscape (attempt 20) removes the cut but was rejected
  because it covers the navigation bar; it is the fallback, not the answer.
- Commit only when asked, never push, no AI attribution in commits.
- Record what you tried, and the owner's verdict, in
  `docs/sheet-rotation-cut-attempts-19-20.md` (append; the file name is
  kept), one section per attempt, numbered from 23. Say "installed, not
  judged" until the owner reports.

## Read first

1. `docs/sheet-rotation-cut-failed-attempts.md`: attempts 1 to 18, the
   mechanism of iOS's old-screen picture, UIKitCore findings, everything
   ruled out before 2026-11-02 (snapshot hiding four ways, UIRequiresFullScreen,
   separate engines, CAMetalLayer, Flutter-drawn sheets, hiding the sheet
   before the turn).
2. `docs/sheet-rotation-cut-attempts-19-20.md`: attempts 19 to 22 and the
   six isolation builds of 2026-11-02, with their verdicts. This is the
   current state.
3. `docs/native-widget-sheet-porting-guide.md`: how the sheet is built
   (sections "What you are building", "Step 1", "Step 8"), with the full
   source of the sheet manager and the rotation code.

## Environment

- Flutter `main` channel, 3.50.0-1.0.pre-343, engine `eede6c7e` (2026-11-02).
  `ChangeNotifier` and friends live in the `listen` package; run
  `flutter pub get` inside `packages/adaptive_platform_ui` as well as in
  the app, or the analyser reports hundreds of false errors.
- Xcode 27.1, iOS 27.1 SDK. Phone: iPhone 18 Pro, iOS 27.2, 402 x 874 pt.
  The simulator (iPhone 17 Pro, iOS 27.0) never shows the bug.
- App: `lib/` (Meridian demo). Package: `packages/adaptive_platform_ui`
  (local fork, SwiftPM plugin at
  `packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui`).
- The native host: the app window's root is a `UITabBarController`; each
  tab a `NativeNavigationController` (real `UINavigationBar`, red opaque
  appearance); its content a `NativeNavigationContent` whose view is a
  `UIScrollView` holding the page's `FlutterViewController` view full-bleed
  (`Navigation/NativeNavigationContent.swift`). Bar metrics reach Dart via
  `onNavigationMetrics` from `Navigation/iOS26ToolbarPlatformView.swift`.
- The sheet: `Overlays/NativeWidgetSheet.swift`. Each sheet is a
  `.pageSheet` presented from the root of its own transparent `SheetWindow`
  one level above the page's window, with its own `FlutterEngine` from a
  `FlutterEngineGroup` (entrypoint `nativeSheetMain`). Detent `fit` is a
  custom detent returning the content's measured height, with
  `prefersEdgeAttachedInCompactHeight = true`, so in landscape a short
  sheet is short and edge-attached; a tall one is full height.
- Rotation code in place (all public API): `Navigation/TurnHold.swift`
  pauses a layer's clock (`speed = 0`, `timeOffset` = now) before UIKit
  adds a turn's animations and runs it past their end at
  `transitionDuration / 2 + 1/30 s` (when Flutter draws the new size).
  `NativeNavigationHost.pageTurnHold` holds the page window's root view
  from `NativeNavigationController.viewWillTransition`; each sheet `Level`
  holds its presented view from `SheetWindow`'s frame setter and from
  `viewWillTransition`. The page's Flutter view has `contentMode = .topLeft`
  and the page background; Flutter overlay views are pinned
  (`FlutterTurnPinning`). Dart holds a bar reading measured for a size it
  is not drawing yet (`_NativeToolbarState.didChangeMetrics`). The bar's
  safe-area strip is a persistent view with an animated frame.

## The bug, exactly

On the phone only. iOS 26 and later treats a rotation as a scene live
resize: the render server takes a picture of the old screen as the turn
begins, lays it over the new layout unscaled at the window's origin,
clipped to the new window's size (so the top-left 402 x 402 pt square),
and fades it out over the first 0.1 to 0.2 s (11 to 14 frames measured).
Wherever the live content under it is the same pixels, the fade is
invisible; wherever it differs, the picture's edge shows as a straight
"cut". Attempts 1 to 10 proved the picture cannot be removed, hidden or
filled from inside the process.

Since attempt 19 the turn is clean when the open sheet reaches the top of
the screen in landscape (Markets, Orders, Activity filter sheets; the owner:
"fixed perfectly"). It still cuts when the open sheet is shorter than the
screen in landscape, so that the page's top (status bar area, navigation
bar, some dimmed page content) is visible above it. The owner's words:
"once the sheet is shorter and not reached to the nav bar when it's
landscape horizontal, the cut happens". Six isolation builds showed the
page content, the tab, the sheet's content, the dismissal configuration and
a native control on the page make no difference; only the sheet's height
in landscape does.

Test rig, committed in `e8c9bbc` and still in the tree: the Watchlist tab
(`lib/features/watchlist/view/watchlist_page.dart`) builds the Activity
page with a short sheet (`Activity(shortSheet: true)`, route
`activityShort` in `lib/app/native_sheet_app.dart`: one segmented control,
a slider, an apply button). Open that sheet on the Watchlist tab and rotate.
The Activity tab opens the tall version of the same sheet and is clean. The
real Watchlist page and sheet are to be restored from commit `49ea038`
before shipping (files listed in the attempts document).

## What has been shown not to be the cause

Each of these was changed in isolation on the test rig and the cut stayed:
the sheet's `isModalInPresentation` and dismissibility; the page's native
segmented control; which tab and which page content lie under the sheet;
pausing the sheet's layer from the window's frame setter instead of
`viewWillTransition`; pausing the whole page window's root view layer;
inserting the bar's safe-area strip during layout. Earlier: everything in
the attempts 1 to 18 document.

## What has never been measured

Every build since attempt 19 was judged by eye at normal speed. Nobody has
confirmed on the phone that:

- the layer holds take effect (the presented sheet view and the page root
  view keep their old frames for the first half of the turn), rather than
  UIKit laying the new size out discretely with no animation to pause;
- which pixels actually change in the top 100 pt of the screen during the
  first ten frames of a landscape-to-portrait turn with the short sheet
  open: the navigation bar's height, its title (compact and regular bar
  metrics use different title fonts and UIKit may swap views), its
  background, the status bar (drawn by the system, outside the app), the
  dimmed page content, or the sheet's top edge.

## Your task, in order

1. Ask the owner for one slow-motion recording (240 fps, the phone's Camera
   app pointed at the test phone, or a screen recording) of the Watchlist
   test rig: open the short sheet in landscape, rotate to portrait, pause,
   rotate back. Previous recordings were read with `ffmpeg` frame
   extraction and pixel-row scans (see
   `docs/sheet-rotation-cut-failed-attempts.md`, attempt 16, and the
   measurement notes in the first document). Read the frames yourself. Do
   not propose a fix until you can say, with frame numbers, what moves
   under the picture and what does not. If the owner cannot record, ask
   whether you may add a temporary `CADisplayLink` logger (Debug build,
   `NSLog`, removed afterwards) that samples the presentation-layer frames
   of the navigation bar, the safe-area strip, the sheet's presented view,
   the page root view and the Flutter view for one second from
   `viewWillTransition`; XcodeBuildMCP captures `NSLog` from the device.
2. From the evidence, pick the one remaining cause and fix it in the
   package, not with a cover. Candidates the record leaves open:
   - the holds are not in place before UIKit's first layout of the turn
     (if so, the only earlier hook for the page window is its frame setter,
     which needs the window to be a subclass; the app's window comes from
     `FlutterSceneDelegate`, so this means either creating the window in
     `SceneDelegate` or swapping its class at runtime);
   - UIKit changes the bar's content at the metrics change without
     animation (title font, glass views): then the bar region can only be
     kept still by keeping the bar's metrics unchanged across orientations,
     or by letting the sheet reach the bar's bottom in landscape (not full
     height: cap the landscape detent at the bar's bottom, so the bar stays
     visible and the page's top is still covered; untested, and a smaller
     design change than attempt 20);
   - the system status bar: nothing in the app can hold it; if it is what
     the owner sees, say so and show it on the frames.
3. One change per build. Install on the phone, do not launch, report what
   changed and what the recording should now show. Append the attempt to
   the attempts document before reporting.
4. If after the measurement no in-process fix is possible, say so plainly,
   restore the Watchlist page and sheet from `49ea038`, and offer the two
   fallbacks with their costs: attempt 20 (full height in landscape,
   covers the bar) and the capped landscape detent (sheet top at the bar's
   bottom).

## Facts that cost time to learn; do not relearn them

- `CALayer.contentsGravity = .topLeft` pins the visual bottom-left on iOS
  (constants named for macOS's flipped axis). Use `UIView.contentMode`.
- `FlutterMetalLayer` presents IOSurfaces as `layer.contents` and drops
  frames whose size is not the layer's `drawableSize`; the engine holds
  viewport metrics for `transitionDuration / 2` after
  `viewWillTransitionToSize` (private flag; do not touch it).
- Flutter's compositor creates overlay views with flexible autoresizing;
  `FlutterTurnPinning` clears it.
- `UIRequiresFullScreen` does not stop the picture on an iPhone (attempt 8,
  POC 11). The picture is not reachable through `UIWindowScene`'s
  live-resize snapshot slots (attempts 1 to 5, 10).
- Hiding the sheet before the turn (accelerometer, attempt 18) removes the
  sheet from the picture but not the page cut, and was rejected.
- A custom detent is honoured in compact height on iOS 27 when
  `prefersEdgeAttachedInCompactHeight` is true; a resolver may return
  `context.maximumDetentValue` for full height.
- XcodeBuildMCP: `screenshot` lags a frame, there is no rotation tool, and
  Dart `debugPrint` does not reach its device log; `NSLog` does.
