import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';

Text label(
  String text, {
  double size = 15,
  Color color = ink,
  FontWeight weight = FontWeight.w400,
}) => Text(
  text,
  style: TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: size > 30 ? -1.5 : -0.2,
  ),
);
