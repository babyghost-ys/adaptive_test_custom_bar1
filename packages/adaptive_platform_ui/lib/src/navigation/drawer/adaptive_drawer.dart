import '../../style/adaptive_icon.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One destination in an [AdaptiveDrawer].
@immutable
class AdaptiveDrawerItem {
  const AdaptiveDrawerItem({
    required this.id,
    required this.title,
    required this.icon,
  });

  /// Passed to [AdaptiveDrawer.onSelected] when the item is chosen.
  final String id;
  final String title;

  /// Its SF Symbol in the native iOS panel, its Material icon in the
  /// Material drawer.
  final AdaptiveIcon icon;
}

/// A side menu of destinations, given to `AdaptiveScaffold.drawer` and
/// opened with `AdaptiveScaffoldState.openDrawer`.
///
/// iOS shows a native panel above the app, its bars staying in place behind
/// the dimmed backdrop. Elsewhere it is a Material [Drawer].
class AdaptiveDrawer extends StatelessWidget {
  const AdaptiveDrawer({
    super.key,
    this.title,
    this.subtitle,
    required this.sections,
    this.selectedId,
    required this.onSelected,
    this.width,
    this.backgroundColor,
  });

  final String? title;
  final String? subtitle;

  /// Groups of items, divided from each other.
  final List<List<AdaptiveDrawerItem>> sections;

  /// The item shown as current, if any.
  final String? selectedId;

  /// Called with the chosen item's id after the menu closes.
  final ValueChanged<String> onSelected;

  /// Panel width. Null uses 82% of the screen, at most 320.
  final double? width;

  /// Panel colour. Null follows the system.
  final Color? backgroundColor;

  double _width(BuildContext context) =>
      width ?? math.min(320, MediaQuery.sizeOf(context).width * 0.82);

  static const _channel = MethodChannel('adaptive_platform_ui/navigation');

  /// Presents the native iOS panel and completes when it closes.
  Future<void> presentNative(BuildContext context) async {
    final tint = CupertinoDynamicColor.resolve(
      CupertinoTheme.of(context).primaryColor,
      context,
    );
    final selection = await _channel.invokeMethod<String>('presentDrawer', {
      'width': _width(context),
      'title': title,
      'subtitle': subtitle,
      'selected': selectedId,
      'background': backgroundColor?.toARGB32(),
      'tint': tint.toARGB32(),
      'closeLabel': MaterialLocalizations.of(context).closeButtonLabel,
      'sections': [
        for (final section in sections)
          [
            for (final item in section)
              {
                'id': item.id,
                'title': item.title,
                'symbol': item.icon.sfSymbol,
              },
          ],
      ],
    });
    if (selection != null) onSelected(selection);
  }

  /// Closes the native iOS panel without a selection.
  static Future<void> dismissNative() =>
      _channel.invokeMethod<void>('dismissDrawer');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      width: _width(context),
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(title!, style: theme.textTheme.titleMedium),
              ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(subtitle!, style: theme.textTheme.bodySmall),
              ),
            if (title != null || subtitle != null) const SizedBox(height: 16),
            for (final (index, section) in sections.indexed) ...[
              if (index > 0) const Divider(height: 24),
              for (final item in section)
                ListTile(
                  leading: item.icon.build(),
                  title: Text(item.title),
                  selected: item.id == selectedId,
                  shape: const StadiumBorder(),
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(item.id);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
