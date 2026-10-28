import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/metric.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';

class PreferencesContent extends StatefulWidget {
  const PreferencesContent({super.key});
  @override
  State<PreferencesContent> createState() => _PreferencesContentState();
}

class _PreferencesContentState extends State<PreferencesContent> {
  bool alerts = true;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      Row(
        children: [
          Expanded(child: label('Price alerts')),
          AdaptiveSwitch(
            value: alerts,
            onChanged: (v) => setState(() => alerts = v),
          ),
        ],
      ),
      const SizedBox(height: 24),
      metric('Currency', 'USD'),
      const SizedBox(height: 12),
      metric('Environment', 'Demo'),
    ],
  );
}
