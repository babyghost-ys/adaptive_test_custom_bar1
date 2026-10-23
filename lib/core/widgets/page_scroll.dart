import 'package:flutter/material.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.storageKey,
    this.header,
  });
  final List<Widget> children;
  final String? storageKey;

  /// Runs edge to edge above the padded children.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 28;
    if (header == null) {
      return ListView(
        key: PageStorageKey(storageKey ?? 'page'),
        padding: EdgeInsets.fromLTRB(24, 28, 24, bottom),
        children: children,
      );
    }
    return ListView(
      key: PageStorageKey(storageKey ?? 'page'),
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        header!,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
