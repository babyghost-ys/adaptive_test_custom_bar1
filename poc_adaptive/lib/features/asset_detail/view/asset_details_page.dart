import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

class AssetDetails extends StatelessWidget {
  const AssetDetails({super.key, required this.asset});
  final Asset asset;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvestmentBloc, InvestmentState>(
    builder: (context, state) => PageScroll(
      storageKey: asset.symbol,
      children: [
        label(asset.name, color: muted),
        const SizedBox(height: 14),
        label(money(asset.price), size: 44, weight: FontWeight.w600),
        const SizedBox(height: 8),
        label(
          '${asset.change > 0 ? '+' : ''}${asset.change}% today',
          color: asset.change < 0 ? red : green,
        ),
        const SizedBox(height: 30),
        SizedBox(
          height: 210,
          child: CustomPaint(
            painter: ChartPainter(seed: assets.indexOf(asset), filled: true),
          ),
        ),
        const SizedBox(height: 28),
        AdaptiveButton(
          onPressed: () =>
              context.read<InvestmentBloc>().add(WatchToggled(asset.symbol)),
          label: state.watchlist.contains(asset.symbol)
              ? 'Remove from watchlist'
              : 'Add to watchlist',
        ),
        const SizedBox(height: 30),
        section('Your position', ''),
        const SizedBox(height: 16),
        metric(
          'Market value',
          money(asset.price * asset.shares * state.accountScale),
        ),
        const SizedBox(height: 12),
        metric(
          'Shares',
          (asset.shares * state.accountScale).toStringAsFixed(1),
        ),
        const SizedBox(height: 12),
        metric('Average cost', money(asset.price * 0.92)),
        const SizedBox(height: 24),
        label('Illustrative data · No real trades', size: 12, color: muted),
      ],
    ),
  );
}
