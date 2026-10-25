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
