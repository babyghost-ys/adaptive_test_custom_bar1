# Sheet rotation cut on a real phone: failed attempts

**Status: FAILED.** None of the attempts below removed the cut. Each was installed as a Release
build on an iPhone 18 Pro running iOS 27.0.1, and the user confirmed on the phone that the cut is
still there.

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
