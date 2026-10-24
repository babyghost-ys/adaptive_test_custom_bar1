import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialPageRoute, PopScope, showModalBottomSheet;
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

  /// The topmost native sheet, or null.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> active =
      ValueNotifier<AdaptiveNativeSheetEntry?>(null);

  /// The sheet the engine draws into right now, or null while it draws the
  /// page. On iOS the engine renders into one view at a time: the topmost
  /// sheet while any is up, so this is [active], except while the native
  /// side has the engine draw a covered layer again after the window changed
  /// size (`drawLayer`). `AdaptiveToolbarHost` paints that sheet's widget
  /// over the whole window, which is then that sheet.
  static final ValueNotifier<AdaptiveNativeSheetEntry?> drawn =
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
  /// `drawLayer`: the window changed size while a sheet was up, so what the
  /// engine was not drawing (the page, any sheet under the top one) is a
  /// stale frame. The native side lends the engine to each such layer in
  /// turn (the page at index -1, then each covered sheet by index) and
  /// finally gives it back to the top sheet, which stays mounted throughout.
  /// Answers once that layer's frame, native views included, is on screen.
  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dismissedByUser':
          if (_stack.isNotEmpty) _finish(_stack.last, null);
        case 'drawLayer':
          final index = (call.arguments as Map?)?['index'] as int? ?? -1;
          drawn.value = index < 0
              ? null
              : index < _stack.length
              ? _stack[index]
              : _stack.lastOrNull;
          await _settled();
      }
      return null;
    });
  }

  /// Completes once the engine has drawn the current layer and composited
  /// its native views: a frame, a pause for the raster thread and the
  /// platform views to catch up, then one more frame.
  static Future<void> _settled() async {
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    SchedulerBinding.instance.ensureVisualUpdate();
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Removes [entry] from the stack and completes its result. The sheet below,
  /// if any, becomes the one drawn.
  static void _finish(AdaptiveNativeSheetEntry entry, Object? value) {
    _stack.remove(entry);
    active.value = _stack.lastOrNull;
    drawn.value = _stack.lastOrNull;
    entry.complete(value);
  }

  /// True while the engine draws a native sheet. Chrome the app paints over
  /// its pages (such as the Duo bar strip) must not draw then: the window the
  /// engine draws into is the sheet.
  static bool get isShowingNow => drawn.value != null;

  /// Shows [builder]'s widget in the sheet. Returns the value passed to [pop],
  /// or null when the sheet is dragged away.
  ///
  /// With [fullScreen], the sheet covers the whole screen (UIKit's
  /// `.overFullScreen` presentation) and cannot be dragged away: only [pop]
  /// closes it, so the widget must offer its own close control. [detents]
  /// is then ignored. Off iOS it is a full-screen dialog route that the
  /// system back gesture does not close.
  ///
  /// With [isDismissible] false, tapping outside the sheet does not close it,
  /// so the widget must offer its own close control. On iOS the sheet cannot
  /// be dragged away either and shows no grabber, since UIKit stops both
  /// together. Off iOS the drag handle goes too.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
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
    _installHandler();
    final done = Completer<T?>();
    final entry = AdaptiveNativeSheetEntry._(
      builder: builder,
      backgroundColor: backgroundColor,
      fits: !fullScreen && detents == AdaptiveFilterDetents.fit,
      fullScreen: fullScreen,
      complete: (value) {
        if (!done.isCompleted) done.complete(value as T?);
      },
    );
    try {
      await _channel.invokeMethod<void>('present', {
        'detents': fullScreen ? 'fullScreen' : detents.name,
        'dismissible': isDismissible,
        // Until the widget has been measured, open at the height the last
        // sheet measured, so a repeat open does not visibly resize.
        'height': _lastOpenHeight > 0 ? _lastOpenHeight : 320.0,
      });
    } on PlatformException {
      return null;
    }
    _stack.add(entry);
    active.value = entry;
    drawn.value = entry;
    return done.future;
  }

  static double _lastOpenHeight = 0;

  /// Tells UIKit the content's height, so the "fit" detent follows it. Debounced:
  /// an animating widget changes size every frame.
  ///
  /// [entry] says which sheet: a covered sheet drawn again after a rotation
  /// can measure differently at its new width. Only the sheet the engine
  /// draws is laid out at its own size, so a measurement of any other sheet
  /// is dropped.
  static void _reportHeight(AdaptiveNativeSheetEntry entry, double height) {
    if (drawn.value != entry) return;
    if ((height - entry._lastHeight).abs() < 0.5) return;
    entry._lastHeight = height;
    if (entry == _stack.lastOrNull) _lastOpenHeight = height;
    entry._heightTimer?.cancel();
    entry._heightTimer = Timer(const Duration(milliseconds: 40), () {
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
    required this.fullScreen,
    required this.complete,
  });

  /// Whether the sheet's height follows [builder]'s widget.
  final bool fits;

  /// Whether the sheet covers the whole screen.
  final bool fullScreen;
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final void Function(Object? value) complete;

  /// The content height last reported for this sheet, and the debounce of
  /// the next report.
  double _lastHeight = 0;
  Timer? _heightTimer;
}

/// Fills the window, which on iOS is the sheet, with the caller's widget.
///
/// Placed above the app by `AdaptiveToolbarHost`. The topmost sheet's widget
/// stays mounted while any sheet is up, and is painted while the engine draws
/// that sheet ([AdaptiveNativeSheet.drawn]). While the engine draws another
/// layer (the page or a covered sheet, after the window changed size) it is
/// kept offstage at the size it last had, so nothing in it is laid out again
/// and its native views are where they were when the engine returns; the
/// covered sheet being drawn is mounted for that alone, over the page.
///
/// Each sheet has its own [Overlay], so widgets that need one (tooltips,
/// menus) work inside it. Where the window has a vertical bar (iPhone Duo),
/// it drops that bar's side inset, since the sheet floats inside the window
/// and is not part of the strip the system reserves for it. Every other inset
/// stays, such as the camera housing's on either side of an iPhone in
/// landscape, where the sheet fills the screen.
class AdaptiveNativeSheetLayer extends StatelessWidget {
  const AdaptiveNativeSheetLayer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AdaptiveNativeSheet.active,
      AdaptiveNativeSheet.drawn,
    ]),
    builder: (context, _) {
      final top = AdaptiveNativeSheet.active.value;
      if (top == null) return const SizedBox.shrink();
      final drawn = AdaptiveNativeSheet.drawn.value;
      return Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A covered sheet the engine draws again, mounted for that alone.
            if (drawn != null && drawn != top)
              _SheetSlot(key: ObjectKey(drawn), entry: drawn, painted: true),
            // The top sheet, mounted throughout.
            _SheetSlot(key: ObjectKey(top), entry: top, painted: drawn == top),
          ],
        ),
      );
    },
  );
}

/// One sheet's widget in [AdaptiveNativeSheetLayer].
///
/// While [painted], it fills the window, which is its sheet, and remembers
/// the window's metrics. While not, it stays mounted but offstage, laid out
/// with those metrics, so the engine can draw another layer at that layer's
/// size without this sheet's widgets being measured at it: the sheet's
/// native views would move and come back, and a fit sheet would report a
/// height it does not have.
class _SheetSlot extends StatefulWidget {
  const _SheetSlot({super.key, required this.entry, required this.painted});

  final AdaptiveNativeSheetEntry entry;
  final bool painted;

  @override
  State<_SheetSlot> createState() => _SheetSlotState();
}

class _SheetSlotState extends State<_SheetSlot> {
  /// The window's metrics when this sheet was last painted.
  MediaQueryData? _painted;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    var mq = MediaQuery.of(context);
    if (widget.painted) {
      _painted = mq;
    } else {
      mq = _painted ?? mq;
    }
    final pose = DuoPoseScope.of(context);
    // A full-screen sheet fills the window like a page, so it keeps the
    // strip's inset.
    EdgeInsets withoutStrip(EdgeInsets insets) =>
        pose == null || entry.fullScreen
        ? insets
        : pose.onLeft
        ? insets.copyWith(left: 0)
        : insets.copyWith(right: 0);
    // Always present, with no bounds of its own while painted, so that
    // toggling [painted] never moves the sheet's widget in the element tree.
    final size = widget.painted ? null : mq.size;
    return Visibility(
      visible: widget.painted,
      maintainState: true,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size?.width,
        maxWidth: size?.width,
        minHeight: size?.height,
        maxHeight: size?.height,
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
              initialEntries: [
                OverlayEntry(
                  builder: (context) => entry.fits
                      ? _FitContent(entry: entry, child: entry.builder(context))
                      : entry.builder(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
