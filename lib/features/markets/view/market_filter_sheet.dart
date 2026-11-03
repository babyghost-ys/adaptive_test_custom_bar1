import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

/// The sheet's content is a plain widget built from the package's native
/// controls: the segmented controls and slider are real UIKit views
/// on iOS, drawn inside the native sheet like any other widget.
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) {
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

class MarketFilterContent extends StatelessWidget {
  const MarketFilterContent({super.key, required this.draft});

  final ValueNotifier<MarketFilter> draft;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MarketFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.apply(assets).length,
      onClose: () => AdaptiveNativeSheet.pop(context),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Gainers', 'Losers'],
          selectedIndex: filter.movement.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(movement: MarketMovement.values[i]),
        ),
        const SizedBox(height: 8),
        AdaptiveSegmentedControl(
          labels: const ['All types', 'Stocks', 'ETFs'],
          selectedIndex: _typeIndex(filter.types),
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
      ],
    ),
  );

  int _typeIndex(Set<HoldingType> types) {
    if (types.length != 1) return 0;
    return types.contains(HoldingType.stock) ? 1 : 2;
  }
}
