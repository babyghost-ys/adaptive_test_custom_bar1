import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/view/holdings_filter_sheet.dart';

class PortfolioTab extends StatelessWidget {
  const PortfolioTab({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvestmentBloc, InvestmentState>(
        builder: (context, state) => Portfolio(state: state),
      );
}

class Portfolio extends StatefulWidget {
  const Portfolio({super.key, required this.state});
  final InvestmentState state;
  @override
  State<Portfolio> createState() => _PortfolioState();
}

class _PortfolioState extends State<Portfolio> {
  HoldingsFilter filter = const HoldingsFilter();

  InvestmentState get state => widget.state;

  Future<void> openFilters() async {
    final result = await showHoldingsFilterSheet(
      context,
      filter,
      scale: state.accountScale,
    );
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'portfolio',
    children: [
      Row(
        children: [
          label(state.accountName, color: muted),
          const Spacer(),
          label('USD', size: 12, color: muted),
        ],
      ),
      const SizedBox(height: 10),
      FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: label(money(state.balance), size: 44, weight: FontWeight.w600),
      ),
      const SizedBox(height: 9),
      Row(
        children: [
          const Icon(Icons.north_east, size: 15, color: green),
          const SizedBox(width: 4),
          label(
            '+${money(state.balance * [0.008, 0.025, 0.0842, 0.146, 0.218][state.range])} (${[0.8, 2.5, 8.42, 14.6, 21.8][state.range]}%)',
            color: green,
            size: 14,
            weight: FontWeight.w500,
          ),
        ],
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 170,
        child: CustomPaint(
          painter: ChartPainter(seed: state.range, filled: true),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          5,
          (i) => Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.read<InvestmentBloc>().add(RangeSelected(i)),
              child: Semantics(
                button: true,
                selected: i == state.range,
                label: [
                  'One day',
                  'One week',
                  'One month',
                  'One year',
                  'All time',
                ][i],
                child: Center(
                  heightFactor: 1,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 64),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: i == state.range ? ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: label(
                      ['1D', '1W', '1M', '1Y', 'ALL'][i],
                      size: 12,
                      color: i == state.range ? Colors.white : muted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(child: metric('Invested', money(state.invested))),
            const SizedBox(width: 12),
            Expanded(child: metric('Available cash', money(state.cash))),
          ],
        ),
      ),
      const SizedBox(height: 32),
      FilterSectionHeader(
        title: 'Holdings',
        onPressed: openFilters,
        activeCount: filter.activeCount,
      ),
      const SizedBox(height: 10),
      ...filter
          .apply(assets, state.accountScale)
          .map(
            (asset) => AssetRow(
              asset: asset,
              holding: true,
              scale: state.accountScale,
            ),
          ),
      const SizedBox(height: 28),
      section('Allocation', ''),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                flex: [51, 42, 7][i],
                child: Container(
                  height: 10,
                  color: [
                    red,
                    const Color(0xFFCCA68B),
                    const Color(0xFFDCD9D0),
                  ][i],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          label('Stocks 51%', size: 12),
          label('ETFs 42%', size: 12),
          label('Cash 7%', size: 12),
        ],
      ),
    ],
  );
}
