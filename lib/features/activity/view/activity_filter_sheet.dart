import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/filtering/filter_values.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

Map<String, Object> _values(ActivityFilter f) => {
  'kind': [f.kind.name],
  'symbols': f.symbols.toList(),
  'period': [f.period.name],
  'minAmount': f.minAmount,
};

ActivityFilter _filter(Map<String, Object> v) => ActivityFilter(
  kind: chosenEnum(v, 'kind', ActivityKind.values),
  symbols: chosenIds(v, 'symbols').toSet(),
  period: chosenEnum(v, 'period', ActivityPeriod.values),
  minAmount: v['minAmount'] as double,
);

/// Shows the activity filter sheet and returns the chosen filter.
Future<ActivityFilter?> showActivityFilterSheet(
  BuildContext context,
  ActivityFilter current,
) async {
  final result = await AdaptiveFilterSheet.show(
    context: context,
    title: 'Filters',
    tint: red,
    controls: [
      const AdaptiveFilterChoices('kind', layout: AdaptiveFilterLayout.stack, [
        AdaptiveFilterOption('all', 'All', sfSymbol: 'infinity'),
        AdaptiveFilterOption('bought', 'Bought', sfSymbol: 'plus.circle'),
        AdaptiveFilterOption(
          'dividends',
          'Dividends',
          sfSymbol: 'arrow.down.left',
          tint: green,
        ),
      ]),
      AdaptiveFilterChoices(
        'symbols',
        sfSymbol: 'tag.circle',
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
      const AdaptiveFilterChoices(
        'period',
        sfSymbol: 'calendar',
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption('all', 'Any time', sfSymbol: 'infinity'),
          AdaptiveFilterOption('week', '7 days', sfSymbol: 'calendar'),
          AdaptiveFilterOption('threeDays', '3 days', sfSymbol: 'clock'),
        ],
      ),
      const AdaptiveFilterSlider(
        'minAmount',
        sfSymbol: 'banknote',
        min: 0,
        max: ActivityFilter.maxAmount,
        prefix: 'Over \$',
        anyLabel: 'Any amount',
      ),
    ],
    values: _values(current),
    cleared: _values(const ActivityFilter()),
    count: (v) => _filter(v).matching(assets).length,
  );
  return result == null ? null : _filter(result);
}
