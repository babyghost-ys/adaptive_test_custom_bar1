import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

const _controls = <AdaptiveFilterControl>[
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
      AdaptiveFilterOption('losers', 'Losers', sfSymbol: 'arrow.down.right'),
    ],
  ),
  AdaptiveFilterChoices('sort', sfSymbol: 'arrow.up.arrow.down', [
    AdaptiveFilterOption('symbol', 'A-Z', sfSymbol: 'textformat.abc'),
    AdaptiveFilterOption('price', 'Price', sfSymbol: 'dollarsign'),
    AdaptiveFilterOption('change', 'Change', sfSymbol: 'percent'),
  ]),
  AdaptiveFilterSlider(
    'maxPrice',
    sfSymbol: 'tag',
    min: 100,
    max: MarketFilter.ceiling,
    prefix: 'Up to \$',
    anyLabel: 'Any price',
    anyAtMin: false,
  ),
  AdaptiveFilterChoices(
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
  AdaptiveFilterSlider(
    'minChange',
    sfSymbol: 'percent',
    min: MarketFilter.floor,
    max: 3,
    prefix: 'Above ',
    suffix: '%',
    decimals: 1,
    anyLabel: 'Any change',
  ),
];

Map<String, Object> _values(MarketFilter f) => {
  'movement': [f.movement.name],
  'sort': [f.sort.name],
  'maxPrice': f.maxPrice,
  'types': [for (final t in f.types) t.name],
  'minChange': f.minChange,
  'symbols': f.symbols.toList(),
};

MarketFilter _filter(Map<String, Object> v) => MarketFilter(
  movement: chosenEnum(v, 'movement', MarketMovement.values),
  sort: chosenEnum(v, 'sort', MarketSort.values),
  maxPrice: v['maxPrice'] as double,
  types: chosenEnums(v, 'types', HoldingType.values),
  minChange: v['minChange'] as double,
  symbols: chosenIds(v, 'symbols').toSet(),
);

/// Shows the market filter sheet and returns the chosen filter.
Future<MarketFilter?> showMarketFilterSheet(
  BuildContext context,
  MarketFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    controls: [
      ..._controls,
      AdaptiveFilterChoices(
        'symbols',
        sfSymbol: 'tag.circle',
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
    ],
    values: _values(current),
    cleared: _values(const MarketFilter()),
    count: (v) => _filter(v).apply(assets).length,
  );
  return result == null ? null : _filter(result);
}
