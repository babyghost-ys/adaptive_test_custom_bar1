import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

/// A native sheet that follows the height of the widget it is given, which
/// grows when "more" opens.
Future<ActivityFilter?> showActivityFilterSheet(
  BuildContext context,
  ActivityFilter current,
) {
  final draft = ValueNotifier(current);
  final more = ValueNotifier(
    current.period != ActivityPeriod.all || current.minAmount > 0,
  );
  return AdaptiveNativeSheet.show<ActivityFilter>(
    context: context,
    builder: (_) => ActivityFilterContent(draft: draft, more: more),
  ).whenComplete(() {
    draft.dispose();
    more.dispose();
  });
}

class ActivityFilterContent extends StatelessWidget {
  const ActivityFilterContent({
    super.key,
    required this.draft,
    required this.more,
  });

  final ValueNotifier<ActivityFilter> draft;
  final ValueNotifier<bool> more;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ActivityFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.matching(assets).length,
      onReset: filter == const ActivityFilter()
          ? null
          : () => draft.value = const ActivityFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        ChipGroup<ActivityKind>(
          options: const [
            (ActivityKind.all, Icons.all_inclusive_rounded, 'All'),
            (ActivityKind.bought, Icons.add_circle_outline_rounded, 'Bought'),
            (ActivityKind.dividends, Icons.south_west_rounded, 'Dividends'),
          ],
          isSelected: (k) => filter.kind == k,
          onTap: (k) => draft.value = filter.copyWith(kind: k),
        ),
        const SizedBox(height: 16),
        ChipGroup<String>(
          options: [
            for (final a in assets)
              (a.symbol, Icons.show_chart_rounded, a.symbol),
          ],
          isSelected: filter.symbols.contains,
          onTap: (s) => draft.value = filter.copyWith(
            symbols: filter.symbols.contains(s)
                ? ({...filter.symbols}..remove(s))
                : {...filter.symbols, s},
          ),
        ),
        OpenSection(
          open: more,
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipGroup<ActivityPeriod>(
                options: const [
                  (ActivityPeriod.all, Icons.all_inclusive_rounded, 'Any time'),
                  (
                    ActivityPeriod.week,
                    Icons.calendar_month_outlined,
                    '7 days',
                  ),
                  (ActivityPeriod.threeDays, Icons.schedule_rounded, '3 days'),
                ],
                isSelected: (p) => filter.period == p,
                onTap: (p) => draft.value = filter.copyWith(period: p),
              ),
              const SizedBox(height: 16),
              label(
                filter.minAmount <= 0
                    ? 'Any amount'
                    : 'Over ${money(filter.minAmount)}',
                size: 28,
                weight: FontWeight.w600,
              ),
              Slider(
                value: filter.minAmount,
                max: ActivityFilter.maxAmount,
                onChanged: (v) => draft.value = filter.copyWith(minAmount: v),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
