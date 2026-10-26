import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialPageRoute, PopScope, showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A UIKit sheet with its own Flutter engine and native platform views.
///
/// On iOS, [show] sends a named route and codec-safe arguments to the app's
/// `nativeSheetMain` entrypoint. That entrypoint calls [bootstrap] and builds
/// the route inside [AdaptiveNativeSheetContent]. The page and every visible
/// sheet keep their own rendering surface throughout rotation and scrolling.
///
/// Widgets, closures, notifiers and blocs cannot cross engine boundaries.
/// Construct the sheet's state in its entrypoint and use [decodeResult] to
/// restore the result in the caller. [builder] is used on other platforms.
class AdaptiveNativeSheet {
  AdaptiveNativeSheet._();

  static const _channel = MethodChannel('adaptive_platform_ui/widget_sheet');
  static bool _hosted = false;
  static bool _closing = false;
  static Object? Function(Object?) _encodeResult = (value) => value;

  /// Called once by `nativeSheetMain`, before building the sheet app.
  ///
  /// The returned map contains `route`, `arguments`, `detents`,
  /// `backgroundColor` and `brightness`. [encodeResult] converts the value
  /// passed to [pop] into StandardMessageCodec-compatible data.
  static Future<Map<String, dynamic>> bootstrap({
    required Object? Function(Object?) encodeResult,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    _hosted = true;
    _encodeResult = encodeResult;
    final configuration = await _channel.invokeMapMethod<String, dynamic>(
      'bootstrap',
    );
    if (configuration == null) {
      throw StateError('The native sheet has no configuration.');
    }
    return configuration;
  }

  /// Shows a native sheet and completes after it has been dismissed.
  ///
  /// [route] is required for native presentation. [arguments] and the encoded
  /// result must be supported by StandardMessageCodec. [decodeResult] is only
  /// used for a non-null native result; [builder] supplies the same content
  /// directly for Material presentation.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? route,
    Object? arguments,
    T Function(Object)? decodeResult,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.fit,
    bool fullScreen = false,
    bool isDismissible = true,
    Color? backgroundColor,
  }) async {
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native && fullScreen) {
      return Navigator.of(context, rootNavigator: true).push<T>(
        MaterialPageRoute<T>(
          fullscreenDialog: true,
          builder: (context) => PopScope(
            canPop: false,
            child: ColoredBox(
              color:
                  backgroundColor ??
                  CupertinoColors.systemBackground.resolveFrom(context),
              child: builder(context),
            ),
          ),
        ),
      );
    }
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      if (detents == AdaptiveFilterDetents.fit) {
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          useSafeArea: true,
          showDragHandle: isDismissible,
          enableDrag: isDismissible,
          isDismissible: isDismissible,
          backgroundColor: backgroundColor,
          builder: (context) => SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: builder(context),
          ),
        );
      }
      return AdaptiveBottomSheet.show<T>(
        context: context,
        builder: builder,
        heightFactor: switch (detents) {
          AdaptiveFilterDetents.short => 0.34,
          AdaptiveFilterDetents.full => 0.94,
          AdaptiveFilterDetents.halfAndFull || AdaptiveFilterDetents.fit => 0.5,
        },
        expandedHeightFactor: detents == AdaptiveFilterDetents.halfAndFull
            ? 0.94
            : null,
        backgroundColor: backgroundColor,
        isDismissible: isDismissible,
      );
    }
    if (route == null || route.isEmpty) {
      throw ArgumentError('Native sheets require a route for nativeSheetMain.');
    }
    // The page stays mounted, with its own metrics and native controls. No
    // sheet widgets are inserted into its tree, even for one temporary frame.
    final value = await _channel.invokeMethod<Object?>('present', {
      'route': route,
      'arguments': arguments,
      'detents': fullScreen ? 'fullScreen' : detents.name,
      'dismissible': isDismissible,
      'backgroundColor':
          (backgroundColor ??
                  CupertinoColors.systemBackground.resolveFrom(context))
              .toARGB32(),
      'brightness': CupertinoTheme.brightnessOf(context).name,
    });
    if (value == null) return null;
    return decodeResult == null ? value as T : decodeResult(value);
  }

  /// Closes this sheet. A nested sheet's result goes to its originating engine.
  static Future<void> pop<T>(BuildContext context, [T? value]) async {
    if (!_hosted) {
      if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
        Navigator.of(context).pop<T>(value);
      }
      return;
    }
    if (_closing) return;
    _closing = true;
    try {
      await _channel.invokeMethod<void>('dismiss', {
        'value': _encodeResult(value),
      });
    } finally {
      _closing = false;
    }
  }
}

/// Sheet content in its dedicated engine. UIKit supplies the real sheet,
/// grabber, detents, dimming and dismissal gestures.
///
/// Fit content scrolls once its natural height exceeds the native detent.
/// Safe areas come from this sheet's FlutterView, never from the page behind it.
class AdaptiveNativeSheetContent extends StatefulWidget {
  const AdaptiveNativeSheetContent({
    super.key,
    required this.child,
    this.fits = true,
    this.backgroundColor,
  });

  final Widget child;
  final bool fits;
  final Color? backgroundColor;

  @override
  State<AdaptiveNativeSheetContent> createState() =>
      _AdaptiveNativeSheetContentState();
}

class _AdaptiveNativeSheetContentState
    extends State<AdaptiveNativeSheetContent> {
  final _contentKey = GlobalKey();
  Timer? _heightTimer;
  double? _height;
  bool _measureScheduled = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void dispose() {
    _heightTimer?.cancel();
    super.dispose();
  }

  void _scheduleMeasurement() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      if (widget.fits) {
        final box = _contentKey.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize && box.size.height.isFinite) {
          final height = box.size.height;
          if (_height == null || (height - _height!).abs() >= 0.5) {
            _height = height;
            _heightTimer?.cancel();
            if (!_ready) {
              _reportHeight(height);
            } else {
              _heightTimer = Timer(
                const Duration(milliseconds: 40),
                () => _reportHeight(height),
              );
            }
          }
        }
      }
      if (!_ready) {
        _ready = true;
        unawaited(AdaptiveNativeSheet._channel.invokeMethod<void>('ready'));
      }
    });
  }

  void _reportHeight(double height) {
    unawaited(
      AdaptiveNativeSheet._channel.invokeMethod<void>('setHeight', {
        'height': height,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return ColoredBox(
      color:
          widget.backgroundColor ??
          CupertinoColors.systemBackground.resolveFrom(context),
      child: widget.fits
          ? NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _scheduleMeasurement();
                return false;
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizeChangedLayoutNotifier(
                  child: KeyedSubtree(key: _contentKey, child: widget.child),
                ),
              ),
            )
          : widget.child,
    );
  }
}
