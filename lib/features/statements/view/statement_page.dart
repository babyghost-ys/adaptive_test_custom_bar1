import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';

class StatementContent extends StatelessWidget {
  const StatementContent({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      metric('Closing balance', '\$118,473.20'),
      const SizedBox(height: 12),
      metric('Dividends received', '\$128.40'),
      const SizedBox(height: 20),
      label('Demo statement', color: muted, size: 12),
    ],
  );
}
