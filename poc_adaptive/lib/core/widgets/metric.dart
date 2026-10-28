import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

Widget metric(String title, String value) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      label(title, color: muted, size: 12),
      const SizedBox(height: 9),
      FittedBox(child: label(value, size: 20, weight: FontWeight.w600)),
    ],
  ),
);
