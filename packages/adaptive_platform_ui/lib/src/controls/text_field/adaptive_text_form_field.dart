import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/adaptive_style.dart';
import 'adaptive_text_field.dart';

/// An adaptive text form field that renders platform-specific styles
///
/// On iOS: Uses UIKit text controls through AdaptiveTextField.
/// On Android: Uses Material TextFormField
class AdaptiveTextFormField extends StatelessWidget {
  /// Creates an adaptive text form field
  const AdaptiveTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.initialValue,
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
    this.enabled = true,
    this.readOnly = false,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onSaved,
    this.validator,
    this.inputFormatters,
    this.padding,
    this.decoration,
    this.autovalidateMode,
    this.onTapOutside,
    this.autofillHints,
  });

  /// Controls the text being edited.
  final TextEditingController? controller;

  /// Defines the keyboard focus for this widget.
  final FocusNode? focusNode;

  /// A lighter colored placeholder hint that appears on the first line when
  /// the text entry field is empty.
  final String? placeholder;

  /// An optional value to initialize the form field to, or null otherwise.
  final String? initialValue;

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

  /// Called when the form is saved.
  final FormFieldSetter<String>? onSaved;

  /// An optional method to validate the input.
  final FormFieldValidator<String>? validator;

  /// Optional input validation and formatting overrides.
  final List<TextInputFormatter>? inputFormatters;

  /// Padding around the text entry area.
  final EdgeInsetsGeometry? padding;

  /// The decoration to show around the text field (Material only).
  final InputDecoration? decoration;

  /// Used to enable/disable this form field auto validation and update its error text.
  final AutovalidateMode? autovalidateMode;

  /// Called when a tap is detected outside the text field.
  final TapRegionCallback? onTapOutside;

  /// Optional autofill hints for the text field.
  final List<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    switch (AdaptiveStyle.of(context)) {
      case AdaptiveStyle.native:
        return _NativeTextFormField(configuration: this);
      case AdaptiveStyle.material:
        return _buildMaterialTextFormField(context);
    }
  }

  Widget _buildMaterialTextFormField(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
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
      enabled: enabled,
      readOnly: readOnly,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      onSaved: onSaved,
      validator: validator,
      inputFormatters: inputFormatters,
      autovalidateMode: autovalidateMode,
      onTapOutside: onTapOutside,
      autofillHints: autofillHints,
      decoration:
          decoration ??
          InputDecoration(
            hintText: placeholder,
            prefixIcon: prefixIcon,
            // Use suffixIcon instead of suffix to prevent extra vertical space
            // Priority: suffixIcon parameter, then suffix parameter (mapped to suffixIcon)
            suffixIcon: suffixIcon ?? suffix,
            prefix: prefix,
            // Don't use suffix in InputDecoration - causes spacing issues
            isDense: true, // Critical for reducing extra space
            suffixIconConstraints: (suffixIcon ?? suffix) != null
                ? const BoxConstraints(minWidth: 48, minHeight: 48)
                : null,
            prefixIconConstraints: prefixIcon != null
                ? const BoxConstraints(minWidth: 48, minHeight: 48)
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                padding ??
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
    );
  }
}

class _NativeTextFormField extends FormField<String> {
  _NativeTextFormField({required this.configuration})
    : super(
        initialValue:
            configuration.controller?.text ?? configuration.initialValue ?? '',
        validator: configuration.validator,
        onSaved: configuration.onSaved,
        enabled: configuration.enabled,
        autovalidateMode:
            configuration.autovalidateMode ?? AutovalidateMode.disabled,
        builder: (state) => (state as _NativeTextFormFieldState).buildControl(),
      );
  final AdaptiveTextFormField configuration;
  @override
  FormFieldState<String> createState() => _NativeTextFormFieldState();
}

class _NativeTextFormFieldState extends FormFieldState<String> {
  late TextEditingController _controller;
  AdaptiveTextFormField get configuration =>
      (widget as _NativeTextFormField).configuration;

  @override
  void initState() {
    super.initState();
    _controller =
        configuration.controller ??
        TextEditingController(text: widget.initialValue);
    _controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (_controller.text != value) didChange(_controller.text);
  }

  @override
  void didUpdateWidget(covariant _NativeTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration.controller != configuration.controller) {
      final previousValue = _controller.value;
      _controller.removeListener(_controllerChanged);
      if (oldWidget.configuration.controller == null) _controller.dispose();
      _controller =
          configuration.controller ??
          TextEditingController.fromValue(previousValue);
      _controller.addListener(_controllerChanged);
      setValue(_controller.text);
    }
  }

  @override
  void reset() {
    _controller.text = widget.initialValue ?? '';
    super.reset();
    configuration.onChanged?.call(_controller.text);
  }

  Widget buildControl() {
    final config = configuration;
    return TextFieldTapRegion(
      onTapOutside: config.onTapOutside,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveTextField(
            controller: _controller,
            focusNode: config.focusNode,
            placeholder: config.placeholder,
            keyboardType: config.keyboardType,
            textInputAction: config.textInputAction,
            textCapitalization: config.textCapitalization,
            style: config.style,
            textAlign: config.textAlign,
            maxLines: config.maxLines,
            minLines: config.minLines,
            maxLength: config.maxLength,
            obscureText: config.obscureText,
            autocorrect: config.autocorrect,
            autofocus: config.autofocus,
            autofillHints: config.autofillHints,
            enabled: config.enabled,
            readOnly: config.readOnly,
            prefix: config.prefix,
            suffix: config.suffix,
            prefixIcon: config.prefixIcon,
            suffixIcon: config.suffixIcon,
            onChanged: (value) {
              didChange(value);
              config.onChanged?.call(value);
            },
            onSubmitted: config.onSubmitted,
            onTap: config.onTap,
            inputFormatters: config.inputFormatters,
            padding: config.padding,
          ),
          if (hasError && errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                errorText!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerChanged);
    if (configuration.controller == null) _controller.dispose();
    super.dispose();
  }
}
