import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/investment/widgets/asset_row.dart';

class SearchContent extends StatefulWidget {
  const SearchContent({super.key});
  @override
  State<SearchContent> createState() => _SearchContentState();
}

class _SearchContentState extends State<SearchContent> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final matches = assets.where(
      (a) =>
          needle.isEmpty ||
          a.symbol.toLowerCase().contains(needle) ||
          a.name.toLowerCase().contains(needle),
    );
    return PageScroll(
      storageKey: 'search',
      children: [
        CupertinoSearchTextField(
          autofocus: true,
          autocorrect: false,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: const Icon(Icons.cancel),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        ...matches.map((a) => AssetRow(asset: a)),
      ],
    );
  }
}
