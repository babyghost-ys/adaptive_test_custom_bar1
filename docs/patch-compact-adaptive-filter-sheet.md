# Patch: compact adaptive filter sheet with a native close button

**The original problem was a visible split through the sheet content during
rotation, especially when a short landscape sheet stopped below the navigation
bar. The owner reports that this is now fixed.** This patch records the
rotation change and the compact sheet layout for other apps to adapt.

This patch is for an app that already has an adaptive sheet component and wants
a compact filter sheet that stays below the navigation bar in landscape. Adapt
it to the existing sheet API and filter model; do not replace the app's sheet
architecture or remove unrelated filters.

## What was established

- The Markets filter sheet in the reference app was changed to use compact,
  fixed-height rows, a native close button, and no outside-tap dismissal. The
  owner reported that version worked. A subsequent update made the cross smaller
  and removed the sort selector; that update was built and installed but has no
  separate visual verdict in this conversation.
- The original **rotation cut** split the sheet and its controls. A video of
  attempt 23 shows it during landscape-to-portrait rotation. Attempt 24 changed
  which UIKit layer is held, and the owner now reports the split is fixed. The
  available recording shows the earlier failure, rather than a frame-by-frame
  measurement of the fixed build. See
  [the attempt record](sheet-rotation-cut-attempts-19-20.md).
- A compact measured height is not an unconditional guarantee that a sheet will
  clear the bar on every phone, at every text size, or while rotating. The
  reference implementation does not calculate a bar-aware height limit.

## Expected behaviour

1. Present the existing native sheet with a content-fitting detent. Keep its
   normal native navigation bar, platform controls and safe areas.
2. Prevent dismissal by tapping the dimmed area. A close control at the top
   right discards the draft; Apply returns it to the page. In the reference
   component, `isDismissible: false` also disables drag dismissal and hides the
   grabber.
3. Make the close control a real native button: a plain 15 pt `xmark` SF
   Symbol, with no resting background, in a 44 by 44 pt hit area. Give it an
   accessible “Close” label and provide the platform's appropriate fallback.
4. Arrange the content in short rows that retain the app's relevant filters.
   The example has two native segmented controls and a price slider with its
   label alongside it. Its last version has no sort selector: removing sort and
   choosing these particular labels are **demo-specific decisions**, not a
   directive to remove another app's sort or filters.
5. In landscape, keep the sheet below the navigation bar. Do not force all
   sheets to full height. Where compact content alone is insufficient, add a
   genuine bar-aware maximum height and allow the content to scroll; the fit
   resolver shown below does not provide that limit by itself.

## 1. Present the sheet with a draft

The reference API uses one Flutter engine per native sheet. It passes a route
and codec-safe arguments into that engine. Use your own project's names and
codec; this is an adaptation pattern, not a stand-alone library:

```dart
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) {
  // This demo intentionally removed the sort selector. Keep this reset only
  // if your own product also chooses to remove sorting from this sheet.
  final initial = current.copyWith(sort: MarketSort.symbol);
  final draft = ValueNotifier(initial);
  return AdaptiveNativeSheet.show<MarketFilter>(
    context: context,
    route: 'markets',
    arguments: NativeSheetCodec.encode(initial),
    decodeResult: NativeSheetCodec.markets,
    isDismissible: false,
    builder: (_) => MarketFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}
```

The page applies the result only when it is non-null. When the close button
returns null, the original filter remains intact. If you retain a sort control,
initialise the draft from `current` without resetting it. Never leave a removed
control's old value invisibly active after applying the draft.

On iOS, the `builder` closure above is **not** the content passed into the
separate engine. Register the route in that engine's sheet app and create its
own notifier using the decoded arguments. Dispose that notifier when the sheet
app is disposed:

```dart
// Inside the existing sheet app's route switch; _own registers the notifier
// for disposal with the sheet app's other notifiers.
'markets' => MarketFilterContent(
  draft: _own(NativeSheetCodec.markets(argument!)),
),
```

Ensure that the relevant native button, segmented control and slider factories
are registered with that sheet engine. Other platforms can use the `builder`
with their existing route. Do not pass a notifier or closure across engines.

## 2. Native close control

In the reference `SheetFrame`, `onClose` is optional. When supplied in the
native style, the header uses this branch; the existing reset control remains
available to sheets that do not supply `onClose`:

```dart
Semantics(
  label: 'Close',
  button: true,
  child: SizedBox(
    width: 44,
    height: 44,
    child: AdaptiveButton.sfSymbol(
      onPressed: onClose,
      sfSymbol: const SFSymbol('xmark', size: 15, color: ink),
      color: ink,
      style: AdaptiveButtonStyle.plain,
      useSmoothRectangleBorder: false,
    ),
  ),
)
```

Place it at the trailing edge of the existing title row. `AdaptiveButton` in
this project renders a UIKit `UIButton` in native style; the SF Symbol is not a
Flutter-drawn substitute. For a non-native style, use the existing platform
fallback, such as an `IconButton` with `Icons.close_rounded` and a “Close”
tooltip. If the destination component has a native accessibility API, label the
actual native button as well as any Flutter semantics wrapper where needed.

Connect the actions to the **sheet's** pop method:

```dart
onClose: () => AdaptiveNativeSheet.pop(context),
onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
```

The no-value close must be encoded and returned as null, not an applied filter.

## 3. Compact content pattern

The reference layout keeps the same vertical arrangement in both orientations:

```dart
AdaptiveSegmentedControl(
  labels: const ['All', 'Gainers', 'Losers'],
  selectedIndex: filter.movement.index,
  onValueChanged: (i) =>
      draft.value = filter.copyWith(movement: MarketMovement.values[i]),
),
const SizedBox(height: 8),
AdaptiveSegmentedControl(
  labels: const ['All types', 'Stocks', 'ETFs'],
  selectedIndex: typeIndex(filter.types),
  onValueChanged: (i) => draft.value = filter.copyWith(
    types: switch (i) {
      1 => {HoldingType.stock},
      2 => {HoldingType.etf},
      _ => <HoldingType>{},
    },
  ),
),
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      flex: 2,
      child: Text(
        filter.maxPrice >= MarketFilter.ceiling
            ? 'Any price'
            : 'Up to ${money(filter.maxPrice)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      flex: 3,
      child: AdaptiveSlider(
        value: filter.maxPrice,
        min: 100,
        max: MarketFilter.ceiling,
        activeColor: red,
        onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
      ),
    ),
  ],
),
```

`typeIndex`, the filter model, colours and currency formatter are app-specific.
In the reference model an empty `types` set means all types; map it consistently
in both the UI and the filter. Preserve any other selected values and result
count logic when adapting this arrangement. Avoid width-dependent wrapping or
expanding content that makes a fit sheet unexpectedly tall during a turn.
Provide scrolling or an accessible alternative when text scaling or available
width makes the compact arrangement insufficient.

## 4. Keep the existing UIKit sheet behaviour

The reference sheet uses a UIKit `.pageSheet`, a transparent presentation
window, and one Flutter engine per sheet. Its content reports its measured
height; the native custom `fit` detent uses:

```swift
sheet.detents = [.custom(identifier: identifier) { context in
    min(context.maximumDetentValue, height)
}]
sheet.selectedDetentIdentifier = identifier
sheet.prefersEdgeAttachedInCompactHeight = true
```

This is a content fit, **not** a navigation-bar clearance calculation. Preserve
any existing height updates, transition handling and scroll fallback in the
target implementation. For this component, non-dismissible sheets use
`presentationControllerShouldDismiss` to return the level's `dismissible`
value; do not change every sheet's dismissal policy to implement this one.
Use the platform's normal dismissal API for the explicit close action.

## Rotation split fix

This section describes the reference code for an implementer whose sheet
already contains its `TurnHold` rotation mechanism. The owner reports the
sheet-content split is fixed after this change. The recorded failed attempt held
the presented view; attempt 24 instead asks the hold to
target the presentation controller's container, which is an ancestor of the
sheet and also contains UIKit's dimming view:

```swift
turnHold = TurnHold { [weak controller] in
    controller?.presentationController?.containerView?.layer
}
```

The existing `TurnHold` also records the actual layer it paused so that a
changing presentation does not cause `snap` to resume a different layer:

```swift
private weak var heldLayer: CALayer?

// At the beginning of hold(coordinator:), before setting speed to zero:
guard let layer = holding ? heldLayer : layer() else { return }
if !holding {
    holding = true
    heldLayer = layer
    // Keep the existing clock and coordinator handling here.
}

// In snap(duration:), after clearing the existing hold bookkeeping:
let pausedLayer = heldLayer
heldLayer = nil
guard let layer = pausedLayer, layer.speed == 0 else { return }
// Keep the existing clock-resume handling here.
```

These are fragments of the existing implementation, not a complete replacement
for `TurnHold`. In particular, retain its cancellation and dismissal handling.
The earlier recording cannot establish exactly which layer moved or whether a
non-animated layout change was involved. Do not add covers, snapshots, or new
guessed timing.

## Handoff check

Confirm the actual target app retains its relevant filter values and applies
only on Apply; close discards the draft; the native cross has a 44 pt hit area;
and outside taps do not close the sheet. Inspect portrait and landscape at the
intended device sizes and text scales when authorised, including that the
sheet clears the navigation bar and remains usable if content scrolls. Report
what was actually inspected. The reference owner's report does not establish
that the rotation fix works on a different app or device; the simulator did not
show the original phone-only cut.

Reference implementation: `lib/features/markets/view/market_filter_sheet.dart`,
`lib/core/widgets/sheet_frame.dart`, `lib/app/native_sheet_app.dart`, and
`packages/adaptive_platform_ui/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/Overlays/NativeWidgetSheet.swift`.

## Warning to the next AI: mistakes you must not repeat

The rotation fix above took 22 recorded attempts and a second AI to find,
because the first AI made the following errors. Do not make them.

1. **You must not hold a layer without checking that it holds.** The first
   AI paused the presented sheet view's layer and took "hiding that view makes
   the sheet vanish" as proof that its layer carried the rotation animation.
   Hiding proves containment, not where the animation lives. For the page
   window it held the root view, the top of the tree; for the sheet window it
   held a child and let the parent animate "because the dimming is harmless".
   That guess was the bug. Hold the top of the tree, not the node you believe
   is right.
2. **You must not reason past the fact that discriminates your hypotheses.**
   A tall sheet's top edge moves about 50 pt between orientations; a short
   one about 470 pt. Only a leaking hold produces exactly "tall is clean,
   short cuts". The first AI wrote that down, then chose a navigation-bar
   theory because it implicated UIKit rather than its own code, and spent
   three builds on it. Keep the hypothesis that implicates your own code ahead
   of the one that implicates the platform.
3. **You must not read "no change" as "wrong timing".** When pausing from the
   window's frame setter changed nothing, the right conclusion was that the
   pause acted on the wrong object. When a build fails, first ask whether the
   fix acted on the right object, before moving to a different theory.
4. **You must not judge rotation builds by eye.** Six builds were judged at
   normal speed with no recording. The notes from October already said timing
   changes need a frame-by-frame recording. The second AI asked the owner for
   one, read frame 241, saw the sheet itself split against the picture, and
   changed one line. Before any build that depends on "this layer is the one
   that moves", get a recording and name the frame.
5. **You must not leave a test rig in the tree.** Test scaffolding (the
   Watchlist tab showing another page with a short sheet) was committed to
   the main branch and left there. Restore it in the same session, before
   you report.

The retry prompt written for this bug already contained every one of these
rules; the AI that wrote it did not follow them itself. Having a rule written
down is not the same as applying it to your own next build.
