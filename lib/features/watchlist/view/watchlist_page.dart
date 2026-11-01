import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/view/watchlist_filter_sheet.dart';

class WatchlistTab extends StatelessWidget {
  const WatchlistTab({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvestmentBloc, InvestmentState>(
        builder: (context, state) => Watchlist(state: state),
      );
}

class Watchlist extends StatefulWidget {
  const Watchlist({super.key, required this.state});
  final InvestmentState state;
  @override
  State<Watchlist> createState() => _WatchlistState();
}

class _WatchlistState extends State<Watchlist> {
  WatchlistFilter filter = const WatchlistFilter();
  int selectedSection = 0;

  InvestmentState get state => widget.state;

  Future<void> openFilters() async {
    final result = await showWatchlistFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'watchlist',
    children: [
      AdaptiveSegmentedControl(
        labels: const ['Following', 'Discover'],
        selectedIndex: selectedSection,
        onValueChanged: (index) => setState(() => selectedSection = index),
      ),
      const SizedBox(height: 24),
      FilterSectionHeader(
        title: selectedSection == 0 ? 'Following' : 'Discover',
        onPressed: openFilters,
        activeCount: filter.activeCount,
      ),
      const SizedBox(height: 12),
      ...assets
          .where(
            (a) =>
                state.watchlist.contains(a.symbol) == (selectedSection == 0) &&
                filter.allows(a),
          )
          .map((a) => AssetRow(asset: a)),
    ],
  );
}
