import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';

class WatchlistTab extends StatelessWidget {
  const WatchlistTab({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvestmentBloc, InvestmentState>(
        builder: (context, state) => Watchlist(state: state),
      );
}

class Watchlist extends StatelessWidget {
  const Watchlist({super.key, required this.state});
  final InvestmentState state;
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'watchlist',
    children: [
      section('Following', '${state.watchlist.length} assets'),
      const SizedBox(height: 12),
      ...assets
          .where((a) => state.watchlist.contains(a.symbol))
          .map((a) => AssetRow(asset: a)),
      const SizedBox(height: 28),
      label('Discover', size: 20, weight: FontWeight.w600),
      ...assets
          .where((a) => !state.watchlist.contains(a.symbol))
          .map((a) => AssetRow(asset: a)),
    ],
  );
}
