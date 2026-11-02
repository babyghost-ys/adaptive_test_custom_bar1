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
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

/// A native sheet that follows the height of the widget it is given. The
/// widget is stateless and owned by the app: the draft lives in a notifier
/// made here. Its controls are the package's native ones,
/// so the content keeps one height at any width and turns cleanly.
Future<WatchlistFilter?> showWatchlistFilterSheet(
  BuildContext context,
  WatchlistFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<WatchlistFilter>(
    context: context,
    route: 'watchlist',
    arguments: NativeSheetCodec.encode(current),
    decodeResult: NativeSheetCodec.watchlist,
    builder: (_) => WatchlistFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class WatchlistFilterContent extends StatelessWidget {
  const WatchlistFilterContent({super.key, required this.draft});

  final ValueNotifier<WatchlistFilter> draft;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WatchlistFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: assets.where(filter.allows).length,
      onReset: filter == const WatchlistFilter()
          ? null
          : () => draft.value = const WatchlistFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Gainers', 'Losers'],
          selectedIndex: filter.movement.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(movement: MarketMovement.values[i]),
        ),
        SwitchLine(
          icon: Icons.business_rounded,
          text: 'Stocks',
          value: filter.types.contains(HoldingType.stock),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.stock, on),
          ),
        ),
        SwitchLine(
          icon: Icons.pie_chart_outline_rounded,
          text: 'ETFs',
          value: filter.types.contains(HoldingType.etf),
          onChanged: (on) => draft.value = filter.copyWith(
            types: _toggled(filter.types, HoldingType.etf, on),
          ),
        ),
        const SizedBox(height: 16),
        label(
          filter.maxPrice >= WatchlistFilter.ceiling
              ? 'Any price'
              : 'Up to ${money(filter.maxPrice)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.maxPrice,
          min: 100,
          max: WatchlistFilter.ceiling,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
        ),
      ],
    ),
  );

  Set<HoldingType> _toggled(Set<HoldingType> set, HoldingType type, bool on) =>
      on ? {...set, type} : ({...set}..remove(type));
}
