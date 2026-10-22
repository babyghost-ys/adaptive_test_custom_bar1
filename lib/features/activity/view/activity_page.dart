import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/core/widgets/section.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';

class Activity extends StatelessWidget {
  const Activity({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'activity',
    children: [
      section('Recent activity', 'Demo'),
      const SizedBox(height: 20),
      for (var i = 0; i < 12; i++)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE5EBE1),
            child: Icon(
              i % 3 == 0 ? Icons.south_west : Icons.add,
              color: green,
              size: 20,
            ),
          ),
          title: label(
            i % 3 == 0 ? 'Dividend · VOO' : 'Bought ${assets[i % 6].symbol}',
            weight: FontWeight.w500,
          ),
          subtitle: label('Oct ${19 - i} · Personal', size: 12, color: muted),
          trailing: label(
            i % 3 == 0 ? '+\$128.40' : money(assets[i % 6].price),
            size: 14,
          ),
        ),
    ],
  );
}
