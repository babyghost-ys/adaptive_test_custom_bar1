import 'package:flutter/material.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.storageKey,
    this.header,
    this.controller,
  });
  final List<Widget> children;
  final String? storageKey;
  final ScrollController? controller;

  /// Runs edge to edge above the padded children.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    // Side insets are left here when the body runs under the camera housing
    // of an iPhone in landscape, so the header can reach the edges.
    final insets = MediaQuery.paddingOf(context);
    final bottom = insets.bottom + 28;
    final left = insets.left + 24;
    final right = insets.right + 24;
    // Applied here, so rows that pad themselves to the safe area (a
    // ListTile does) do not add the side insets a second time.
    Widget consumed(Widget child) => MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeRight: true,
      child: child,
    );
    if (header == null) {
      return consumed(
        ListView(
          key: PageStorageKey(storageKey ?? 'page'),
          controller: controller,
          padding: EdgeInsets.fromLTRB(left, 28, right, bottom),
          children: children,
        ),
      );
    }
    return ListView(
      key: PageStorageKey(storageKey ?? 'page'),
      controller: controller,
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        header!,
        consumed(
          Padding(
            padding: EdgeInsets.fromLTRB(left, 28, right, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
