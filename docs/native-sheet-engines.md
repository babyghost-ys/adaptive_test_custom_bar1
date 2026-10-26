# Independent sheet engines

**Status: FAILED on the physical phone.** Implemented and installed 2026-10-25
to address the rotation cut recorded in `NYAQ7106.MP4`. The user subsequently
confirmed that the problem remains and requested documentation only, with no
retry. This document records the implementation still in the working tree;
it must not be treated as a successful rotation fix. See
[attempt 11](sheet-rotation-cut-failed-attempts.md#attempt-11-independent-flutter-engine-for-each-uikit-sheet)
and the ten earlier failed attempts.

On 2026-10-26 the user authorized another approach. Attempt 12 retains this
ownership design but sets `FLTUseFlutterMetalLayer=false` in the main app's
Info.plist, selecting system `CAMetalLayer` for every Flutter engine and overlay.
**Attempt 12 also FAILED:** after the signed Release build was installed on the
iPhone 18 Pro, the user reported "still not working" and requested documentation
only, with no retry. See the attempt log for details. The setting and independent
engines remain in place; neither attempt is a verified rotation fix.

## Ownership

- The page engine stays attached to its original `FlutterViewController`.
- Each UIKit sheet owns a separate `FlutterEngine` created by a shared
  `FlutterEngineGroup`, and one `FlutterViewController` for that engine.
- Each sheet has its own transparent presentation window. The page and covered
  sheets remain live while UIKit handles the sheet, dimming, detents and drag.
- Platform-view factories are registered for every sheet engine. The global
  page navigation channels are registered only by the page engine.
- No engine lending, frozen page or sheet images, manual appearance callbacks,
  private metric-hold release, or UIKit snapshot suppression is used.

Flutter's supported multiple-instance model is documented at
https://docs.flutter.dev/add-to-app/multiple-flutters.

## Dart integration

Every native call supplies a `route`, codec-safe `arguments`, and (for a typed
result) `decodeResult`. The existing `builder` supplies the Android content.

```dart
return AdaptiveNativeSheet.show<ActivityFilter>(
  context: context,
  route: 'activity',
  arguments: NativeSheetCodec.encode(current),
  decodeResult: NativeSheetCodec.activity,
  builder: (_) => ActivityFilterContent(draft: draft, more: more),
);
```

`main.dart` exports `nativeSheetMain` with `@pragma('vm:entry-point')` so Release
tree shaking retains it. It calls `runNativeSheetApp`, which bootstraps the
configuration and constructs the same content widgets with locally owned draft
notifiers. `NativeSheetCodec` preserves every filter field, enum, account set
and date. Closures and Flutter widget objects never cross engine boundaries.

Use `CupertinoApp` with the app's `AdaptiveTheme` and matching Material theme for
the sheet root. Do not install `AdaptiveApp`, `AdaptiveToolbarHost`, or the
page router in that engine. `AdaptiveNativeSheetContent` supplies background,
fit-height measurement, scrolling, keyboard inset and the startup handshake.

`AdaptiveNativeSheet.pop(context, value)` serializes the result and asks UIKit
to dismiss. The originating `show` future completes after dismissal. A nested
sheet returns to its own parent engine, preserving the parent's draft and
scroll position. A drag dismissal returns null. A non-dismissible sheet retains
its explicit close control and has no grabber.

Current routes: `watchlist`, `activity`, `date`, `orders`, `accounts`, `markets`,
`signIn`. The full-screen sign-in route uses the same independent ownership.

## Delivery scope

The requested verification is a signed Release build installed directly on the
physical iPhone. No simulator runs or test suites are part of this attempt.
The Release build compiled and installed successfully on the iPhone 18 Pro on
2026-10-25 (`com.peterleung.meridian`); it was not launched by the agent.
The user's subsequent phone result was "still not working." Compilation and
installation succeeded, but the rotation fix failed. No new recording or runtime
inspection establishes whether the artifact changed in timing or severity.
The implementation remains in place. No retry, rebuild, reinstall or code change
followed the user's request to document this failure only.
