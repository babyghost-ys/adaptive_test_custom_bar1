import 'package:flutter/widgets.dart';

/// Connects a Flutter scroll view to a native navigation bar.
/// Use one controller per page/tab, and dispose it with that page.
class AdaptiveNavigationScrollController extends ScrollController {
  AdaptiveNavigationScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// UIKit's automatic content inset at the page's resting position.
  final ValueNotifier<double?> contentTopInset = ValueNotifier<double?>(null);

  /// Current native bar boundary, including large-title expansion and bounce.
  final ValueNotifier<double?> navigationBarBottom = ValueNotifier<double?>(
    null,
  );

  bool _disposed = false;

  /// Most recent first. A scaffold offers one controller to its whole body,
  /// so every tab kept alive in it (an IndexedStack, a shell route) attaches.
  final List<ScrollPosition> _recent = [];
  final Map<ScrollPosition, VoidCallback> _moveListeners = {};

  /// The scroll view the native bar follows: the one most recently attached
  /// or scrolled among those on screen. Tab containers that keep pages alive
  /// offstage turn their tickers off, which is what tells them apart.
  ScrollPosition? get activePosition {
    if (positions.length == 1) return positions.first;
    for (final position in _recent) {
      final context = position.context.notificationContext;
      if (context == null || !context.mounted) continue;
      if (TickerMode.getValuesNotifier(context).value.enabled) return position;
    }
    return null;
  }

  /// [activePosition]'s offset from its top, or the initial offset before
  /// any scroll view is attached.
  double get activeOffset {
    final position = activePosition;
    return position == null || !position.hasPixels
        ? initialScrollOffset
        : position.pixels - position.minScrollExtent;
  }

  void _touch(ScrollPosition position) {
    if (_recent.isNotEmpty && identical(_recent.first, position)) return;
    _recent
      ..remove(position)
      ..insert(0, position);
  }

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    _touch(position);
    void moved() {
      if (position.isScrollingNotifier.value) _touch(position);
    }

    _moveListeners[position] = moved;
    position.addListener(moved);
    // PageStorage restores a position during layout without a scroll event.
    // Tell a retained native bar about that restored position after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && positions.contains(position)) notifyListeners();
    });
  }

  @override
  void detach(ScrollPosition position) {
    final moved = _moveListeners.remove(position);
    if (moved != null) position.removeListener(moved);
    _recent.remove(position);
    super.detach(position);
  }

  /// Tells the native bar to follow [activePosition] again, e.g. after the
  /// body switched to another tab that shares this controller.
  void activeChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    contentTopInset.dispose();
    navigationBarBottom.dispose();
    super.dispose();
  }
}
