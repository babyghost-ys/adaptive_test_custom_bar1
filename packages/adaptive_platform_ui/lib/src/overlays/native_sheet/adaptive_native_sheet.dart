import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive_style.dart';
import '../../devices/duo/duo_layout.dart';
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
/// A sheet can open another on top of itself: call [show] again from the
/// sheet's widget. Each sheet has its own result and its own [pop].
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

  /// The topmost native sheet's widget, or null. `AdaptiveToolbarHost` draws it
  /// over the whole window, which on iOS is that sheet: the engine renders
  /// into the topmost sheet while any is up.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> active =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// Open native sheets, bottom first. A sheet can open another on top of
  /// itself by calling [show] again from its own widget.
  static final List<AdaptiveNativeSheetEntry> _stack = [];

  static bool _handlerInstalled = false;

  /// One handler for the whole stack.
  ///
  /// `dismissedByUser`: the user dragged the top sheet away, so it is already
  /// gone.
  ///
  /// `drawLayer`: after the window changes size, the native side lends the
  /// engine to each covered layer in turn (the page at index -1, then each
  /// sheet below the top one) so it can be drawn again at the new size, and
  /// finally gives it back to the top sheet. Answers once that layer's frame,
  /// native views included, is on screen.
  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dismissedByUser':
          if (_stack.isNotEmpty) _finish(_stack.last, null);
        case 'drawLayer':
          final index = (call.arguments as Map?)?['index'] as int? ?? -1;
          active.value = index >= 0 && index < _stack.length
              ? _stack[index]
              : null;
          await _settled();
      }
      return null;
    });
  }

  /// Completes once the current layer has been drawn and its native views,
  /// which are created and sized over a few more frames, have caught up.
  static Future<void> _settled() async {
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Removes [entry] from the stack and completes its result. The sheet below,
  /// if any, becomes the one drawn.
  static void _finish(AdaptiveNativeSheetEntry entry, Object? value) {
    _stack.remove(entry);
    active.value = _stack.isEmpty ? null : _stack.last;
    entry.complete(value);
  }

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
    _installHandler();
    final done = Completer<T?>();
    final entry = AdaptiveNativeSheetEntry._(
      builder: builder,
      backgroundColor: backgroundColor,
      fits: detents == AdaptiveFilterDetents.fit,
      complete: (value) {
        if (!done.isCompleted) done.complete(value as T?);
      },
    );
    try {
      await _channel.invokeMethod<void>('present', {
        'detents': detents.name,
        // Until the widget has been measured, open at the height the last
        // sheet measured, so a repeat open does not visibly resize.
        'height': _lastOpenHeight > 0 ? _lastOpenHeight : 320.0,
      });
    } on PlatformException {
      return null;
    }
    _stack.add(entry);
    active.value = entry;
    return done.future;
  }

  static Timer? _heightTimer;
  static double _lastHeight = 0;
  static double _lastOpenHeight = 0;

  /// Tells UIKit the content's height, so the "fit" detent follows it. Debounced:
  /// an animating widget changes size every frame.
  ///
  /// [entry] says which sheet: a covered sheet drawn again after a rotation
  /// can measure differently at its new width.
  static void _reportHeight(AdaptiveNativeSheetEntry entry, double height) {
    if ((height - _lastHeight).abs() < 0.5) return;
    _lastHeight = height;
    _lastOpenHeight = height;
    _heightTimer?.cancel();
    _heightTimer = Timer(const Duration(milliseconds: 40), () {
      final depth = _stack.indexOf(entry);
      if (depth < 0) return;
      _channel
          .invokeMethod<void>('setHeight', {'height': height, 'depth': depth})
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
    if (_stack.isEmpty) return;
    final entry = _stack.last;
    // Let UIKit finish dismissing first, so the sheet never shows what is
    // below it as it leaves.
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on PlatformException {
      // Already gone.
    }
    _finish(entry, value);
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
/// widgets that need one (tooltips, menus) work inside it. Where the window
/// has a vertical bar (iPhone Duo), it drops that bar's side inset, since the
/// sheet floats inside the window and is not part of the strip the system
/// reserves for it. Every other inset stays, such as the camera housing's on
/// either side of an iPhone in landscape, where the sheet fills the screen.
class AdaptiveNativeSheetLayer extends StatelessWidget {
  const AdaptiveNativeSheetLayer({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AdaptiveNativeSheetEntry?>(
        valueListenable: AdaptiveNativeSheet.active,
        builder: (context, entry, _) {
          if (entry == null) return const SizedBox.shrink();
          final mq = MediaQuery.of(context);
          final pose = DuoPoseScope.of(context);
          EdgeInsets withoutStrip(EdgeInsets insets) => pose == null
              ? insets
              : pose.onLeft
              ? insets.copyWith(left: 0)
              : insets.copyWith(right: 0);
          return Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                padding: withoutStrip(mq.padding),
                viewPadding: withoutStrip(mq.viewPadding),
              ),
              child: ColoredBox(
                color:
                    entry.backgroundColor ??
                    CupertinoColors.systemBackground.resolveFrom(context),
                child: Overlay(
                  // A different sheet on top gets a fresh overlay.
                  key: ObjectKey(entry),
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) => entry.fits
                          ? _FitContent(
                              entry: entry,
                              child: entry.builder(context),
                            )
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
  const _FitContent({required this.entry, required this.child});
  final AdaptiveNativeSheetEntry entry;
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
        AdaptiveNativeSheet._reportHeight(widget.entry, box.size.height);
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
