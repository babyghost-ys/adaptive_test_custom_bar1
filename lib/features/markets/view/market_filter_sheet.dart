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
    icon: AdaptiveIcon(
      sfSymbol: 'chart.line.uptrend.xyaxis',
      icon: Icons.trending_up_rounded,
    ),
    layout: AdaptiveFilterLayout.blocks,
    [
      AdaptiveFilterOption(
        'all',
        'All',
        icon: AdaptiveIcon(
          sfSymbol: 'infinity',
          icon: Icons.all_inclusive_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'gainers',
        'Gainers',
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.up.right',
          icon: Icons.north_east_rounded,
        ),
        tint: green,
      ),
      AdaptiveFilterOption(
        'losers',
        'Losers',
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.down.right',
          icon: Icons.south_east_rounded,
        ),
      ),
    ],
  ),
  AdaptiveFilterChoices(
    'sort',
    icon: AdaptiveIcon(
      sfSymbol: 'arrow.up.arrow.down',
      icon: Icons.swap_vert_rounded,
    ),
    [
      AdaptiveFilterOption(
        'symbol',
        'A-Z',
        icon: AdaptiveIcon(
          sfSymbol: 'textformat.abc',
          icon: Icons.sort_by_alpha_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'price',
        'Price',
        icon: AdaptiveIcon(
          sfSymbol: 'dollarsign',
          icon: Icons.attach_money_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'change',
        'Change',
        icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
      ),
    ],
  ),
  AdaptiveFilterSlider(
    'maxPrice',
    icon: AdaptiveIcon(sfSymbol: 'tag', icon: Icons.sell_outlined),
    min: 100,
    max: MarketFilter.ceiling,
    prefix: 'Up to \$',
    anyLabel: 'Any price',
    anyAtMin: false,
  ),
  AdaptiveFilterChoices(
    'types',
    icon: AdaptiveIcon(
      sfSymbol: 'square.grid.2x2',
      icon: Icons.grid_view_rounded,
    ),
    layout: AdaptiveFilterLayout.blocks,
    multiple: true,
    columns: 2,
    [
      AdaptiveFilterOption(
        'stock',
        'Stocks',
        icon: AdaptiveIcon(
          sfSymbol: 'building.2',
          icon: Icons.business_rounded,
        ),
      ),
      AdaptiveFilterOption(
        'etf',
        'ETFs',
        icon: AdaptiveIcon(
          sfSymbol: 'chart.pie',
          icon: Icons.pie_chart_outline_rounded,
        ),
      ),
    ],
  ),
  AdaptiveFilterSlider(
    'minChange',
    icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
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
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
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
