import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';

/// The shell of a filter sheet's content: a title with a reset icon, the
/// caller's [children], and a full-width apply button showing [count]. It
/// takes its natural height, so a sheet can fit it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.children,
    required this.count,
    required this.onApply,
    this.onReset,
  });

  final List<Widget> children;
  final int count;
  final VoidCallback onApply;

  /// Null disables the reset icon.
  final VoidCallback? onReset;

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
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
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

/// A row of single-choice or multi-choice chips.
class ChipGroup<T> extends StatelessWidget {
  const ChipGroup({
    super.key,
    required this.options,
    required this.isSelected,
    required this.onTap,
  });

  final List<(T, IconData, String)> options;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (value, icon, text) in options)
        ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(text),
          selected: isSelected(value),
          showCheckmark: false,
          onSelected: (_) => onTap(value),
        ),
    ],
  );
}

/// A titled section that opens and closes, animating its height. The open
/// state belongs to the caller, so the widget can stay stateless.
class OpenSection extends StatelessWidget {
  const OpenSection({
    super.key,
    required this.open,
    required this.icon,
    required this.child,
  });

  final ValueNotifier<bool> open;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: open,
    builder: (context, isOpen, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => open.value = !isOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: muted),
                const Spacer(),
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: muted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Padding(padding: const EdgeInsets.only(bottom: 8), child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );
}
