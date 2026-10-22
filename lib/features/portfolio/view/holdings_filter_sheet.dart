import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

Map<String, Object> _values(HoldingsFilter f) => {
  'sort': [f.sort.name],
  'movement': [f.movement.name],
  'types': [for (final t in f.types) t.name],
  'minValue': f.minValue,
  'minChange': f.minChange,
  'symbols': f.symbols.toList(),
};

HoldingsFilter _filter(Map<String, Object> v) => HoldingsFilter(
  sort: chosenEnum(v, 'sort', HoldingsSort.values),
  movement: chosenEnum(v, 'movement', MarketMovement.values),
  types: chosenEnums(v, 'types', HoldingType.values),
  minValue: v['minValue'] as double,
  minChange: v['minChange'] as double,
  symbols: chosenIds(v, 'symbols').toSet(),
);

/// A very long sheet: full height only. [scale] is the selected account's
/// share of the demo holdings.
Future<HoldingsFilter?> showHoldingsFilterSheet(
  BuildContext context,
  HoldingsFilter current, {
  required double scale,
}) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    detents: AdaptiveFilterDetents.full,
    controls: [
      const AdaptiveFilterChoices(
        'sort',
        sfSymbol: 'arrow.up.arrow.down',
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption('value', 'Value', sfSymbol: 'wallet.bifold'),
          AdaptiveFilterOption('change', 'Change', sfSymbol: 'percent'),
          AdaptiveFilterOption('symbol', 'A-Z', sfSymbol: 'textformat.abc'),
        ],
      ),
      const AdaptiveFilterChoices(
        'movement',
        layout: AdaptiveFilterLayout.stack,
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
      const AdaptiveFilterChoices(
        'types',
        sfSymbol: 'square.grid.2x2',
        layout: AdaptiveFilterLayout.blocks,
        multiple: true,
        columns: 2,
        [
          AdaptiveFilterOption('stock', 'Stocks', sfSymbol: 'building.2'),
          AdaptiveFilterOption('etf', 'ETFs', sfSymbol: 'chart.pie'),
        ],
      ),
      const AdaptiveFilterSlider(
        'minValue',
        sfSymbol: 'banknote',
        min: 0,
        max: HoldingsFilter.maxValue,
        prefix: 'Over \$',
        anyLabel: 'Any size',
      ),
      const AdaptiveFilterSlider(
        'minChange',
        sfSymbol: 'percent',
        min: HoldingsFilter.floor,
        max: 3,
        prefix: 'Above ',
        suffix: '%',
        decimals: 1,
        anyLabel: 'Any change',
      ),
      AdaptiveFilterChoices(
        'symbols',
        sfSymbol: 'tag.circle',
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
    ],
    values: _values(current),
    cleared: _values(const HoldingsFilter()),
    count: (v) => _filter(v).apply(assets, scale).length,
  );
  return result == null ? null : _filter(result);
}
