import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart'
    show
        MaterialPageRoute,
        ModalBottomSheetRoute,
        PopScope,
        kMinInteractiveDimension;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../../devices/duo/duo_layout.dart';
import '../../devices/duo/system_vertical_bar.dart';
import '../../navigation/app_bar/native_toolbar.dart';
import '../../navigation/chrome/hosted_top_toolbar.dart';
import '../../navigation/chrome/toolbar_registry.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A sheet that hosts any widget, with native platform views inside it.
///
/// On iOS the sheet is a real UIKit sheet with its own Flutter engine: [show]
/// sends [route] and codec-safe [arguments] to the app's `nativeSheetMain`
/// entrypoint, which calls [bootstrap] and builds the route inside
/// [AdaptiveNativeSheetContent]. UIKit owns the grabber, detents, dimming and
/// drag dismissal, and hides the sheet while the screen turns (see
/// `docs/sheet-rotation-cut-failed-attempts.md`). Widgets, closures and
/// notifiers cannot cross engines, so [decodeResult] restores the result in
/// the caller.
///
/// Elsewhere, and for a [fullScreen] sheet on every platform, [builder]
/// supplies the content in the caller's isolate as a Flutter route.
class AdaptiveNativeSheet {
  AdaptiveNativeSheet._();

  static const _channel = MethodChannel('adaptive_platform_ui/widget_sheet');
  static bool _hosted = false;
  static bool _closing = false;
  static Object? Function(Object?) _encodeResult = (value) => value;

  static final Set<Route<Object?>> _leavingRoutes = <Route<Object?>>{};
  static final ValueNotifier<bool> _leaving = ValueNotifier(false);

  /// True while a sheet shown by [show] slides away after it was popped.
  ///
  /// The page under it is current again from the moment of the pop, so its
  /// native tab bar would come back over the sheet as it slides down. The
  /// scaffold keeps the tab bar away until this is false.
  static ValueListenable<bool> get leaving => _leaving;

  static void _watchLeaving(TransitionRoute<Object?> route) {
    route.animation?.addStatusListener((status) {
      debugPrint('TMP2 sheet status $status');
      switch (status) {
        case AnimationStatus.reverse:
          _leavingRoutes.add(route);
        case AnimationStatus.dismissed:
          _leavingRoutes.remove(route);
        case AnimationStatus.forward:
        case AnimationStatus.completed:
          return;
      }
      _leaving.value = _leavingRoutes.isNotEmpty;
    });
  }

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

  /// Shows the sheet and completes after it has been dismissed, with the
  /// value given to [pop], or null when it was dragged away or tapped
  /// outside.
  ///
  /// A [fullScreen] sheet covers the whole screen and, like an [isDismissible]
  /// `false` sheet, only closes through [pop]. On iOS [route] is required and
  /// [arguments] must be StandardMessageCodec data.
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
    if (fullScreen) {
      // An opaque page on the root navigator. On iOS the page's native bar
      // stays over its top while it slides up; once it covers the screen the
      // page below leaves the stage, so the bar loses its owner and UIKit
      // hides it until the cover starts to slide away.
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
    if (AdaptiveStyle.of(context) == AdaptiveStyle.native) {
      if (route == null || route.isEmpty) {
        throw ArgumentError(
          'Native sheets require a route for nativeSheetMain.',
        );
      }
      // The page stays mounted with its own engine, metrics and native
      // controls. UIKit presents the sheet from a window of its own.
      final value = await _channel.invokeMethod<Object?>('present', {
        'route': route,
        'arguments': arguments,
        'detents': detents.name,
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
    // Elsewhere the sheet is Flutter's own modal bottom sheet on the root
    // navigator.
    final fill =
        backgroundColor ??
        CupertinoColors.systemBackground.resolveFrom(context);
    if (detents == AdaptiveFilterDetents.fit) {
      // `showModalBottomSheet` with its route in hand, so the tab bar can
      // wait for the sheet to slide away (see [leaving]).
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = ModalBottomSheetRoute<T>(
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: isDismissible,
        enableDrag: isDismissible,
        isDismissible: isDismissible,
        backgroundColor: fill,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        barrierLabel: 'Dismiss',
        builder: (context) => PopScope(
          canPop: isDismissible,
          child: _BelowNativeBars(
            handle: isDismissible,
            child: ValueListenableBuilder<bool>(
              valueListenable: _leaving,
              builder: (context, leaving, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leaving)
                    const SizedBox(
                      height: 40,
                      width: double.infinity,
                      child: ColoredBox(color: Color(0xFFFF0000)),
                    ),
                  Flexible(child: child!),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: builder(context),
              ),
            ),
          ),
        ),
      );
      final result = navigator.push<T>(route);
      _watchLeaving(route);
      return result;
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
      backgroundColor: fill,
      isDismissible: isDismissible,
    );
  }

  /// Closes the sheet [context] is in, completing its [show] with [value].
  static Future<void> pop<T>(BuildContext context, [T? value]) async {
    if (!_hosted) {
      Navigator.of(context).pop<T>(value);
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

/// Gap between the sheet's top and the native bar above it.
const double _inset = 8;

/// Caps a fit sheet's content so the sheet's top stays below the native bars
/// over the page, which UIKit draws above everything Flutter draws; taller
/// content scrolls. UIKit moves the bars when the screen turns, and the cap
/// follows them.
class _BelowNativeBars extends StatelessWidget {
  const _BelowNativeBars({required this.handle, required this.child});

  /// Whether the sheet shows Material's drag handle above [child].
  final bool handle;
  final Widget child;

  /// How far down the screen the native bars over the covered page reach:
  /// its navigation bar, with any large title, or on iPhone Duo the title
  /// band. Only the status bar when the page shows no native bar.
  double _barsBottom(BuildContext context, TopToolbarContent bar) {
    // The sheet's route has taken the status bar out of its padding.
    final statusBar = MediaQueryData.fromView(View.of(context)).viewPadding.top;
    if (DuoPoseScope.of(context) != null) {
      return SystemVerticalBar.titleBand.value?.contentTop ??
          statusBar + kMinInteractiveDimensionCupertino;
    }
    if (ToolbarRegistry.maybeOf(context) == null) {
      return nativeNavigationBarBottom.value ?? statusBar;
    }
    if (bar.isEmpty) return statusBar;
    return bar.scrollController?.navigationBarBottom.value ??
        nativeNavigationBarBottom.value ??
        statusBar + kHostedToolbarHeight;
  }

  @override
  Widget build(BuildContext context) {
    // While a sheet covers it, the page in front keeps owning the bar.
    final bar = TopToolbarContent.of(ToolbarRegistry.maybeOf(context)?.owner);
    final barBottom = bar.scrollController?.navigationBarBottom;
    return ListenableBuilder(
      listenable: Listenable.merge([
        nativeNavigationBarBottom,
        SystemVerticalBar.titleBand,
        if (barBottom != null) barBottom,
      ]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        // The sheet's drag handle sits above the content and takes a row.
        final handleHeight = handle ? kMinInteractiveDimension : 0.0;
        final room = math.max(
          0.0,
          media.size.height -
              media.viewInsets.bottom -
              _barsBottom(context, bar) -
              _inset -
              handleHeight,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room),
          child: child,
        );
      },
    );
  }
}
