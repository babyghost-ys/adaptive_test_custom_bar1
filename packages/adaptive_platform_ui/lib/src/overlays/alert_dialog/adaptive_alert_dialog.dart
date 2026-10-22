import '../../style/adaptive_icon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/adaptive_style.dart';
import 'native_alert_dialog.dart';

export 'native_alert_dialog.dart' show AlertAction, AlertActionStyle;

/// Configuration for text input in alert dialog
class AdaptiveAlertDialogInput {
  /// Creates a text input configuration for alert dialog
  const AdaptiveAlertDialogInput({
    required this.placeholder,
    this.initialValue,
    this.keyboardType,
    this.obscureText = false,
    this.maxLength,
  });

  /// Placeholder text for the text field
  final String placeholder;

  /// Initial value for the text field
  final String? initialValue;

  /// Keyboard type for the text field
  final TextInputType? keyboardType;

  /// Whether to obscure the text (for passwords)
  final bool obscureText;

  /// Maximum length of the text input
  final int? maxLength;
}

/// An adaptive alert dialog that renders platform-specific styles
///
/// On iOS: Uses the running system’s native UIAlertController.
/// On Android: Uses Material AlertDialog
class AdaptiveAlertDialog {
  AdaptiveAlertDialog._();

  /// Shows a standard adaptive alert dialog
  ///
  /// [icon] shows its SF Symbol in the native alert and its Material icon
  /// in the Material dialog.
  ///
  /// Returns a Future that resolves to void when the dialog is dismissed
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    required List<AlertAction> actions,
    AdaptiveIcon? icon,
    double? iconSize,
    Color? iconColor,
    String? oneTimeCode,
  }) {
    switch (AdaptiveStyle.of(context)) {
      case AdaptiveStyle.native:
        // iOS 26+ - Use native iOS 26 alert dialog

        return showCupertinoDialog<void>(
          context: context,
          barrierColor: CupertinoColors.transparent,
          builder: (context) => NativeAlertDialog(
            title: title,
            message: message,
            actions: actions,
            icon: icon?.sfSymbol,
            iconSize: iconSize,
            iconColor: iconColor,
            oneTimeCode: oneTimeCode,
            input: null, // No input for standard dialog
          ),
        );
      case AdaptiveStyle.material:
        // Android - Use Material Design AlertDialog
        return _showMaterialDialog(
          context: context,
          title: title,
          message: message,
          actions: actions,
          icon: icon,
          iconSize: iconSize,
          iconColor: iconColor,
          oneTimeCode: oneTimeCode,
          input: null,
        );
    }
  }

  /// Shows an adaptive alert dialog with text input
  ///
  /// The [input] parameter configures the text input field.
  /// Returns a Future containing the entered text or null if cancelled
  static Future<String?> inputShow({
    required BuildContext context,
    required String title,
    String? message,
    required List<AlertAction> actions,
    required AdaptiveAlertDialogInput input,
    AdaptiveIcon? icon,
    double? iconSize,
    Color? iconColor,
  }) {
    switch (AdaptiveStyle.of(context)) {
      case AdaptiveStyle.native:
        // iOS 26+ - Use native iOS 26 alert dialog with input

        return showCupertinoDialog<String?>(
          context: context,
          barrierColor: CupertinoColors.transparent,
          builder: (context) => NativeAlertDialog(
            title: title,
            message: message,
            actions: actions,
            icon: icon?.sfSymbol,
            iconSize: iconSize,
            iconColor: iconColor,
            oneTimeCode: null,
            input: input,
          ),
        );
      case AdaptiveStyle.material:
        // Android - Use Material Design AlertDialog with TextField
        return _showMaterialDialog<String?>(
          context: context,
          title: title,
          message: message,
          actions: actions,
          icon: icon,
          iconSize: iconSize,
          iconColor: iconColor,
          oneTimeCode: null,
          input: input,
        );
    }
  }

  /// Internal helper method for showing Material dialogs
  static Future<T?> _showMaterialDialog<T>({
    required BuildContext context,
    required String title,
    String? message,
    required List<AlertAction> actions,
    AdaptiveIcon? icon,
    double? iconSize,
    Color? iconColor,
    String? oneTimeCode,
    AdaptiveAlertDialogInput? input,
  }) {
    final textController = TextEditingController(text: input?.initialValue);

    return showDialog<T>(
      context: context,
      builder: (context) {
        // Build custom content if icon, OTP, or textfield is present
        Widget? contentWidget;
        final hasMaterialIcon = icon != null && iconSize != null;
        final hasOtpCode = oneTimeCode != null;
        final hasInput = input != null;
        final hasContentBelowMessage = hasOtpCode || hasInput;
        if (icon != null ||
            oneTimeCode != null ||
            message != null ||
            input != null) {
          contentWidget = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasMaterialIcon) ...[
                icon.build(
                  size: iconSize,
                  color: iconColor ?? Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
              ],
              if (message != null) ...[
                Text(message, textAlign: TextAlign.center),
                if (hasContentBelowMessage) const SizedBox(height: 16),
              ],
              if (hasOtpCode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    oneTimeCode,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (input != null) ...[
                TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    hintText: input.placeholder,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: input.keyboardType,
                  obscureText: input.obscureText,
                  maxLength: input.maxLength,
                  autofocus: true,
                ),
              ],
            ],
          );
        }

        // Separate actions by type
        final normalActions = actions
            .where((a) => a.style != AlertActionStyle.cancel)
            .toList();
        final cancelAction = actions.firstWhere(
          (a) => a.style == AlertActionStyle.cancel,
          orElse: () => AlertAction(
            title: MaterialLocalizations.of(context).cancelButtonLabel,
            onPressed: () {},
            style: AlertActionStyle.cancel,
          ),
        );

        return AlertDialog(
          title: Text(title),
          content: contentWidget,
          // Material convention: dismissive action on the left, confirming
          // action on the right — so the cancel button comes first.
          actions: [
            if (actions.any((a) => a.style == AlertActionStyle.cancel))
              TextButton(
                onPressed: () {
                  // Cancel button always returns null for input dialogs
                  if (input != null) {
                    Navigator.of(context).pop<String?>(null);
                  } else {
                    Navigator.of(context).pop();
                  }
                  cancelAction.onPressed();
                },
                child: Text(cancelAction.title),
              ),
            ...normalActions.map((action) {
              Color? buttonColor;
              switch (action.style) {
                case AlertActionStyle.destructive:
                  buttonColor = Colors.red;
                  break;
                case AlertActionStyle.primary:
                  buttonColor = Theme.of(context).colorScheme.primary;
                  break;
                case AlertActionStyle.success:
                  buttonColor = Colors.green;
                  break;
                case AlertActionStyle.warning:
                  buttonColor = Colors.orange;
                  break;
                case AlertActionStyle.info:
                  buttonColor = Colors.blue;
                  break;
                default:
                  buttonColor = null;
              }

              return TextButton(
                onPressed: action.enabled
                    ? () {
                        if (input != null) {
                          // Input dialog - return the text
                          final text = textController.text.trim();
                          Navigator.of(
                            context,
                          ).pop<String?>(text.isNotEmpty ? text : null);
                        } else {
                          // Normal dialog - just close
                          Navigator.of(context).pop();
                        }
                        action.onPressed();
                      }
                    : null,
                style: buttonColor != null
                    ? TextButton.styleFrom(foregroundColor: buttonColor)
                    : null,
                child: Text(action.title),
              );
            }),
          ],
        );
      },
    );
  }
}
