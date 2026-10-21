# Remove `foldable` from `adaptive_platform_ui`

This migration is implemented in this repository. Use this guide when applying it to another checkout or reviewing the change. Paths below are relative to the repository root; `P` means `packages/adaptive_platform_ui`.

## Scope and behavior to preserve

The package used `Foldable.snapshot` and `Foldable.changes` **only for reserved-region geometry**. It did not consume hinge angle, posture, capabilities, display features, or size classes. Toolbar placement already comes from `DuoLayout.resolvePose`, Flutter safe-area insets, and the package's `SystemVerticalBar` bridge.

Do not replace camera/status-area bounds with screen-size guesses. Remove the third-party dependency while keeping these behaviors:

- Existing left/right toolbar placement, including the leading Split View pane.
- Camera/status clearance after rotation, folding, unfolding, or pane changes.
- Existing conservative clearance when no usable region has arrived.
- Native navigation, title measurement, safe areas, and non-iOS behavior.

This removes the dependency; it does not replace the package's other upstream code or change its licensing/attribution.

## 1. Own the small geometry model

Add `P/lib/src/platform/reserved_region.dart`. The essential shape is:

```dart
import 'package:flutter/widgets.dart';

enum ReservedRegionKind { occlusion, division }

@immutable
class ReservedRegion {
  const ReservedRegion({
    required this.kind,
    required this.bounds,
    required this.isActive,
  });

  final ReservedRegionKind kind;
  final Rect bounds;
  final bool isActive;

  // Also implement fromWire, value equality, and hashCode as in this checkout.
}
```

`fromWire` accepts a list of maps containing `x`, `y`, `width`, and `height`. Reject malformed, non-finite, or non-positive geometry; return an unmodifiable list of active occlusions. Bounds are **Flutter-view logical coordinates**, not physical pixels. Value equality lets `listEquals` suppress redundant updates. Keep `division` so existing layout logic/fixtures can express regions that must not affect clearance; the native bridge queries only occlusions.

## 2. Extend the existing native bridge

Edit `P/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/VerticalBarEdgeStreamHandler.swift`. Reuse the registered `adaptive_platform_ui/vertical_bar_edge` event channel; do not introduce another plugin or one native subscription per widget.

Change its payload from an edge string to:

```swift
let payload: NSDictionary = [
    "edge": edge,
    "regions": view.map(Self.occlusions) ?? []
]
guard lastSent == nil || !payload.isEqual(lastSent!) else { return }
lastSent = payload
sink?(payload)
```

Change `lastSent` to `NSDictionary?`. Each region is a map of four `Double` values. Preserve the existing physical-edge conversion, including right-to-left layouts.

The current implementation uses guarded Objective-C runtime lookup so older SDKs need not name the newer UIKit types. Import `ObjectiveC.runtime`. The core query is:

```swift
let query = NSSelectorFromString("reservedRegionsOfKind:options:")
let factory = NSSelectorFromString("occlusionRegionKind")
guard view.responds(to: query),
      let kindClass = NSClassFromString("UIViewReservedRegionKind"),
      let method = class_getClassMethod(kindClass, factory)
else { return [] }

typealias MakeKind = @convention(c)
    (AnyClass, Selector) -> Unmanaged<AnyObject>
let makeKind = unsafeBitCast(method_getImplementation(method), to: MakeKind.self)
let kind = makeKind(kindClass, factory).takeUnretainedValue()

typealias Query = @convention(c)
    (AnyObject, Selector, AnyObject, UInt) -> Unmanaged<AnyObject>
let read = unsafeBitCast(view.method(for: query), to: Query.self)
guard let regions = read(view, query, kind, 0)
    .takeUnretainedValue() as? [NSObject]
else { return [] }
```

Use the complete `occlusions(in:)` implementation in that file: guard the `frame` accessor, extract `NSValue.cgRectValue`, reject null/infinite/empty frames, skip inactive regions, and serialize the rectangle. These selectors and signatures were checked against the installed iOS 27.1 UIKit headers; preserve their exact calling conventions.

Lifecycle requirements:

- Keep the invisible, non-interactive observer aligned to the Flutter host view.
- Send initially and on layout, trait, and safe-area changes.
- Preserve attachment retries and generation guards when the host has no window yet.
- Refresh regions every 0.25 seconds while subscribed: activity can change without a layout callback. Deduplicate the **whole payload**, not just the edge.
- Invalidate the timer on cancellation, a new subscription, and deinitialization; use weak captures.
- Return empty regions when the API is unavailable. Keep the existing layout fallback.

## 3. Share geometry through Dart

Edit `P/lib/src/platform/system_vertical_bar.dart`. Add the model import and a shared notifier:

```dart
static final ValueNotifier<List<ReservedRegion>> _regions =
    ValueNotifier(const []);

static List<ReservedRegion> get currentRegions => _regions.value;

static ValueListenable<List<ReservedRegion>> get regions {
  edge; // Starts the existing shared event subscription.
  return _regions;
}
```

Inside the existing channel listener, decode both the new map and an older native edge-only payload:

```dart
final map = value is Map ? value : null;
final regions = ReservedRegion.fromWire(map?['regions']);
if (!listEquals(_regions.value, regions)) _regions.value = regions;
_edge.value = SystemVerticalBarEdge.fromWire(map?['edge'] ?? value);
_measureTitleBand();
```

Keep the existing missing-channel/error handling. `currentRegions` must not start a subscription, so builds on other platforms stay inert. The string fallback supports new Dart with an older native bridge; old Dart does not understand the new map. Rebuild the native app after migration—hot reload alone is insufficient.

## 4. Replace consumers and fixtures

| File under `P` | Change |
| --- | --- |
| `lib/src/toolbar/adaptive_toolbar_host.dart` | Remove `FoldableData`, snapshot requests, stream subscription, and `dart:async`; listen to `SystemVerticalBar.regions` and read `currentRegions`. |
| `lib/src/widgets/ios26/ios26_scaffold.dart` | Remove the same fold subscription; add/remove a region listener alongside the existing edge/title listeners. |
| `lib/src/toolbar/duo_vertical_bar.dart` | Import the local model; keep `DuoLayout.barInsets` and pose resolution unchanged. |
| `lib/src/toolbar/hosted_duo_bar.dart` | Import the local model; keep the existing `regions` plumbing. |

Register listeners only in the existing iOS 26+ path, rebuild on changes, and remove widget listeners in `dispose`. The host must still bypass native readings when a debug override is supplied.

Replace the testing-only `debugFold` parameter with `List<ReservedRegion>? debugRegions`:

```dart
AdaptiveToolbarHost(
  debugRegions: const [
    ReservedRegion(
      kind: ReservedRegionKind.occlusion,
      bounds: Rect.fromLTRB(867, 0, 951, 120),
      isActive: true,
    ),
  ],
  child: child,
)
```

Update `test/duo_vertical_bar_test.dart`, `test/hosted_top_toolbar_test.dart`, and `test/toolbar_host_chrome_test.dart` to import the local model. Replace `FoldableData` fixtures with region lists, removing unused capabilities, posture, angle, display features, and size classes. An empty list still forces hosted chrome in fixtures. Preserve existing assertions; this is an API migration, not a reason to weaken coverage.

## 5. Remove dependencies and finish

Remove `foldable:` and its obsolete explanatory comment from `P/pubspec.yaml`. Remove the app-level entry from root `pubspec.yaml` only after confirming the app has no separate usage. Refresh both resolutions:

```sh
flutter pub get --offline
(cd packages/adaptive_platform_ui && flutter pub get --offline)
```

Omit `--offline` if required packages are not cached. Let Flutter regenerate plugin metadata; do not hand-edit generated registrants. In this checkout, resolution also removed the now-unused `plugin_platform_interface` transitive dependency. Leave historical changelog/contributor entries intact and add a migration entry under Unreleased.

Inspect remaining references:

```sh
rg -n 'package:foldable|FoldableData|Foldable\.(snapshot|changes)|debugFold' \
  lib packages/adaptive_platform_ui/lib packages/adaptive_platform_ui/test
rg -n '^  foldable:' pubspec.yaml pubspec.lock \
  packages/adaptive_platform_ui/pubspec.yaml packages/adaptive_platform_ui/pubspec.lock
git diff --check
```

Compile the iOS app through Build iOS Apps/XcodeBuildMCP, following the repository's instructions. Do not run tests unless requested. If runtime verification is requested, inspect open/folded displays, rotation, both Split View panes, and initial/scrolled navigation; compilation does not establish visual correctness.

**Recorded result:** dependency resolution removed `foldable`; the iPhone Duo simulator build succeeded. Existing fixtures were migrated, but tests and runtime visual checks were not run. Older-SDK compilation was not verified.
