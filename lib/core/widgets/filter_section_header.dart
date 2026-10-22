import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/core/widgets/filter_button.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// A page section title with the filter button at its trailing edge.
class FilterSectionHeader extends StatelessWidget {
  const FilterSectionHeader({
    super.key,
    required this.title,
    required this.onPressed,
    required this.activeCount,
  });
  final String title;
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.centerRight,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: label(title, size: 20, weight: FontWeight.w600),
        ),
      ),
      FilterButton(onPressed: onPressed, activeCount: activeCount),
    ],
  );
}
