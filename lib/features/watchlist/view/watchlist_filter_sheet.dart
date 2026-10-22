import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

/// A native sheet that follows the height of the widget it is given. The
/// widget is plain Flutter, stateless, and owned by the app: the draft and the
/// open state live in notifiers made here.
Future<WatchlistFilter?> showWatchlistFilterSheet(
  BuildContext context,
  WatchlistFilter current,
) {
  final draft = ValueNotifier(current);
  final more = ValueNotifier(
    current.maxPrice < WatchlistFilter.ceiling || current.types.isNotEmpty,
  );
  return AdaptiveNativeSheet.show<WatchlistFilter>(
    context: context,
    builder: (_) => WatchlistFilterContent(draft: draft, more: more),
  ).whenComplete(() {
    draft.dispose();
    more.dispose();
  });
}

class WatchlistFilterContent extends StatelessWidget {
  const WatchlistFilterContent({
    super.key,
    required this.draft,
    required this.more,
  });

  final ValueNotifier<WatchlistFilter> draft;
  final ValueNotifier<bool> more;

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
        ChipGroup<MarketMovement>(
          options: const [
            (MarketMovement.all, Icons.all_inclusive_rounded, 'All'),
            (MarketMovement.gainers, Icons.north_east_rounded, 'Gainers'),
            (MarketMovement.losers, Icons.south_east_rounded, 'Losers'),
          ],
          isSelected: (m) => filter.movement == m,
          onTap: (m) => draft.value = filter.copyWith(movement: m),
        ),
        OpenSection(
          open: more,
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipGroup<HoldingType>(
                options: const [
                  (HoldingType.stock, Icons.business_rounded, 'Stocks'),
                  (HoldingType.etf, Icons.pie_chart_outline_rounded, 'ETFs'),
                ],
                isSelected: filter.types.contains,
                onTap: (t) => draft.value = filter.copyWith(
                  types: filter.types.contains(t)
                      ? ({...filter.types}..remove(t))
                      : {...filter.types, t},
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
              Slider(
                value: filter.maxPrice,
                min: 100,
                max: WatchlistFilter.ceiling,
                onChanged: (v) => draft.value = filter.copyWith(maxPrice: v),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
