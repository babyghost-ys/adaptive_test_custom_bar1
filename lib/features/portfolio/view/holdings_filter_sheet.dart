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
        icon: AdaptiveIcon(
          sfSymbol: 'arrow.up.arrow.down',
          icon: Icons.swap_vert_rounded,
        ),
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption(
            'value',
            'Value',
            icon: AdaptiveIcon(
              sfSymbol: 'wallet.bifold',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
          AdaptiveFilterOption(
            'change',
            'Change',
            icon: AdaptiveIcon(
              sfSymbol: 'percent',
              icon: Icons.percent_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'symbol',
            'A-Z',
            icon: AdaptiveIcon(
              sfSymbol: 'textformat.abc',
              icon: Icons.sort_by_alpha_rounded,
            ),
          ),
        ],
      ),
      const AdaptiveFilterChoices(
        'movement',
        layout: AdaptiveFilterLayout.stack,
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
      const AdaptiveFilterChoices(
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
      const AdaptiveFilterSlider(
        'minValue',
        icon: AdaptiveIcon(sfSymbol: 'banknote', icon: Icons.payments_outlined),
        min: 0,
        max: HoldingsFilter.maxValue,
        prefix: 'Over \$',
        anyLabel: 'Any size',
      ),
      const AdaptiveFilterSlider(
        'minChange',
        icon: AdaptiveIcon(sfSymbol: 'percent', icon: Icons.percent_rounded),
        min: HoldingsFilter.floor,
        max: 3,
        prefix: 'Above ',
        suffix: '%',
        decimals: 1,
        anyLabel: 'Any change',
      ),
      AdaptiveFilterChoices(
        'symbols',
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
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
