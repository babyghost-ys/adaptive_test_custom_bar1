import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

Widget section(String title, String trailing) => Row(
  children: [
    label(title, size: 20, weight: FontWeight.w600),
    const Spacer(),
    label(trailing, size: 12, color: muted),
  ],
);
