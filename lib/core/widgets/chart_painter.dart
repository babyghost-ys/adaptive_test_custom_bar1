import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';

class ChartPainter extends CustomPainter {
  ChartPainter({this.seed = 0, this.filled = false, this.color = red});
  final int seed;
  final bool filled;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final random = math.Random(seed + 41);
    for (var i = 0; i <= 60; i++) {
      final x = size.width * i / 60;
      final trend = 0.8 - i / 60 * 0.58;
      final y =
          size.height *
          (trend +
              math.sin(i * 0.64 + seed) * 0.06 +
              (random.nextDouble() - 0.5) * 0.1);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    if (filled) {
      final grid = Paint()
        ..color = const Color(0xFFE6E4DE)
        ..strokeWidth = 1;
      for (var i = 1; i <= 3; i++) {
        canvas.drawLine(
          Offset(0, size.height * i / 4),
          Offset(size.width, size.height * i / 4),
          grid,
        );
      }
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = filled ? 2.4 : 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant ChartPainter old) =>
      old.seed != seed || old.color != color || old.filled != filled;
}
