import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

/// The sheet's content is a plain widget built from the package's native
/// controls: the segmented controls, slider and switches are real UIKit views
/// on iOS, drawn inside the native sheet like any other widget.
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<MarketFilter>(
    context: context,
    route: 'markets',
    arguments: NativeSheetCodec.encode(current),
    decodeResult: NativeSheetCodec.markets,
    builder: (_) => MarketFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class MarketFilterContent extends StatelessWidget {
  const MarketFilterContent({super.key, required this.draft});

  final ValueNotifier<MarketFilter> draft;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MarketFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.apply(assets).length,
      onReset: filter == const MarketFilter()
          ? null
          : () => draft.value = const MarketFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Gainers', 'Losers'],
          selectedIndex: filter.movement.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(movement: MarketMovement.values[i]),
        ),
        const SizedBox(height: 16),
        AdaptiveSegmentedControl(
          labels: const ['A-Z', 'Price', 'Change'],
          selectedIndex: filter.sort.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(sort: MarketSort.values[i]),
        ),
        const SizedBox(height: 24),
        label(
          filter.maxPrice >= MarketFilter.ceiling
              ? 'Any price'
              : 'Up to ${money(filter.maxPrice)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.maxPrice,
          min: 100,
          max: MarketFilter.ceiling,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
        ),
        const SizedBox(height: 8),
        _SwitchLine(
          text: 'Stocks',
          value: filter.types.contains(HoldingType.stock),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.stock, on),
          ),
        ),
        _SwitchLine(
          text: 'ETFs',
          value: filter.types.contains(HoldingType.etf),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.etf, on),
          ),
        ),
      ],
    ),
  );

  Set<HoldingType> _toggled(Set<HoldingType> set, HoldingType type, bool on) =>
      on ? {...set, type} : ({...set}..remove(type));
}

/// A title with a native switch at the trailing edge.
class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: label(text, size: 17),
        ),
      ),
      AdaptiveSwitch(value: value, onChanged: onChanged),
    ],
  );
}
