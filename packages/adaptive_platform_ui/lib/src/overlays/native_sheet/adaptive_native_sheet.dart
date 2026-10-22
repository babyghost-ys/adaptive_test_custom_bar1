import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../bottom_sheet/adaptive_bottom_sheet.dart';
import '../filter_sheet/adaptive_filter_sheet.dart';

/// A real UIKit sheet (`UISheetPresentationController`) that shows your own
/// widget.
///
/// On iOS the sheet is native: it floats above the whole window, so it covers
/// the navigation bar and tab bar, and it has native detents, grabber, dimming
/// and drag-to-dismiss. Its content is [builder]'s widget, drawn by Flutter
/// inside the sheet, in the same isolate as the rest of the app. The widget
/// can be a `StatelessWidget`, close over anything, and read the app's state
/// (a bloc, a provider, a notifier) as it would anywhere else.
///
/// The widget is not a route. The page behind the sheet stays the current
/// route, so its navigation bar and toolbar stay in place.
///
/// ```dart
/// final result = await AdaptiveNativeSheet.show<MyFilter>(
///   context: context,
///   builder: (_) => MyWidget(),
/// );
/// ```
///
/// The sheet's height follows the widget's height. Close it from inside with
/// [pop], not `Navigator.pop`.
///
/// Where [AdaptiveStyle] is material, the same widget is shown in a Material
/// bottom sheet.
class AdaptiveNativeSheet {
  AdaptiveNativeSheet._();
  static const _channel = MethodChannel('adaptive_platform_ui/widget_sheet');

  /// The widget the native sheet is showing, or null. `AdaptiveToolbarHost`
  /// draws it over the whole window, which on iOS is the sheet: the engine
  /// renders into the sheet while one is up.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> active =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// True while a native sheet is showing. Chrome the app paints over its
  /// pages (such as the Duo bar strip) must not draw over the sheet.
  static bool get isShowingNow => active.value != null;

  /// Shows [builder]'s widget in the sheet. Returns the value passed to [pop],
  /// or null when the sheet is dragged away.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.fit,
    Color? backgroundColor,
  }) async {
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      if (detents == AdaptiveFilterDetents.fit) {
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          useSafeArea: true,
          showDragHandle: true,
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
      );
    }
    if (active.value != null) return null;

    final done = Completer<T?>();
    final entry = AdaptiveNativeSheetEntry._(
      builder: builder,
      backgroundColor: backgroundColor,
      fits: detents == AdaptiveFilterDetents.fit,
      complete: (value) {
        if (!done.isCompleted) done.complete(value as T?);
      },
    );
    _channel.setMethodCallHandler((call) async {
      // The user dragged the sheet down: it is already gone.
      if (call.method == 'dismissedByUser' && active.value == entry) {
        active.value = null;
        entry.complete(null);
      }
      return null;
    });
    try {
      await _channel.invokeMethod<void>('present', {
        'detents': detents.name,
        // Until the widget has been measured, open at the height the last
        // sheet measured, so a repeat open does not visibly resize.
        'height': _lastOpenHeight > 0 ? _lastOpenHeight : 320.0,
      });
    } on PlatformException {
      _channel.setMethodCallHandler(null);
      return null;
    }
    active.value = entry;
    try {
      return await done.future;
    } finally {
      if (active.value == entry) active.value = null;
      _channel.setMethodCallHandler(null);
    }
  }

  static Timer? _heightTimer;
  static double _lastHeight = 0;
  static double _lastOpenHeight = 0;

  /// Tells UIKit the content's height, so the "fit" detent follows it. Debounced:
  /// an animating widget changes size every frame.
  static void _reportHeight(double height) {
    if ((height - _lastHeight).abs() < 0.5) return;
    _lastHeight = height;
    _lastOpenHeight = height;
    _heightTimer?.cancel();
    _heightTimer = Timer(const Duration(milliseconds: 40), () {
      if (active.value == null) return;
      _channel
          .invokeMethod<void>('setHeight', {'height': height})
          .catchError((Object _) {});
    });
  }

  /// Closes the sheet opened by [show], returning [value] from it. Call it
  /// from inside the sheet's widget.
  static Future<void> pop<T>(BuildContext context, [T? value]) async {
    // Off iOS the sheet is an ordinary modal bottom sheet route.
    if (AdaptiveStyle.of(context) != AdaptiveStyle.native) {
      Navigator.of(context).pop<T>(value);
      return;
    }
    final entry = active.value;
    if (entry == null) return;
    if (AdaptiveStyle.of(context) == AdaptiveStyle.native) {
      // Let UIKit finish dismissing first, so the sheet never shows the page
      // behind it as it leaves.
      try {
        await _channel.invokeMethod<void>('dismiss');
      } on PlatformException {
        // Already gone.
      }
    }
    active.value = null;
    entry.complete(value);
  }
}

/// One open native sheet: the caller's widget and how to finish it.
class AdaptiveNativeSheetEntry {
  AdaptiveNativeSheetEntry._({
    required this.builder,
    required this.backgroundColor,
    required this.fits,
    required this.complete,
  });

  /// Whether the sheet's height follows [builder]'s widget.
  final bool fits;
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final void Function(Object? value) complete;
}

/// Fills the window, which on iOS is the sheet, with the caller's widget.
///
/// Placed above the app by `AdaptiveToolbarHost`. It has its own [Overlay], so
/// widgets that need one (tooltips, menus) work inside it, and it drops the
/// side insets the page below carries, since the sheet floats inside the window
/// and is not part of the strip the system reserves for a vertical bar.
class AdaptiveNativeSheetLayer extends StatelessWidget {
  const AdaptiveNativeSheetLayer({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AdaptiveNativeSheetEntry?>(
        valueListenable: AdaptiveNativeSheet.active,
        builder: (context, entry, _) {
          if (entry == null) return const SizedBox.shrink();
          final mq = MediaQuery.of(context);
          return Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(left: 0, right: 0),
                viewPadding: mq.viewPadding.copyWith(left: 0, right: 0),
              ),
              child: ColoredBox(
                color:
                    entry.backgroundColor ??
                    CupertinoColors.systemBackground.resolveFrom(context),
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) => entry.fits
                          ? _FitContent(child: entry.builder(context))
                          : entry.builder(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// Lays [child] out at its natural height and reports it, so the native sheet
/// can follow it. Scrolls when the sheet is capped at full height.
class _FitContent extends StatefulWidget {
  const _FitContent({required this.child});
  final Widget child;

  @override
  State<_FitContent> createState() => _FitContentState();
}

class _FitContentState extends State<_FitContent> {
  final _key = GlobalKey();

  void _measure() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        AdaptiveNativeSheet._reportHeight(box.size.height);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    AdaptiveNativeSheet._lastHeight = 0;
    _measure();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _measure();
          return false;
        },
        child: SingleChildScrollView(
          child: SizeChangedLayoutNotifier(
            child: KeyedSubtree(key: _key, child: widget.child),
          ),
        ),
      );
}
