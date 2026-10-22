import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/adaptive_style.dart';

/// Where a native-bar page's body sits relative to its bars.
///
/// The scaffold measures every inset (status bar, navigation bar or large
/// title, tab bar, home indicator) and decides here, once, which edges the
/// body runs under. An edge the body runs under stays in [MediaQuery.padding]
/// for the body's scroll view to apply; every other edge is applied as
/// padding, so content never sits under a bar it cannot scroll out from.
@immutable
class BodyPlacement {
  const BodyPlacement({required this.underTop, required this.underBottom});

  /// Content scrolls under the top bar and starts below it.
  final bool underTop;

  /// Content scrolls under the tab bar and ends above it.
  final bool underBottom;

  /// Aligned first: the body sits between the bars, unless it is a scroll
  /// view that applies the insets itself and the platform draws glass bars
  /// over content (iOS 26 and later). A large title needs the content below
  /// it to collapse, so it runs under the top bar on every iOS version.
  /// [extendBehindTop] and [extendBehindBottom] override either edge.
  factory BodyPlacement.resolve({
    required Widget? body,
    required bool largeTitle,
    bool? extendBehindTop,
    bool? extendBehindBottom,
  }) {
    final scrolls = appliesInsets(body);
    final glass = AdaptiveCapabilities.liquidGlass;
    return BodyPlacement(
      underTop: extendBehindTop ?? (scrolls && (glass || largeTitle)),
      underBottom: extendBehindBottom ?? (scrolls && glass),
    );
  }

  /// Whether [body] is a vertical scroll view that keeps its content clear
  /// of [MediaQuery.padding] by itself: a box scroll view without padding of
  /// its own (Flutter then applies the media padding), or a custom scroll
  /// view, whose slivers [withInsetSlivers] wraps.
  static bool appliesInsets(Widget? body) => switch (body) {
    BoxScrollView(scrollDirection: Axis.vertical, padding: null) => true,
    CustomScrollView(scrollDirection: Axis.vertical, center: null) => true,
    _ => false,
  };

  /// [body] with a custom scroll view's slivers kept clear of the vertical
  /// media padding, as a box scroll view does by itself. Any other body is
  /// returned unchanged.
  static Widget? withInsetSlivers(Widget? body) {
    if (body is! CustomScrollView ||
        body.scrollDirection != Axis.vertical ||
        body.center != null) {
      return body;
    }
    return CustomScrollView(
      key: body.key,
      reverse: body.reverse,
      controller: body.controller,
      primary: body.primary,
      physics: body.physics,
      scrollBehavior: body.scrollBehavior,
      shrinkWrap: body.shrinkWrap,
      anchor: body.anchor,
      scrollCacheExtent:
          body.scrollCacheExtent ??
          // ignore: deprecated_member_use
          (body.cacheExtent == null
              ? null
              // ignore: deprecated_member_use
              : ScrollCacheExtent.pixels(body.cacheExtent!)),
      paintOrder: body.paintOrder,
      semanticChildCount: body.semanticChildCount,
      dragStartBehavior: body.dragStartBehavior,
      keyboardDismissBehavior: body.keyboardDismissBehavior,
      restorationId: body.restorationId,
      clipBehavior: body.clipBehavior,
      hitTestBehavior: body.hitTestBehavior,
      slivers: [
        SliverSafeArea(
          left: false,
          right: false,
          sliver: SliverMainAxisGroup(slivers: body.slivers),
        ),
      ],
    );
  }
}

/// Applies a [BodyPlacement] to the body: pads every edge the body does not
/// run under and removes it from [MediaQuery.padding], so nothing below
/// counts it twice.
class PlacedBody extends StatelessWidget {
  const PlacedBody({super.key, required this.placement, required this.child});

  final BodyPlacement placement;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        placement.underTop ? 0 : padding.top,
        padding.right,
        placement.underBottom ? 0 : padding.bottom,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        removeTop: !placement.underTop,
        removeBottom: !placement.underBottom,
        child: child,
      ),
    );
  }
}
