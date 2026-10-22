import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

Map<String, Object> _values(WatchlistFilter f) => {
  'movement': [f.movement.name],
};

WatchlistFilter _filter(Map<String, Object> v) =>
    WatchlistFilter(movement: chosenEnum(v, 'movement', MarketMovement.values));

/// A short sheet with a single control.
Future<WatchlistFilter?> showWatchlistFilterSheet(
  BuildContext context,
  WatchlistFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    detents: AdaptiveFilterDetents.short,
    controls: const [
      AdaptiveFilterChoices(
        'movement',
        sfSymbol: 'chart.line.uptrend.xyaxis',
        layout: AdaptiveFilterLayout.blocks,
        [
          AdaptiveFilterOption('all', 'All', sfSymbol: 'infinity'),
          AdaptiveFilterOption(
            'gainers',
            'Gainers',
            sfSymbol: 'arrow.up.right',
            tint: green,
          ),
          AdaptiveFilterOption(
            'losers',
            'Losers',
            sfSymbol: 'arrow.down.right',
          ),
        ],
      ),
    ],
    values: _values(current),
    cleared: _values(const WatchlistFilter()),
    count: (v) => assets.where(_filter(v).allows).length,
  );
  return result == null ? null : _filter(result);
}
