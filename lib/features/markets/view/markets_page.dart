import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';

class Markets extends StatelessWidget {
  const Markets({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'markets',
    children: [
      section('Market overview', 'Demo prices'),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: metric('S&P 500', '5,892.16')),
          const SizedBox(width: 12),
          Expanded(child: metric('NASDAQ', '18,421.09')),
        ],
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 150,
        child: CustomPaint(painter: ChartPainter(seed: 7, filled: true)),
      ),
      const SizedBox(height: 24),
      section('Explore', 'USD'),
      const SizedBox(height: 8),
      ...assets.map((a) => AssetRow(asset: a)),
    ],
  );
}
