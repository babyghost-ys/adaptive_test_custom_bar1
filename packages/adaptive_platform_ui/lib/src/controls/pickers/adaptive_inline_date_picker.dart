import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/platform_info.dart';
import '../../native/sheet_platform_view_guard.dart';

/// How [AdaptiveInlineDatePicker] presents dates on iOS.
enum AdaptiveDatePickerStyle {
  /// Spinning wheels, the compact choice for a sheet.
  wheels,

  /// A month calendar grid.
  inline,
}

/// A date picker embedded in the layout, rather than presented as a popup.
///
/// On iOS this is a native `UIDatePicker`, so the system draws, measures and
/// announces it. Elsewhere it is a Material [CalendarDatePicker]. Give it a
/// bounded height, such as an [Expanded] inside a sheet.
class AdaptiveInlineDatePicker extends StatefulWidget {
  const AdaptiveInlineDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    this.style = AdaptiveDatePickerStyle.wheels,
    this.tintColor,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// Called as the user scrolls or taps to a new date.
  final ValueChanged<DateTime> onDateChanged;

  /// iOS only; other platforms always show a calendar.
  final AdaptiveDatePickerStyle style;

  /// Selection colour.
  final Color? tintColor;

  @override
  State<AdaptiveInlineDatePicker> createState() =>
      _AdaptiveInlineDatePickerState();
}

class _AdaptiveInlineDatePickerState extends State<AdaptiveInlineDatePicker> {
  static int _nextId = 0;
  final int _id = _nextId++;
  late final MethodChannel _channel = MethodChannel(
    'adaptive_platform_ui/ios26_date_picker_$_id',
  );
  bool? _lastDark;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'valueChanged') {
        final ms = (call.arguments as Map)['date'] as int;
        widget.onDateChanged(DateTime.fromMillisecondsSinceEpoch(ms));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = _isDark;
    if (_lastDark != null && _lastDark != dark) {
      _channel.invokeMethod<void>('setBrightness', {'isDark': dark});
    }
    _lastDark = dark;
  }

  @override
  void didUpdateWidget(AdaptiveInlineDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstDate != widget.firstDate ||
        oldWidget.lastDate != widget.lastDate ||
        oldWidget.tintColor != widget.tintColor) {
      _channel.invokeMethod<void>('update', _params());
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  bool get _isDark =>
      (CupertinoTheme.maybeBrightnessOf(context) ??
          MediaQuery.platformBrightnessOf(context)) ==
      Brightness.dark;

  Map<String, Object?> _params() => {
    'id': _id,
    'date': widget.initialDate.millisecondsSinceEpoch,
    'minimum': widget.firstDate.millisecondsSinceEpoch,
    'maximum': widget.lastDate.millisecondsSinceEpoch,
    'style': widget.style.name,
    'isDark': _isDark,
    if (widget.tintColor != null) 'tint': widget.tintColor!.toARGB32(),
  };

  @override
  Widget build(BuildContext context) {
    if (PlatformInfo.isIOS && !kIsWeb) {
      return PlatformViewSheetGuard(
        child: UiKitView(
          viewType: 'adaptive_platform_ui/ios26_date_picker',
          creationParams: _params(),
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(),
            ),
            Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
          },
        ),
      );
    }
    return CalendarDatePicker(
      initialDate: widget.initialDate,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      onDateChanged: widget.onDateChanged,
    );
  }
}
