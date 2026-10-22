import 'package:flutter/material.dart';
import '../../core/adaptive_style.dart';
import 'ios26_switch.dart';

/// An adaptive switch that renders platform-specific switch styles
///
/// On iOS: Uses the running system’s native UISwitch.
/// On Android: Uses Material Design Switch
///
/// Example:
/// ```dart
/// bool _value = false;
///
/// AdaptiveSwitch(
///   value: _value,
///   onChanged: (bool newValue) {
///     setState(() {
///       _value = newValue;
///     });
///   },
/// )
/// ```
class AdaptiveSwitch extends StatelessWidget {
  /// Creates an adaptive switch
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  /// Whether this switch is on or off
  final bool value;

  /// Called when the user toggles the switch on or off
  ///
  /// The switch passes the new value to the callback but does not actually
  /// change state until the parent widget rebuilds the switch with the new
  /// value.
  ///
  /// If null, the switch will be displayed as disabled.
  final ValueChanged<bool>? onChanged;

  /// The color to use when this switch is on
  ///
  /// On iOS: Uses the color for the track when on
  /// On Android: Uses the color for the track
  final Color? activeColor;

  /// The color of the thumb (handle)
  ///
  /// On iOS: The color of the circular knob
  /// On Android: The color of the circular knob
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    switch (AdaptiveStyle.of(context)) {
      case AdaptiveStyle.native:
        // iOS 26+ - Use native iOS 26 switch
        return IOS26Switch(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
          thumbColor: thumbColor,
        );
      case AdaptiveStyle.material:
        // Android - Use Material Design Switch
        return Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: thumbColor != null
              ? WidgetStateProperty.all(thumbColor)
              : null,
          trackColor: activeColor != null
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return activeColor;
                  }
                  return null;
                })
              : null,
        );
    }
  }
}
