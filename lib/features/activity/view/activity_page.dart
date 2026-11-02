import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/activity/view/activity_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

class Activity extends StatefulWidget {
  const Activity({super.key, this.shortSheet = false});

  /// Opens the short filter sheet (kind and amount only).
  final bool shortSheet;
  @override
  State<Activity> createState() => _ActivityState();
}

class _ActivityState extends State<Activity> {
  ActivityFilter filter = const ActivityFilter();

  Future<void> openFilters() async {
    final result = await showActivityFilterSheet(
      context,
      filter,
      short: widget.shortSheet,
    );
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final rows = filter.matching(assets);
    return PageScroll(
      storageKey: 'activity',
      children: [
        FilterSectionHeader(
          title: 'Recent activity',
          onPressed: openFilters,
          activeCount: filter.activeCount,
        ),
        const SizedBox(height: 20),
        for (final i in rows)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE5EBE1),
              child: Icon(
                i % 3 == 0 ? Icons.south_west : Icons.add,
                color: green,
                size: 20,
              ),
            ),
            title: label(
              i % 3 == 0 ? 'Dividend · VOO' : 'Bought ${assets[i % 6].symbol}',
              weight: FontWeight.w500,
            ),
            subtitle: label(
              'Oct ${activityDate(i).day} · Personal',
              size: 12,
              color: muted,
            ),
            trailing: label(
              i % 3 == 0 ? '+\$128.40' : money(assets[i % 6].price),
              size: 14,
            ),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Icon(Icons.search_off_rounded, size: 40, color: muted),
          ),
      ],
    );
  }
}
