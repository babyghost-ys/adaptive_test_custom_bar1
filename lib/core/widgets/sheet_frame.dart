import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// The shell of a filter sheet's content: a title with a reset icon (or a
/// close icon, given [onClose]), the caller's [children], and a full-width
/// apply button showing [count]. It takes its natural height, so a sheet can
/// fit it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.children,
    required this.count,
    required this.onApply,
    this.onReset,
    this.onClose,
  });

  final List<Widget> children;
  final int count;
  final VoidCallback onApply;

  /// Null disables the reset icon.
  final VoidCallback? onReset;

  /// Shows a close icon in place of the reset icon, for a sheet that tapping
  /// outside does not close.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: label('Filters', size: 22, weight: FontWeight.w600),
                ),
                IconButton(
                  onPressed: onClose ?? onReset,
                  icon: Icon(
                    onClose == null
                        ? Icons.restart_alt_rounded
                        : Icons.close_rounded,
                  ),
                  color: ink,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: onApply,
                icon: const Icon(Icons.check_rounded),
                label: Text('$count'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// An icon and title with a native switch at the trailing edge. One fixed
/// row at any width, so a sheet holding it keeps its height when the screen
/// turns.
class SwitchLine extends StatelessWidget {
  const SwitchLine({
    super.key,
    required this.icon,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: muted),
        const SizedBox(width: 14),
        Expanded(child: label(text, size: 17)),
        AdaptiveSwitch(value: value, activeColor: red, onChanged: onChanged),
      ],
    ),
  );
}
