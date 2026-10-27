import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialPageRoute, PopScope, showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../../devices/duo/duo_layout.dart';
import '../../devices/duo/system_vertical_bar.dart';
import '../../native/sheet_platform_view_guard.dart';
import '../../navigation/app_bar/native_toolbar.dart';
import '../../navigation/chrome/hosted_top_toolbar.dart';
import '../../navigation/chrome/toolbar_registry.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A sheet that hosts any widget, with native platform views inside it.
///
/// On iOS the sheet is, for now, drawn by Flutter in the page's own view: an
/// iOS 26 style floating sheet on the root navigator, which keeps its top
/// below the native navigation bar UIKit draws above every Flutter route.
/// [builder] supplies its content on every platform, in the caller's isolate,
/// so the widget keeps its closures, notifiers and blocs.
///
/// The UIKit presentation (one Flutter engine per sheet, started through the
/// app's `nativeSheetMain` entrypoint with [bootstrap] and
/// [AdaptiveNativeSheetContent]) is not used while this is so; `route`,
/// `arguments` and `decodeResult` only serve that presentation.
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

  /// Shows [builder]'s content in a sheet and completes after it has been
  /// dismissed, with the value given to [pop], or null when it was dragged
  /// away or tapped outside.
  ///
  /// A [fullScreen] sheet covers the whole screen and, like an [isDismissible]
  /// `false` sheet, only closes through [pop]. [route], [arguments] and
  /// [decodeResult] are kept for the UIKit presentation, which is not in use.
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
    final resizable = detents == AdaptiveFilterDetents.halfAndFull;
    // Over another sheet, a second scrim would be split around native
    // controls by Flutter's platform view compositing. The lower sheet dims
    // its own fill instead, as UIKit dims a sheet behind a sheet.
    final nested = ModalRoute.of(context) is PopupRoute;
    // On the root navigator the sheet covers the page that holds the native
    // tab bar, so the tab bar steps aside rather than staying over the sheet.
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      backgroundColor: const Color(0x00000000),
      elevation: 0,
      constraints: const BoxConstraints(),
      barrierColor: nested ? const Color(0x00000000) : _scrim,
      builder: (context) => PopScope(
        canPop: isDismissible,
        child: _FloatingSheet(
          share: switch (detents) {
            AdaptiveFilterDetents.fit => null,
            AdaptiveFilterDetents.short => 0.34,
            AdaptiveFilterDetents.full => 1,
            AdaptiveFilterDetents.halfAndFull => 0.5,
          },
          expandedShare: resizable ? 1 : null,
          grabber: isDismissible || resizable,
          backgroundColor: backgroundColor,
          builder: builder,
        ),
      ),
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

/// Dimming behind a sheet, and over a sheet another sheet covers.
const Color _scrim = Color(0x33000000);

/// Gap between a floating sheet and the screen edges, and between its top
/// and the native bar above it.
const double _inset = 8;

/// A wider sheet is centred, as UIKit centres one on a wide screen.
const double _maxSheetWidth = 640;

/// An iOS 26 floating sheet drawn by Flutter: inset from the screen edges,
/// with continuous corners, and a grabber when it can be dragged.
///
/// It rests at [share] of the screen height, or fits its content when [share]
/// is null; with [expandedShare] the grabber moves it between the two. Either
/// way its top stays below the native bars over the page, which UIKit draws
/// above everything Flutter draws, and content taller than the room left
/// scrolls.
class _FloatingSheet extends StatefulWidget {
  const _FloatingSheet({
    required this.share,
    required this.expandedShare,
    required this.grabber,
    required this.backgroundColor,
    required this.builder,
  });

  final double? share;
  final double? expandedShare;
  final bool grabber;
  final Color? backgroundColor;
  final WidgetBuilder builder;

  @override
  State<_FloatingSheet> createState() => _FloatingSheetState();
}

class _FloatingSheetState extends State<_FloatingSheet> {
  static const double _flingVelocity = 300;
  static const double _dragThreshold = 24;

  bool _expanded = false;
  double _drag = 0;

  void _settle(double velocity) {
    final up = velocity < -_flingVelocity || _drag < -_dragThreshold;
    final down = velocity > _flingVelocity || _drag > _dragThreshold;
    _drag = 0;
    if (up && !_expanded) {
      setState(() => _expanded = true);
    } else if (down) {
      if (_expanded) {
        setState(() => _expanded = false);
      } else {
        Navigator.maybePop(context);
      }
    }
  }

  /// How far down the screen the native bars over the covered page reach:
  /// its navigation bar, with any large title, or on iPhone Duo the title
  /// band (the controls are in the side strip, which the sheet's side insets
  /// keep clear of). Only the status bar when the page shows no native bar.
  double _barsBottom(TopToolbarContent bar) {
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
    // UIKit moves the bars when the screen turns; the sheet follows them.
    return ListenableBuilder(
      listenable: Listenable.merge([
        nativeNavigationBarBottom,
        SystemVerticalBar.titleBand,
        if (barBottom != null) barBottom,
      ]),
      builder: (context, _) => _buildSheet(context, bar),
    );
  }

  Widget _buildSheet(BuildContext context, TopToolbarContent bar) {
    final media = MediaQuery.of(context);
    // Floats clear of the home indicator, and rides on top of the keyboard
    // while a field in the sheet has focus.
    final lift = media.viewPadding.bottom > 0 ? _inset : 0.0;
    final bottom = media.viewInsets.bottom + lift;
    final room = math.max(
      0.0,
      media.size.height - bottom - _barsBottom(bar) - _inset,
    );
    final fill =
        widget.backgroundColor ??
        CupertinoColors.systemBackground.resolveFrom(context);
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    final share = widget.share;
    final expandedShare = widget.expandedShare;

    Widget content = Builder(builder: widget.builder);
    if (share == null) content = SingleChildScrollView(child: content);
    // The sheet's edges are its content's safe area: nothing at the top or
    // the sides, and at the bottom only what of the home indicator it still
    // overlaps.
    content = MediaQuery(
      data: media.copyWith(
        padding: EdgeInsets.only(
          bottom: math.max(0.0, media.padding.bottom - lift),
        ),
        viewPadding: EdgeInsets.only(
          bottom: math.max(0.0, media.viewPadding.bottom - lift),
        ),
        viewInsets: EdgeInsets.zero,
      ),
      child: content,
    );
    if (widget.grabber) {
      // UIKit's grabber floats over the top of the content.
      Widget grabber = Padding(
        padding: const EdgeInsets.only(top: 5),
        child: SizedBox(
          width: 36,
          height: 5,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      );
      grabber = expandedShare == null
          ? IgnorePointer(child: grabber)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              onVerticalDragUpdate: (details) => _drag += details.delta.dy,
              onVerticalDragEnd: (details) =>
                  _settle(details.primaryVelocity ?? 0),
              onVerticalDragCancel: () => _drag = 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 10),
                child: grabber,
              ),
            );
      content = Stack(
        fit: share == null ? StackFit.loose : StackFit.expand,
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: grabber),
          ),
        ],
      );
    }

    Widget sheet = SheetSurface(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        // Covered by another sheet, only the fill darkens: a layer drawn over
        // the sheet's native controls would be split around them by
        // Flutter's platform view compositing.
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: covered ? Color.alphaBlend(_scrim, fill) : fill,
          ),
          duration: const Duration(milliseconds: 220),
          builder: (context, color, child) =>
              ColoredBox(color: color ?? fill, child: child),
          child: content,
        ),
      ),
    );
    if (share != null) {
      sheet = TweenAnimationBuilder<double>(
        tween: Tween(end: _expanded ? expandedShare ?? share : share),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => SizedBox(
          height: math.min(value * media.size.height, room),
          child: child,
        ),
        child: sheet,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        math.max(_inset, media.padding.left),
        0,
        math.max(_inset, media.padding.right),
        bottom,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _maxSheetWidth,
            maxHeight: room,
          ),
          child: SizedBox(width: double.infinity, child: sheet),
        ),
      ),
    );
  }
}
