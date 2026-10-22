import 'package:flutter/material.dart';
import '../../core/adaptive_style.dart';
import 'ios26_segmented_control.dart';

/// An adaptive segmented control that renders platform-specific styles
///
/// On iOS: Uses the running system’s native UISegmentedControl.
/// On Android: Uses Material SegmentedButton
class AdaptiveSegmentedControl extends StatelessWidget {
  /// Creates an adaptive segmented control
  const AdaptiveSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 36.0,
    this.shrinkWrap = false,
    this.sfSymbols,
    this.iconSize,
    this.iconColor,
    this.textColor,
    this.selectedTextColor,
  });

  /// Segment labels to display, in order
  final List<String> labels;

  /// The index of the selected segment
  final int selectedIndex;

  /// Called when the user selects a segment
  final ValueChanged<int> onValueChanged;

  /// Whether the control is interactive
  final bool enabled;

  /// Tint color for the selected segment
  final Color? color;

  /// Height of the control
  final double height;

  /// Whether the control should shrink to fit content
  final bool shrinkWrap;

  /// Optional SF Symbol names or IconData
  final List<dynamic>? sfSymbols;

  /// Icon size
  final double? iconSize;

  /// Icon color
  final Color? iconColor;

  /// Optional text color for unselected segments.
  final Color? textColor;

  /// Optional text color for the selected segment.
  final Color? selectedTextColor;

  @override
  Widget build(BuildContext context) {
    return switch (AdaptiveStyle.of(context)) {
      AdaptiveStyle.native => IOS26SegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: onValueChanged,
        enabled: enabled,
        color: color,
        height: height,
        shrinkWrap: shrinkWrap,
        icons: sfSymbols,
        iconSize: iconSize,
        iconColor: iconColor,
        textColor: textColor,
        selectedTextColor: selectedTextColor,
      ),
      AdaptiveStyle.material => _buildMaterialSegmentedButton(context),
    };
  }

  Widget _buildMaterialSegmentedButton(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTextColor = textColor ?? theme.colorScheme.onSurface;
    final effectiveSelectedTextColor =
        selectedTextColor ??
        (color != null ? Colors.white : effectiveTextColor);
    final segments = <ButtonSegment<int>>[];

    // Check if using icons
    final useIcons = sfSymbols != null && sfSymbols!.isNotEmpty;
    final itemCount = useIcons ? sfSymbols!.length : labels.length;

    for (int i = 0; i < itemCount; i++) {
      if (useIcons) {
        // Icon mode
        final dynamic icon = sfSymbols![i];
        segments.add(
          ButtonSegment<int>(
            value: i,
            icon: icon is IconData
                ? Icon(icon, size: iconSize ?? 20, color: iconColor)
                : Icon(Icons.circle, size: iconSize ?? 20, color: iconColor),
          ),
        );
      } else {
        // Text mode
        segments.add(
          ButtonSegment<int>(
            value: i,
            label: Text(
              labels[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selectedIndex == i
                    ? effectiveSelectedTextColor
                    : effectiveTextColor,
              ),
            ),
          ),
        );
      }
    }

    final buttonStyle = SegmentedButton.styleFrom(
      minimumSize: Size.fromHeight(height),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      selectedBackgroundColor: color,
      selectedForegroundColor: selectedTextColor,
      foregroundColor: textColor,
    );

    Widget control = SegmentedButton<int>(
      segments: segments,
      selected: {selectedIndex},
      onSelectionChanged: enabled
          ? (Set<int> newSelection) {
              if (newSelection.isNotEmpty) {
                onValueChanged(newSelection.first);
              }
            }
          : null,
      style: buttonStyle,
    );

    if (shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return control;
  }
}
