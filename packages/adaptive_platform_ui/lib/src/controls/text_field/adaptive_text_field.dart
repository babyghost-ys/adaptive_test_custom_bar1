import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../core/platform_info.dart';
import '../../native/sheet_platform_view_guard.dart';

/// An adaptive text field that renders platform-specific styles
///
/// On iOS: Uses the running system’s UITextField or UITextView.
/// On Android: Uses Material TextField
class AdaptiveTextField extends StatelessWidget {
  /// Creates an adaptive text field
  const AdaptiveTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.autofillHints,
    this.enabled = true,
    this.readOnly = false,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.inputFormatters,
    this.padding,
    this.decoration,
    this.cupertinoDecoration,
  });

  /// Controls the text being edited.
  final TextEditingController? controller;

  /// Defines the keyboard focus for this widget.
  final FocusNode? focusNode;

  /// A lighter colored placeholder hint that appears on the first line when
  /// the text entry field is empty.
  final String? placeholder;

  /// The type of keyboard to use for editing the text.
  final TextInputType? keyboardType;

  /// The type of action button to use for the keyboard.
  final TextInputAction? textInputAction;

  /// Configures how the platform keyboard will select an uppercase or
  /// lowercase keyboard.
  final TextCapitalization textCapitalization;

  /// The style to use for the text being edited.
  final TextStyle? style;

  /// How the text should be aligned horizontally.
  final TextAlign textAlign;

  /// The maximum number of lines to show at one time.
  final int? maxLines;

  /// The minimum number of lines to occupy when the content spans fewer lines.
  final int? minLines;

  /// The maximum number of characters to allow in the text field.
  final int? maxLength;

  /// Whether to hide the text being edited.
  final bool obscureText;

  /// Whether to enable autocorrection.
  final bool autocorrect;

  /// Whether this text field should focus itself if nothing else is already focused.
  final bool autofocus;

  /// Hints passed to the native iOS content type or Material autofill system.
  final Iterable<String>? autofillHints;

  /// Whether the text field is enabled.
  final bool enabled;

  /// Whether the text field is read-only.
  final bool readOnly;

  /// A widget that appears before the editable part of the text field.
  final Widget? prefix;

  /// A widget that appears after the editable part of the text field.
  final Widget? suffix;

  /// An icon that appears before the editable part of the text field.
  final Widget? prefixIcon;

  /// An icon that appears after the editable part of the text field.
  final Widget? suffixIcon;

  /// Called when the user initiates a change to the TextField's value.
  final ValueChanged<String>? onChanged;

  /// Called when the user indicates that they are done editing the text.
  final ValueChanged<String>? onSubmitted;

  /// Called when the text field is tapped.
  final VoidCallback? onTap;

  /// Optional input validation and formatting overrides.
  final List<TextInputFormatter>? inputFormatters;

  /// Padding around the Material text entry area. UIKit owns iOS insets.
  final EdgeInsetsGeometry? padding;

  /// The decoration to show around the text field (Material only).
  final InputDecoration? decoration;

  /// Retained for source compatibility; UIKit owns iOS field chrome.
  /// Flutter box decorations are not drawn behind the native text control.
  final BoxDecoration? cupertinoDecoration;

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isIOS) {
      return _NativeIOSTextField(configuration: this);
    }

    return _buildMaterialTextField(context);
  }

  Widget _buildMaterialTextField(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      obscureText: obscureText,
      autocorrect: autocorrect,
      autofocus: autofocus,
      autofillHints: autofillHints,
      enabled: enabled,
      readOnly: readOnly,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      inputFormatters: inputFormatters,
      decoration:
          decoration ??
          InputDecoration(
            hintText: placeholder,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            prefix: prefix,
            suffix: suffix,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                padding ??
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
    );
  }
}

/// Internal platform-view bridge; the public field API remains unchanged.
class _NativeIOSTextField extends StatefulWidget {
  const _NativeIOSTextField({required this.configuration});
  final AdaptiveTextField configuration;
  @override
  State<_NativeIOSTextField> createState() => _NativeIOSTextFieldState();
}

class _NativeIOSTextFieldState extends State<_NativeIOSTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  MethodChannel? _channel;
  bool _receivingValue = false;
  bool _receivingFocus = false;
  AdaptiveTextField get field => widget.configuration;

  @override
  void initState() {
    super.initState();
    _controller = field.controller ?? TextEditingController();
    _focusNode = field.focusNode ?? FocusNode();
    _controller.addListener(_sendValue);
    _focusNode.addListener(_sendFocus);
  }

  @override
  void didUpdateWidget(_NativeIOSTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration.controller != field.controller) {
      _controller.removeListener(_sendValue);
      if (oldWidget.configuration.controller == null) _controller.dispose();
      _controller = field.controller ?? TextEditingController();
      _controller.addListener(_sendValue);
      _sendValue();
    }
    if (oldWidget.configuration.focusNode != field.focusNode) {
      _focusNode.removeListener(_sendFocus);
      if (oldWidget.configuration.focusNode == null) _focusNode.dispose();
      _focusNode = field.focusNode ?? FocusNode();
      _focusNode.addListener(_sendFocus);
      _sendFocus();
    }
    _channel?.invokeMethod<void>('configure', _configuration());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel?.invokeMethod<void>('configure', _configuration());
  }

  Map<String, dynamic> _editingValue() => {
    'text': _controller.text,
    'selectionStart': _controller.selection.start < 0
        ? _controller.text.length
        : _controller.selection.start,
    'selectionEnd': _controller.selection.end < 0
        ? _controller.text.length
        : _controller.selection.end,
  };

  Map<String, dynamic> _configuration() {
    final style = DefaultTextStyle.of(context).style.merge(field.style);
    final type = field.keyboardType ?? TextInputType.text;
    return {
      ..._editingValue(),
      'placeholder': field.placeholder,
      'autofillHints': field.autofillHints?.toList(),
      'multiline': field.maxLines != 1,
      'enabled': field.enabled,
      'readOnly': field.readOnly,
      'obscureText': field.obscureText,
      'autocorrect': field.autocorrect,
      'isDark':
          (CupertinoTheme.of(context).brightness ??
              Theme.of(context).brightness) ==
          Brightness.dark,
      'fontSize': style.fontSize ?? 17,
      'fontWeight':
          ((style.fontWeight?.value ?? FontWeight.normal.value) / 100).round() -
          1,
      if (style.color != null)
        'textColor': CupertinoDynamicColor.resolve(
          style.color!,
          context,
        ).toARGB32(),
      'textAlign': field.textAlign.name,
      'capitalization': field.textCapitalization.name,
      'inputAction':
          (field.textInputAction ??
                  (field.maxLines == 1
                      ? TextInputAction.done
                      : TextInputAction.newline))
              .name,
      'keyboard': type.toJson()['name'].toString().split('.').last,
      'decimal': type.decimal ?? false,
      'signed': type.signed ?? false,
    };
  }

  void _sendValue() {
    if (!_receivingValue) {
      _channel?.invokeMethod<void>('setValue', _editingValue());
    }
  }

  void _sendFocus() {
    if (!_receivingFocus) {
      _channel?.invokeMethod<void>('setFocus', {
        'focused': _focusNode.hasFocus,
      });
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    final arguments = call.arguments as Map? ?? const {};
    switch (call.method) {
      case 'editingChanged':
        final oldValue = _controller.value;
        final text = arguments['text'] as String? ?? '';
        var value = TextEditingValue(
          text: text,
          selection: TextSelection(
            baseOffset: arguments['selectionStart'] as int? ?? text.length,
            extentOffset: arguments['selectionEnd'] as int? ?? text.length,
          ),
          composing: arguments['composing'] == true
              ? TextRange(start: 0, end: text.length)
              : TextRange.empty,
        );
        for (final formatter
            in field.inputFormatters ?? const <TextInputFormatter>[]) {
          value = formatter.formatEditUpdate(oldValue, value);
        }
        if (field.maxLength != null && field.maxLength! > 0) {
          value = LengthLimitingTextInputFormatter(
            field.maxLength,
          ).formatEditUpdate(oldValue, value);
        }
        _receivingValue = true;
        _controller.value = value;
        _receivingValue = false;
        if (value.text != text) _sendValue();
        if (oldValue.text != value.text) field.onChanged?.call(value.text);
        break;
      case 'focusChanged':
        _receivingFocus = true;
        if (arguments['focused'] == true) {
          _focusNode.requestFocus();
        } else {
          _focusNode.unfocus();
        }
        _receivingFocus = false;
        break;
      case 'submitted':
        field.onSubmitted?.call(
          arguments['text'] as String? ?? _controller.text,
        );
        if (field.textInputAction == TextInputAction.next) {
          _focusNode.nextFocus();
        }
        break;
      case 'tap':
        field.onTap?.call();
        break;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(field.style);
    final lineHeight = (style.fontSize ?? 17) * (style.height ?? 1.35);
    final lines = field.maxLines == 1
        ? 1
        : (field.minLines ?? field.maxLines ?? 4);
    final height = (lineHeight * lines + 16).clamp(36.0, double.infinity);
    return Focus(
      focusNode: _focusNode,
      child: Row(
        children: [
          if (field.prefix ?? field.prefixIcon case final prefix?) prefix,
          Expanded(
            child: SizedBox(
              height: height,
              child: PlatformViewSheetGuard(
                child: UiKitView(
                  key: ValueKey(field.maxLines == 1),
                  viewType: 'adaptive_platform_ui/text_field',
                  creationParams: _configuration(),
                  creationParamsCodec: const StandardMessageCodec(),
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<EagerGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  onPlatformViewCreated: (id) {
                    _channel?.setMethodCallHandler(null);
                    _channel = MethodChannel(
                      'adaptive_platform_ui/text_field_$id',
                    )..setMethodCallHandler(_handleMethod);
                    _sendValue();
                    if (field.autofocus) _focusNode.requestFocus();
                    _sendFocus();
                  },
                ),
              ),
            ),
          ),
          if (field.suffix ?? field.suffixIcon case final suffix?) suffix,
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _controller.removeListener(_sendValue);
    _focusNode.removeListener(_sendFocus);
    if (field.controller == null) _controller.dispose();
    if (field.focusNode == null) _focusNode.dispose();
    super.dispose();
  }
}
