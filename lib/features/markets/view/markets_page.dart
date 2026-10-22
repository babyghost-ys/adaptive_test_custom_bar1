import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/markets/view/market_filter_sheet.dart';

class Markets extends StatefulWidget {
  const Markets({super.key});
  @override
  State<Markets> createState() => _MarketsState();
}

class _MarketsState extends State<Markets> {
  MarketFilter filter = const MarketFilter();

  Future<void> openFilters() async {
    final result = await showMarketFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

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
      FilterSectionHeader(
        title: 'Explore',
        onPressed: openFilters,
        activeCount: filter.activeCount,
      ),
      const SizedBox(height: 8),
      ...filter.apply(assets).map((a) => AssetRow(asset: a)),
      if (filter.apply(assets).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Icon(Icons.search_off_rounded, size: 40, color: muted),
        ),
    ],
  );
}
