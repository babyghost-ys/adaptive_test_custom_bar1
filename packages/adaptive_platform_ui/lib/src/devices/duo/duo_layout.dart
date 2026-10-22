import 'package:flutter/cupertino.dart';
import 'reserved_region.dart';

import 'system_vertical_bar.dart';

/// Width of the strip the vertical control bar lives in when the system
/// reserves none: the leading pane in Split View, or a missing inset. Matches
/// the hardware strip of the inner display (the bar's centre sits 48 points
/// from the edge in both), which the system mirrors there. Where the system
/// does reserve the strip, the bar takes the width of that inset instead.
const double kDuoVerticalBarWidth = 84.0;

/// Top clearance of the vertical bar in a strip without hardware (the leading
/// Split View pane). Matches UIKit's `bar(onEdge:extent:)` layout region there.
const double kDuoBarOnlyTopMargin = 16.0;

/// How far the control band extends inward beyond the system strip, so the
/// centred controls sit a few points off the bezel instead of hugging the
/// display edge.
const double kDuoVerticalBarBezelInset = 12.0;

/// Clearance used below the top edge until the system has reported where the
/// camera and status cluster are. It covers the taller of the two displays, so
/// controls never start out underneath the cluster.
const double kDuoStatusClusterFallbackHeight = 170.0;

/// The edge of the window the system reserves for vertical controls.
enum DuoBarSide { left, right }

/// The resolved iPhone Duo layout for a window: which edge the vertical bar is
/// on and how wide its strip is.
@immutable
class DuoPose {
  const DuoPose({
    required this.side,
    required this.stripWidth,
    required this.reservedBySystem,
  });

  final DuoBarSide side;

  /// Width of the strip the bar sits in.
  final double stripWidth;

  /// True when the strip is a system safe-area inset, holding the status
  /// cluster or camera. False in the leading Split View pane: the system
  /// wants a vertical bar there, but only adds its inset for bars it draws
  /// itself, never for a Flutter view.
  final bool reservedBySystem;

  bool get onLeft => side == DuoBarSide.left;

  /// Width of the band the bar is laid out in: the strip plus
  /// [kDuoVerticalBarBezelInset].
  double get bandWidth => stripWidth + kDuoVerticalBarBezelInset;

  /// [insets] with the strip added on the bar's side: the inset UIKit would
  /// have reserved for a vertical bar it draws itself.
  EdgeInsets addStrip(EdgeInsets insets) => onLeft
      ? insets.copyWith(left: insets.left + stripWidth)
      : insets.copyWith(right: insets.right + stripWidth);

  @override
  bool operator ==(Object other) =>
      other is DuoPose &&
      other.side == side &&
      other.stripWidth == stripWidth &&
      other.reservedBySystem == reservedBySystem;

  @override
  int get hashCode => Object.hash(side, stripWidth, reservedBySystem);

  @override
  String toString() =>
      '${side.name} ${stripWidth.toStringAsFixed(0)}pt '
      '(${reservedBySystem ? 'system strip' : 'bar-only strip'})';
}

/// Layout decisions for iPhone Duo.
abstract final class DuoLayout {
  /// The Duo layout for a window, or null where bars stay horizontal.
  ///
  /// The safe-area insets decide where they name a side ([barSide]). The
  /// system's own [edge] only adds a vertical pose where they name none, which
  /// is the leading Split View pane: it has no side inset, so the edge is the
  /// only signal there. The insets win because they arrive with the frame,
  /// while the edge comes on its own channel and can be a frame stale after a
  /// pane move.
  static DuoPose? resolvePose(
    EdgeInsets viewPadding,
    SystemVerticalBarEdge edge,
  ) {
    final side =
        barSide(viewPadding) ??
        switch (edge) {
          SystemVerticalBarEdge.left => DuoBarSide.left,
          SystemVerticalBarEdge.right => DuoBarSide.right,
          SystemVerticalBarEdge.none || SystemVerticalBarEdge.unknown => null,
        };
    if (side == null) return null;
    final inset = side == DuoBarSide.left
        ? viewPadding.left
        : viewPadding.right;
    return DuoPose(
      side: side,
      stripWidth: inset > 0 ? inset : kDuoVerticalBarWidth,
      reservedBySystem: inset > 0,
    );
  }

  /// The edge the safe-area insets alone put the bar on, or null where they
  /// say bars stay horizontal. [resolvePose] trusts it first and consults the
  /// system's vertical bar edge only when this returns null.
  ///
  /// Decided from what the system actually reserves rather than from a device
  /// or size class. On iPhone Duo the controls stay aligned with the hardware:
  /// the window has an inset on one side only, with no top inset. That strip
  /// holds the camera and status cluster, and measurements put it on the right
  /// in every pose that has it: the inner display in both landscape rotations,
  /// and the cover display while folded. A pane that does not touch the
  /// hardware strip reports no inset at all, which is why the leading Split
  /// View pane (the one real left-bar case) needs the system's edge instead.
  /// The strip is absent where bars stay horizontal:
  ///
  /// * any other iPhone in portrait has a top inset, and in landscape has
  ///   equal insets on both sides;
  /// * an iPad has no side inset;
  /// * the Duo inner display in portrait has a top inset.
  ///
  /// A left inset is handled too, although no pose has been observed to
  /// report one.
  ///
  /// Pass the *view* padding: it is known on the very first frame, and unlike
  /// `padding` it is not consumed by a `SafeArea` further up the tree.
  static DuoBarSide? barSide(EdgeInsets viewPadding) {
    if (viewPadding.top != 0) return null;
    if (viewPadding.right > 0 && viewPadding.left == 0) return DuoBarSide.right;
    if (viewPadding.left > 0 && viewPadding.right == 0) return DuoBarSide.left;
    return null;
  }

  /// Whether toolbar controls belong in a vertical bar right now.
  static bool isVerticalBarPose(EdgeInsets viewPadding) =>
      barSide(viewPadding) != null;

  /// Free space to keep above and below the controls, so that they clear the
  /// camera and status cluster wherever the current rotation puts them: at
  /// the top of the strip in portrait, at the bottom of it in one landscape
  /// rotation. Measured on the system's own bar: controls start right at the
  /// edge of a region, and keep [kDuoBarEdgeMargin] from a free window edge.
  static ({double top, double bottom}) barInsets({
    required Size size,
    required DuoPose pose,
    required List<ReservedRegion> regions,
  }) {
    // A strip the system did not reserve has no camera or status cluster in
    // it. No region will ever be reported there, so don't wait for one.
    if (!pose.reservedBySystem) {
      return (top: kDuoBarOnlyTopMargin, bottom: kDuoBarEdgeMargin);
    }
    final stripStart = pose.onLeft ? 0.0 : size.width - pose.stripWidth;
    final stripEnd = pose.onLeft ? pose.stripWidth : size.width;

    // Only regions that really lie in this window's strip count. While the
    // device folds, unfolds or rotates, a reading taken in the previous pose
    // can still be around for a moment; its region sits elsewhere.
    final inStrip = regions.where(
      (r) =>
          r.kind == ReservedRegionKind.occlusion &&
          r.isActive &&
          r.bounds.right > stripStart &&
          r.bounds.left < stripEnd &&
          r.bounds.right <= size.width + 1 &&
          r.bounds.bottom <= size.height + 1,
    );

    double? top;
    double? bottom;
    for (final region in inStrip) {
      if (region.bounds.center.dy < size.height / 2) {
        if (top == null || region.bounds.bottom > top) {
          top = region.bounds.bottom;
        }
      } else {
        final room = size.height - region.bounds.top + kDuoBarRegionGap;
        if (bottom == null || room > bottom) bottom = room;
      }
    }

    // Every system-reserved strip has the camera or the status cluster
    // somewhere in it, so an empty strip means nothing has been reported for
    // this pose yet (regions arrive a moment after launch and after a pose
    // change). Until then stay clear of where the cluster can be instead of
    // starting underneath it.
    final unknown = inStrip.isEmpty;
    return (
      top:
          top ??
          (unknown ? kDuoStatusClusterFallbackHeight : kDuoBarEdgeMargin),
      bottom: bottom ?? kDuoBarEdgeMargin,
    );
  }

  /// Top clearance of [barInsets].
  static double topClearance({
    required Size size,
    required DuoPose pose,
    required List<ReservedRegion> regions,
  }) => barInsets(size: size, pose: pose, regions: regions).top;
}

/// Hands the resolved [DuoPose] to everything below, so the bar, the title
/// and the page body agree on one decision instead of re-reading insets the
/// host may have adjusted.
class DuoPoseScope extends InheritedWidget {
  const DuoPoseScope({super.key, required this.pose, required super.child});

  /// The pose in effect, or null where bars stay horizontal.
  final DuoPose? pose;

  /// The nearest scope, or null when there is none. Tells "no scope" apart
  /// from a scope whose pose is null (a decision for horizontal bars).
  static DuoPoseScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DuoPoseScope>();

  /// The pose in effect here. Without a scope, derived from the insets alone.
  static DuoPose? of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope.pose;
    return DuoLayout.resolvePose(
      MediaQuery.viewPaddingOf(context),
      SystemVerticalBarEdge.unknown,
    );
  }

  @override
  bool updateShouldNotify(DuoPoseScope oldWidget) => pose != oldWidget.pose;
}

/// Space the system leaves between the controls and a free edge of the
/// window, above the first control and below the tab capsule.
const double kDuoBarEdgeMargin = 24.0;

/// Space the system leaves between the controls and a reserved region that
/// sits below them.
const double kDuoBarRegionGap = 11.0;

/// The band at the top of the page that holds the title on iPhone Duo, as
/// UIKit lays it out in this window: the title at the leading edge with the
/// controls in the trailing bar, and the page content below it.
///
/// The positions come from a native navigation controller measured in the
/// window ([SystemVerticalBar.titleBand]). Until that reading arrives, they
/// follow Flutter's own navigation bar: content below the status area and
/// one bar height, and the title centred in that bar.
abstract final class DuoTitleBand {
  /// The measured band, or the fallback for [context].
  static DuoTitleBandMetrics of(BuildContext context) {
    final measured = SystemVerticalBar.titleBand.value;
    if (measured != null) return measured;
    final top = MediaQuery.viewPaddingOf(context).top;
    final barMid = top + kMinInteractiveDimensionCupertino / 2;
    return DuoTitleBandMetrics(
      contentTop: top + kMinInteractiveDimensionCupertino,
      largeTitleMidY: barMid,
      inlineTitleMidY: barMid,
      titleMinX: NavigationToolbar.kMiddleSpacing,
    );
  }

  /// Rebuilds [builder] when a new measurement arrives.
  static Widget builder({
    required Widget Function(BuildContext context, DuoTitleBandMetrics band)
    builder,
  }) {
    return ValueListenableBuilder<DuoTitleBandMetrics?>(
      valueListenable: SystemVerticalBar.titleBand,
      builder: (context, _, _) => builder(context, of(context)),
    );
  }
}
