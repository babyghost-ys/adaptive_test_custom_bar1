import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/asset_detail/view/asset_details_page.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/portfolio_selection.dart';
import 'package:native_widgets_on_duo/features/portfolio/view/holdings_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/portfolio/view/portfolio_columns.dart';

class PortfolioTab extends StatelessWidget {
  const PortfolioTab({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvestmentBloc, InvestmentState>(
        builder: (context, state) => Portfolio(state: state),
      );
}

class Portfolio extends StatefulWidget {
  const Portfolio({
    super.key,
    required this.state,
    this.origin,
    this.columnSymbol,
    this.onColumnSelect,
  });
  final InvestmentState state;
  final PortfolioAssetOrigin? origin;
  final String? columnSymbol;
  final ValueChanged<Asset>? onColumnSelect;
  @override
  State<Portfolio> createState() => _PortfolioState();
}

class _PortfolioState extends State<Portfolio> {
  late final ValueNotifier<HoldingsFilter> filterState;
  late final ScrollController scrollController;
  String? selectedSymbol;

  @override
  void initState() {
    super.initState();
    filterState =
        widget.origin?.filter ?? ValueNotifier(const HoldingsFilter());
    filterState.addListener(_filterChanged);
    scrollController = ScrollController(
      initialScrollOffset: widget.origin?.scrollOffset ?? 0,
    );
  }

  void _filterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    filterState.removeListener(_filterChanged);
    if (widget.origin == null) filterState.dispose();
    scrollController.dispose();
    super.dispose();
  }

  InvestmentState get state => widget.state;

  Future<void> openFilters() async {
    final result = await showHoldingsFilterSheet(
      context,
      filterState.value,
      scale: state.accountScale,
    );
    if (result != null && mounted) filterState.value = result;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final holdings = filterState.value.apply(assets, state.accountScale);
      if (widget.onColumnSelect != null) {
        final selected = holdings
            .where((asset) => asset.symbol == widget.columnSymbol)
            .firstOrNull;
        return portfolioContent(holdings, true, selected);
      }
      final split = constraints.maxWidth >= 540;
      final selected = holdings
          .where((asset) => asset.symbol == selectedSymbol)
          .firstOrNull;
      if (!split || selected == null)
        return portfolioContent(holdings, split, null);

      return PortfolioColumns(
        portfolio: portfolioContent(holdings, true, selected),
        detail: AssetDetails(asset: selected),
      );
    },
  );

  Widget portfolioContent(
    List<Asset> holdings,
    bool split,
    Asset? selected,
  ) => PageScroll(
    storageKey: 'portfolio',
    controller: scrollController,
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
        activeCount: filterState.value.activeCount,
      ),
      const SizedBox(height: 10),
      ...holdings.map(
        (asset) => AssetRow(
          asset: asset,
          holding: true,
          scale: state.accountScale,
          selected: selected?.symbol == asset.symbol,
          onTap: () {
            if (widget.onColumnSelect != null) {
              widget.onColumnSelect!(asset);
            } else if (split) {
              setState(() => selectedSymbol = asset.symbol);
            } else {
              selectedSymbol = null;
              context.push(
                '/asset/${asset.symbol}',
                extra: PortfolioAssetOrigin(
                  filter: filterState,
                  scrollOffset: scrollController.hasClients
                      ? scrollController.offset
                      : 0,
                ),
              );
            }
          },
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
