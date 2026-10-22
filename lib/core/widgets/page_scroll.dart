import 'package:flutter/material.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children, this.storageKey});
  final List<Widget> children;
  final String? storageKey;
  @override
  Widget build(BuildContext context) => ListView(
    key: PageStorageKey(storageKey ?? 'page'),
    padding: EdgeInsets.fromLTRB(
      24,
      28,
      24,
      MediaQuery.paddingOf(context).bottom + 28,
    ),
    children: children,
  );
}
