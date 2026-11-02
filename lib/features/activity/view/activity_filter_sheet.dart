import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/native_sheet_codec.dart';
import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

/// A native sheet that follows the height of the widget it is given. Choosing
/// the date line opens a second native sheet on top, holding another widget:
/// the native wheel date picker.
Future<ActivityFilter?> showActivityFilterSheet(
  BuildContext context,
  ActivityFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<ActivityFilter>(
    context: context,
    route: 'activity',
    arguments: NativeSheetCodec.encode(current),
    decodeResult: NativeSheetCodec.activity,
    builder: (_) => ActivityFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class ActivityFilterContent extends StatelessWidget {
  const ActivityFilterContent({super.key, required this.draft});

  final ValueNotifier<ActivityFilter> draft;

  /// Opens the date picker as a second sheet over this one.
  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDateSheet(
      context,
      draft.value.since ?? activityDate(0),
    );
    if (picked != null) draft.value = draft.value.copyWith(since: picked);
  }

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
        AdaptiveSegmentedControl(
          labels: const ['All', 'Bought', 'Dividends'],
          selectedIndex: filter.kind.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(kind: ActivityKind.values[i]),
        ),
        const SizedBox(height: 8),
        for (final a in assets)
          SwitchLine(
            icon: Icons.show_chart_rounded,
            text: a.symbol,
            value: filter.symbols.contains(a.symbol),
            onChanged: (on) => draft.value = filter.copyWith(
              symbols: on
                  ? {...filter.symbols, a.symbol}
                  : ({...filter.symbols}..remove(a.symbol)),
            ),
          ),
        _DateLine(
          since: filter.since,
          onTap: () => _pickDate(context),
          onClear: () => draft.value = filter.copyWith(clearSince: true),
        ),
        const SizedBox(height: 12),
        AdaptiveSegmentedControl(
          labels: const ['Any time', '7 days', '3 days'],
          selectedIndex: filter.period.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(period: ActivityPeriod.values[i]),
        ),
        const SizedBox(height: 16),
        label(
          filter.minAmount <= 0
              ? 'Any amount'
              : 'Over ${money(filter.minAmount)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.minAmount,
          max: ActivityFilter.maxAmount,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(minAmount: v),
        ),
      ],
    ),
  );
}

/// A tappable line that shows the chosen date and opens the date page.
class _DateLine extends StatelessWidget {
  const _DateLine({
    required this.since,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? since;
  final VoidCallback onTap;
  final VoidCallback onClear;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // Opening the native sheet supplies the interaction feedback.
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, color: muted),
          const SizedBox(width: 14),
          Expanded(
            child: label(
              since == null
                  ? 'Any date'
                  : 'From ${since!.day} ${_months[since!.month - 1]} ${since!.year}',
              size: 17,
              weight: since == null ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
          if (since != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 20),
              color: muted,
              visualDensity: VisualDensity.compact,
            ),
          const Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    ),
  );
}

/// Opens a second native sheet over the first, holding the wheel date picker.
/// Returns the chosen date, or null when the sheet is dragged away.
Future<DateTime?> showDateSheet(BuildContext context, DateTime initial) {
  final chosen = ValueNotifier(initial);
  return AdaptiveNativeSheet.show<DateTime>(
    context: context,
    route: 'date',
    arguments: NativeSheetCodec.encode(initial),
    decodeResult: NativeSheetCodec.date,
    builder: (_) => DateSheetContent(chosen: chosen),
  ).whenComplete(chosen.dispose);
}

/// The second sheet's widget: the native `UIDatePicker` in its classic wheel
/// style, and a Done button.
class DateSheetContent extends StatelessWidget {
  const DateSheetContent({super.key, required this.chosen});

  final ValueNotifier<DateTime> chosen;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            label('Date', size: 22, weight: FontWeight.w600),
            SizedBox(
              height: 216,
              child: AdaptiveInlineDatePicker(
                initialDate: chosen.value,
                firstDate: activityDate(11),
                lastDate: activityDate(0),
                tintColor: red,
                onDateChanged: (d) => chosen.value = d,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => AdaptiveNativeSheet.pop(context, chosen.value),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
