import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/chart_painter.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

class AssetRow extends StatelessWidget {
  const AssetRow({
    super.key,
    required this.asset,
    this.holding = false,
    this.scale = 1,
    this.onTap,
    this.selected = false,
  });
  final Asset asset;
  final bool holding;
  final double scale;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE6E5DF))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: selected ? const Color(0xFFEFEEE9) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ?? () => context.push('/asset/${asset.symbol}'),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: 13,
                horizontal: holding ? 8 : 0,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(asset.color),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: label(
                      asset.symbol == 'AAPL'
                          ? 'a'
                          : asset.symbol.substring(0, 1),
                      size: 22,
                      color: Colors.white,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label(asset.symbol, weight: FontWeight.w600),
                        const SizedBox(height: 4),
                        Text(
                          holding
                              ? '${(asset.shares * scale).toStringAsFixed(1)} shares'
                              : asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 25,
                    child: CustomPaint(
                      painter: ChartPainter(
                        seed: assets.indexOf(asset),
                        color: asset.change < 0 ? red : green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      label(
                        money(
                          holding
                              ? asset.price * asset.shares * scale
                              : asset.price,
                        ),
                        weight: FontWeight.w500,
                      ),
                      const SizedBox(height: 4),
                      label(
                        '${asset.change > 0 ? '+' : ''}${asset.change.toStringAsFixed(2)}%',
                        color: asset.change < 0 ? red : green,
                        size: 12,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
