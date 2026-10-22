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
        AdaptiveFilterOption(
          'all',
          'All',
          icon: AdaptiveIcon(
            sfSymbol: 'infinity',
            icon: Icons.all_inclusive_rounded,
          ),
        ),
        AdaptiveFilterOption(
          'bought',
          'Bought',
          icon: AdaptiveIcon(
            sfSymbol: 'plus.circle',
            icon: Icons.add_circle_outline_rounded,
          ),
        ),
        AdaptiveFilterOption(
          'dividends',
          'Dividends',
          icon: AdaptiveIcon(
            sfSymbol: 'arrow.down.left',
            icon: Icons.south_west_rounded,
          ),
          tint: green,
        ),
      ]),
      AdaptiveFilterChoices(
        'symbols',
        icon: AdaptiveIcon(sfSymbol: 'tag.circle', icon: Icons.sell_outlined),
        layout: AdaptiveFilterLayout.swatches,
        multiple: true,
        assetSwatches(assets),
      ),
      const AdaptiveFilterChoices(
        'period',
        icon: AdaptiveIcon(
          sfSymbol: 'calendar',
          icon: Icons.calendar_month_outlined,
        ),
        layout: AdaptiveFilterLayout.strip,
        [
          AdaptiveFilterOption(
            'all',
            'Any time',
            icon: AdaptiveIcon(
              sfSymbol: 'infinity',
              icon: Icons.all_inclusive_rounded,
            ),
          ),
          AdaptiveFilterOption(
            'week',
            '7 days',
            icon: AdaptiveIcon(
              sfSymbol: 'calendar',
              icon: Icons.calendar_month_outlined,
            ),
          ),
          AdaptiveFilterOption(
            'threeDays',
            '3 days',
            icon: AdaptiveIcon(sfSymbol: 'clock', icon: Icons.schedule_rounded),
          ),
        ],
      ),
      const AdaptiveFilterSlider(
        'minAmount',
        icon: AdaptiveIcon(sfSymbol: 'banknote', icon: Icons.payments_outlined),
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
