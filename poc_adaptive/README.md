# Adaptive Activity Sheet Rotation POC

This standalone app copies the original project's Activity page, data, filter sheet, adaptive UI package, theme, native toolbar and tab bar. Open the filter control beside Recent activity and rotate the phone with the sheet open. The other navigation controls are present for the layout comparison; Activity is the only page in this POC.

Run from this directory with `flutter run` on an iOS device or simulator.

## 2026-10-28 — build 2

The sheet's real UIKit segmented control now uses opaque images for its normal,
selected and pressed backgrounds and dividers. Its window host and positioning,
the Flutter Apply button, and the rest of the page are unchanged.

This isolates the control's default material appearance as a possible contributor
to the rotation cut. Apple documents the background-image API, and a developer
report describes custom backgrounds suppressing Liquid Glass selection; neither
establishes that Liquid Glass causes this app's cut. Phone behavior is unverified.

- [Apple background-image API](https://developer.apple.com/documentation/uikit/uisegmentedcontrol/setbackgroundimage(_:for:barmetrics:))
- [Developer observation about Liquid Glass selection](https://developer.apple.com/forums/thread/815718)

## 2026-10-28 — build 3

The window-hosted diagnostic control and its `WindowSegmentHost` are removed. The
sheet uses the package's `AdaptiveSegmentedControl` again, embedded as a Flutter
platform view, and the package's `iOS26SegmentedControlView` now draws the track,
selection and dividers with opaque images through `UISegmentedControl`'s public
appearance API. The control stays a real `UISegmentedControl`; it no longer carries
the Liquid Glass selection backdrop (`UISegmentedControlSelectedSegmentVibrancyEffect`
in UIKitCore) over the Flutter surface. Phone behaviour is unverified.

## 2026-10-28 — build 4

Build 3 failed on the phone: the cut was still there, and the opaque background
images collapsed the control to a 3 pt bar, because `UISegmentedControl` takes its
intrinsic height from its background image. The package's `iOS26SegmentedControlView`
is back to the original file from the main project. The sheet keeps the package's
`AdaptiveSegmentedControl` as a platform view; no window-hosted control.

Phone result (2026-10-28): the user reported the cut is still there with build 4. So
the package's `AdaptiveSegmentedControl` as a plain Flutter platform view, with its
default Liquid Glass appearance and a Flutter Apply button, reproduces the cut in this
sheet. Work stopped here at the user's request; no further attempt was made.

## Where this POC stands

| Build | Segmented control in the sheet | Cut |
| --- | --- | --- |
| Flutter chips (original sheet) | none | no |
| 1 | `UISegmentedControl` hosted in the window, glass | yes |
| 2 | window-hosted, opaque images | unverified |
| 3 | `AdaptiveSegmentedControl` platform view, opaque images (collapsed to 3 pt) | yes |
| 4 | `AdaptiveSegmentedControl` platform view, default glass | yes |

Not yet tested: whether a plain UIKit view of another kind in the same place cuts, or
only `UISegmentedControl`.

## Direct native control bridge

The segmented control bridge is rewritten around a standard `UISegmentedControl`
returned directly as the Flutter platform view. UIKit keeps its default Liquid
Glass appearance, gestures, accessibility and layout. The extra wrapper UIView,
Auto Layout constraints, custom resize-animation suppression, forced layout calls
and experimental window overlay are removed.

Flutter binds to the native view's own platform-view ID after creation, sends only
changed configuration, and keeps that native instance during layout changes.
Vertical scrolling belongs to the sheet; the control registers tap and horizontal
drag gestures. The sheet geometry and Flutter Apply button are unchanged.

This corrects bridge lifecycle/layout issues. Whether it resolves the physical
phone's rotation cut is not yet established.

## 2026-10-28 — build 5: the sheet rebuilt from the top as a real UIKit sheet

Every build that showed the cut drew the sheet in Flutter with a `UISegmentedControl`
somewhere over it. The one sheet design recorded as turning cleanly is a UIKit sheet
whose content is UIKit. Build 5 makes the Activity filter that sheet: `AdaptiveFilterSheet`
(`UISheetPresentationController`, `NativeFilterSheet.swift`), declared from Dart, drawn
entirely by UIKit. The Flutter engine never leaves the page, and nothing Flutter draws sits
in or over the sheet.

- `UISegmentedControl` for All / Bought / Dividends, Liquid Glass as UIKit draws it.
- Native chips (`UIButton` configurations) for the symbols.
- A disclosure row (new `AdaptiveFilterSection`) holding a compact `UIDatePicker`
  (new `AdaptiveFilterDate`), the period chips, and a `UISlider`.
- The sheet fits its content (`AdaptiveFilterDetents.fit` now resolves a custom detent
  natively) and follows the disclosure row through `invalidateDetents()`.
- The Material fallback draws the same controls.

Phone behaviour is unverified. The dormant engine-hosted widgets stay in
`activity_filter_sheet.dart` for `nativeSheetMain`.

Phone result (2026-10-28): the user reported the cut is still there with build 5, a
sheet with no Flutter in it. So neither the platform-view hosting nor Flutter content in
the sheet is the cause.

## 2026-10-28 — build 6: build 5 without the segmented control

Same UIKit sheet as build 5, with the kind control as native chips instead of a
`UISegmentedControl`. Nothing else changed. If the cut stays, the segmented control is
not the cause; if it goes, it is, even inside a UIKit sheet. Phone behaviour is
unverified.

Phone result (2026-10-28): the user reported build 6 still cuts, and that the cut shows
once the sheet is expanded (date, period, slider visible), when the sheet is tall enough
to cross the 402 pt line. So the `UISegmentedControl` is not the cause.

## 2026-10-28 — build 7: two comparisons in one install

- Filter icon: build 6's UIKit sheet with dimming off (`largestUndimmedDetentIdentifier`,
  new `dims: false` on `AdaptiveFilterSheet.show`). No `UIDimmingView` over the page.
- Search icon in the toolbar: the same filter drawn by Flutter (`AdaptiveNativeSheet`, a
  Flutter route), Flutter chips for the kind, Flutter chips, slider and date line below,
  opened expanded so it crosses the 402 pt line. No native control, no UIKit view in it.

Reading: if the filter sheet still cuts, dimming is cleared. If the search sheet stays clean
while tall, the only clean shape is sheet content that stretches with the Flutter page
during the first half of the turn. Phone behaviour is unverified.

Phone result (2026-10-29): the user reported build 7 still cuts, on both sheets. A tall
Flutter-drawn sheet with no UIKit view in it cuts too, and the undimmed UIKit sheet cuts.
So neither dimming nor UIKit views over the page are the cause; the only clean sheets so
far were short ones that did not cross the 402 pt line.

## 2026-10-29 — build 8

The UIKit filter sheet is back to its design: `UISegmentedControl` at the top, dimming on.
The search icon no longer opens the comparison sheet. No fix is in this build.

## 2026-10-29 — build 9: no stretch during the turn

`RotationViewController` (a `FlutterViewController` subclass set in the storyboard) sets the
Flutter view's layer, and its subviews' layers, to `contentsGravity = .topLeft` in
`viewWillTransition` and restores the previous gravity when the coordinator finishes. During
the turn the old frame stays unscaled at the top-left, the same pixels UIKit's old-screen
picture holds, instead of stretching to the animating bounds. The sheet is the UIKit filter
sheet of build 8. Phone behaviour is unverified.

Phone result (2026-10-29): build 9 "still really bad".

## 2026-10-29 — build 10: new size at frame one

Build 9's unscaled layer, plus `RotationViewController` clears the engine's
`shouldIgnoreViewportMetricsUpdatesDuringRotation` right after `viewWillTransition`, so the
layout pass that follows sends the new metrics at once and Flutter renders the new size from
the first frame, as a UIKit view lays out, instead of holding the old frame for half the turn.
Phone behaviour is unverified.

Phone result (2026-10-29): build 10 "still no".

## 2026-10-29 — build 11: discrete resizing

`UIRequiresFullScreen = YES` in `ios/Runner/Info.plist`. Per Apple TN3192, from iOS 27 an app
built with the iOS 27 SDK that sets this key is resized discretely instead of live, the mode
meant for apps that render into one surface: no live resize, no old-screen picture. Builds 9
and 10's `RotationViewController` stays. Phone behaviour is unverified.

Phone result (2026-10-29): build 11 "still no"; the cut looked a little smaller once the
sheet was expanded to nearly the whole screen.

## 2026-10-29 — build 12: not built

A stock-Flutter-only comparison was prepared and dropped at the user's request: a sheet
with nothing native in it is already known to be clean. The adaptive entry is restored.

## 2026-10-29 — build 13: Flutter view pinned to the scroll bounds at once

The host keeps the Flutter view inside `NativeFlutterScrollView` (a `UIScrollView` that is
the navigation controller's content scroll view) and re-pinned its viewport to the scroll
bounds only in `layoutSubviews`. During a turn UIKit changes that scroll view's offset as
the bars change height, so between that change and the next layout pass the Flutter
surface sat displaced: the ghost in the user's frame is offset, not only rotated.
`NativeFlutterScrollView` now re-pins the viewport in `bounds` and `contentOffset` setters.
Sheet as build 8 (UIKit, segmented control). `UIRequiresFullScreen` off, storyboard on
`FlutterViewController`. Phone behaviour is unverified.

Phone result (2026-10-29): build 13 "still really bad".

## 2026-10-29 — build 14: Flutter view beside the scroll view

The page's view is now a plain container holding the host's content scroll view and, as
a sibling above it, the Flutter viewport. The Flutter surface is no longer inside the
`UIScrollView` the navigation controller drives, so no offset change during the turn can
move it. Sheet as build 8. Phone behaviour is unverified.

Phone result (2026-10-29): build 14 "still no".

## 2026-10-29 — build 15: no app bar, no tab bar

The toolbar and the tab bar are Flutter platform views on the page
(`iOS26ToolbarPlatformView`, `iOS26TabBarPlatformView`), so the page always composites
through Flutter's platform-view path. Build 15 keeps `AdaptiveScaffold`, the native host and
build 14's layout, and drops `appBar` and `bottomNavigationBar`. Sheet as build 8. If this is
clean, the next builds put each bar back on its own. Phone behaviour is unverified.

Phone result (2026-10-29): build 15 still cut, so the bars are cleared.

## 2026-10-29 — build 16: no bars, Flutter sheet

Build 15 with the filter as a stock `showModalBottomSheet` holding the Flutter-only content,
opened expanded. No UIKit sheet, no bars, no platform view. Only the adaptive app and its
native host container remain. Phone behaviour is unverified.

## 2026-10-29 — build 17: package sheet with adaptive controls, no bars

Build 16's stock Material sheet replaced by the package's Flutter-drawn `AdaptiveNativeSheet`
holding adaptive controls: `AdaptiveSegmentedControl` (native `UISegmentedControl`) at the
top, the symbol chips, and behind the open section the date line, period chips and an
`AdaptiveSlider` (native `UISlider`). Bars still off. Phone behaviour is unverified.

## 2026-10-29 — build 18: bars back

Build 17's sheet (package Flutter-drawn sheet, native segmented control and slider inside)
with the native toolbar and tab bar restored. Phone behaviour is unverified.

Phone result (2026-10-29): build 18 cut. The user judged builds 9 to 18 all huge fails. The
full table of POC builds and what each rules out is in the main project's
`docs/sheet-rotation-cut-failed-attempts.md` under "POC builds, all failed".
