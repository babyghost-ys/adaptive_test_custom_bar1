import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      const Center(
        child: CircleAvatar(
          radius: 42,
          backgroundColor: red,
          child: Text(
            'PL',
            style: TextStyle(color: Colors.white, fontSize: 28),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Center(child: label('Peter Leung', size: 25, weight: FontWeight.w600)),
      const SizedBox(height: 32),
      metric('Account', 'Demo investor'),
      const SizedBox(height: 12),
      metric('Base currency', 'USD'),
    ],
  );
}
