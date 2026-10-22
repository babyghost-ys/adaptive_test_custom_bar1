import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';

/// Opens a filter sheet. Shows how many filters are active.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.onPressed,
    this.activeCount = 0,
  });
  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: active ? 'Filters, $activeCount active' : 'Filters',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: active,
            label: Text('$activeCount'),
            backgroundColor: red,
            child: Icon(
              Icons.tune_rounded,
              size: 24,
              color: active ? red : ink,
            ),
          ),
        ),
      ),
    );
  }
}
