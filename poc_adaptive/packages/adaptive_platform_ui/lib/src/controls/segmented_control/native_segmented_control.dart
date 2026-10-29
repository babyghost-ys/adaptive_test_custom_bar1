import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../native/sheet_platform_view_guard.dart';

/// Native iOS 26 segmented control implementation using platform views
class NativeSegmentedControl extends StatefulWidget {
  const NativeSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.icons,
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

  /// Optional SF Symbol names for icons (iOS only)
  final List<dynamic>? icons;

  /// Icon size (when using icons)
  final double? iconSize;

  /// Icon color (when using icons)
  final Color? iconColor;

  /// Optional text color for unselected segments.
  final Color? textColor;

  /// Optional text color for the selected segment.
  final Color? selectedTextColor;

  @override
  State<NativeSegmentedControl> createState() => _NativeSegmentedControlState();
}

class _NativeSegmentedControlState extends State<NativeSegmentedControl> {
  MethodChannel? _channel;
  Map<String, dynamic>? _desiredConfiguration;
  Map<String, dynamic>? _sentConfiguration;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncConfiguration();
  }

  @override
  void didUpdateWidget(NativeSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncConfiguration();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  Brightness _effectiveBrightness() =>
      CupertinoTheme.of(context).brightness ?? Theme.of(context).brightness;

  void _onPlatformViewCreated(int viewId) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('adaptive_platform_ui/segmented_control/$viewId');
    _channel!.setMethodCallHandler(_handleMethod);
    _sentConfiguration = null;
    _syncConfiguration();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (!mounted || call.method != 'valueChanged') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final index = arguments['index'];
    final itemCount = widget.icons?.isNotEmpty == true
        ? widget.icons!.length
        : widget.labels.length;
    if (index is int && index >= 0 && index < itemCount && widget.enabled) {
      widget.onValueChanged(index);
    }
  }

  bool _sameConfiguration(Map<String, dynamic>? a, Map<String, dynamic> b) {
    if (a == null || a.length != b.length) return false;
    for (final key in b.keys) {
      final left = a[key];
      final right = b[key];
      if (left is List && right is List) {
        if (!listEquals(left, right)) return false;
      } else if (left != right) {
        return false;
      }
    }
    return true;
  }

  void _syncConfiguration() {
    _desiredConfiguration = _buildCreationParams();
    if (_channel != null && !_sending) _sendConfiguration();
  }

  // Keep a single native instance, identified by Flutter's platform-view ID.
  // Coalesce model changes while a channel call is outstanding. Rotation only
  // resizes the view; it does not resend unchanged theme/selection attributes.
  Future<void> _sendConfiguration() async {
    _sending = true;
    try {
      while (mounted && _channel != null) {
        final channel = _channel!;
        final desired = _desiredConfiguration!;
        if (_sameConfiguration(_sentConfiguration, desired)) break;
        await channel.invokeMethod<void>('update', desired);
        if (!mounted || channel != _channel) break;
        _sentConfiguration = desired;
      }
    } catch (error, stack) {
      if (mounted) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'adaptive_platform_ui',
            context: ErrorDescription('updating the native segmented control'),
          ),
        );
      }
    } finally {
      _sending = false;
    }
  }

  int _colorToARGB(Color color) {
    return ((color.a * 255.0).round() & 0xff) << 24 |
        ((color.r * 255.0).round() & 0xff) << 16 |
        ((color.g * 255.0).round() & 0xff) << 8 |
        ((color.b * 255.0).round() & 0xff);
  }

  Map<String, dynamic> _buildThemeParams() {
    final cupertinoTheme = CupertinoTheme.of(context);
    final brightness = _effectiveBrightness();

    final baseTextStyle = DefaultTextStyle.of(context).style;
    final themeTextStyle = cupertinoTheme.textTheme.textStyle;

    final effectiveTextColor =
        widget.textColor ??
        baseTextStyle.color ??
        themeTextStyle.color ??
        (brightness == Brightness.dark
            ? CupertinoColors.white
            : CupertinoColors.black);

    final effectiveSelectedTextColor =
        widget.selectedTextColor ??
        (widget.color != null ? CupertinoColors.white : effectiveTextColor);

    return <String, dynamic>{
      'textColor': _colorToARGB(effectiveTextColor),
      'selectedTextColor': _colorToARGB(effectiveSelectedTextColor),
    };
  }

  Map<String, dynamic> _buildCreationParams() => <String, dynamic>{
    'labels': List<String>.of(widget.labels),
    'sfSymbols': widget.icons == null ? null : List<dynamic>.of(widget.icons!),
    'selectedIndex': widget.selectedIndex,
    'enabled': widget.enabled,
    'isDark': _effectiveBrightness() == Brightness.dark,
    'tintColor': widget.color == null ? null : _colorToARGB(widget.color!),
    'iconSize': widget.iconSize,
    'iconColor': widget.iconColor == null
        ? null
        : _colorToARGB(widget.iconColor!),
    ..._buildThemeParams(),
  };

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      Widget control = PlatformViewSheetGuard(
        child: UiKitView(
          viewType: 'adaptive_platform_ui/ios26_segmented_control',
          creationParams: _buildCreationParams(),
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            Factory<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(),
            ),
          },
        ),
      );

      // Wrap in SizedBox for height
      control = SizedBox(height: widget.height, child: control);

      // Center if shrinkWrap is true (but don't use IntrinsicWidth with UiKitView)
      if (widget.shrinkWrap) {
        control = Center(child: control);
      }

      return control;
    }

    // Fallback for non-iOS (should not reach here in normal usage)
    final Map<int, Widget> children = {};
    for (int i = 0; i < widget.labels.length; i++) {
      children[i] = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          widget.labels[i],
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      );
    }

    Widget control = CupertinoSegmentedControl<int>(
      children: children,
      groupValue: widget.selectedIndex,
      onValueChanged: widget.enabled ? widget.onValueChanged : (_) {},
    );

    if (widget.shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return SizedBox(height: widget.height, child: control);
  }
}
