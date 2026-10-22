import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';

class StatementsContent extends StatelessWidget {
  const StatementsContent({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      for (final month in ['September', 'August', 'July'])
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          leading: const Icon(Icons.description_outlined, color: red),
          title: label('$month 2026'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/statements/$month'),
        ),
    ],
  );
}
