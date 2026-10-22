import 'package:adaptive_platform_ui/src/devices/duo/reserved_region.dart';
import 'package:adaptive_platform_ui/src/devices/duo/system_vertical_bar.dart';
import 'package:adaptive_platform_ui/src/devices/duo/duo_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry measured on the iPhone Duo inner display (iOS 27.1 simulator).
const Size duoLandscape = Size(951, 669);
const EdgeInsets duoPadding = EdgeInsets.only(right: 84, bottom: 34);
const ReservedRegion duoCamera = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(867, 0, 951, 120),
  isActive: true,
);
const ReservedRegion duoFlatFold = ReservedRegion(
  kind: ReservedRegionKind.division,
  bounds: Rect.fromLTRB(455.5, 0, 495.5, 669),
  isActive: false,
);

/// The cover display while folded.
const Size duoCover = Size(466, 678);
const ReservedRegion duoCoverCluster = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTRB(382, 0, 466, 170),
  isActive: true,
);

/// Split View on the inner display, measured on the iOS 27.1 simulator.
const Size duoSplitPane = Size(469, 669);
const EdgeInsets duoLeftPanePadding = EdgeInsets.only(bottom: 34); // leading
const EdgeInsets duoRightPanePadding = EdgeInsets.only(
  right: 84,
  bottom: 34,
); // trailing

/// The pose the insets alone resolve to, which is what a window with no
/// system reading gets.
DuoPose poseOf(EdgeInsets padding) =>
    DuoLayout.resolvePose(padding, SystemVerticalBarEdge.unknown)!;

void main() {
  group('DuoLayout: detection', () {
    test(
      'the inner display and the folded cover display: strip on the right',
      () {
        // Both measured with the same insets.
        expect(DuoLayout.barSide(duoPadding), DuoBarSide.right);
        expect(DuoLayout.isVerticalBarPose(duoPadding), isTrue);
      },
    );

    test('a left inset is handled by the inset fallback', () {
      // Not a pose seen on hardware or in the simulator (both landscape
      // rotations put the strip on the right); kept as the fallback.
      const rotated = EdgeInsets.only(left: 84, bottom: 34);
      expect(DuoLayout.barSide(rotated), DuoBarSide.left);
      expect(poseOf(rotated).stripWidth, 84);
    });

    test('an ordinary iPhone in portrait has a top inset', () {
      expect(
        DuoLayout.barSide(const EdgeInsets.only(top: 62, bottom: 34)),
        isNull,
      );
    });

    test('an ordinary iPhone in landscape is inset on both sides', () {
      expect(
        DuoLayout.barSide(
          const EdgeInsets.only(left: 62, right: 62, bottom: 21),
        ),
        isNull,
      );
    });

    test('an iPad has no side inset', () {
      expect(
        DuoLayout.barSide(const EdgeInsets.only(top: 24, bottom: 20)),
        isNull,
      );
    });
  });

  group('DuoLayout.resolvePose', () {
    test(
      'leading Split View pane: the system edge alone puts the bar on the left',
      () {
        final pose = DuoLayout.resolvePose(
          duoLeftPanePadding,
          SystemVerticalBarEdge.left,
        )!;
        expect(pose.side, DuoBarSide.left);
        expect(pose.stripWidth, kDuoVerticalBarWidth);
        expect(pose.reservedBySystem, isFalse);
      },
    );

    test('the insets win over a stale edge after a pane move', () {
      // The edge arrives on its own channel and can still say "left" for a
      // frame after the window moved to the trailing pane.
      final pose = DuoLayout.resolvePose(
        duoRightPanePadding,
        SystemVerticalBarEdge.left,
      )!;
      expect(pose.side, DuoBarSide.right);
      expect(pose.stripWidth, 84);
      expect(pose.reservedBySystem, isTrue);
    });

    test('trailing Split View pane: the strip is the system inset', () {
      for (final edge in [
        SystemVerticalBarEdge.right,
        SystemVerticalBarEdge.unknown,
      ]) {
        final pose = DuoLayout.resolvePose(duoRightPanePadding, edge)!;
        expect(pose.side, DuoBarSide.right);
        expect(pose.stripWidth, 84);
        expect(pose.reservedBySystem, isTrue);
      }
    });

    test('without a system reading the insets still decide', () {
      expect(
        DuoLayout.resolvePose(duoPadding, SystemVerticalBarEdge.unknown)!.side,
        DuoBarSide.right,
      );
      expect(
        DuoLayout.resolvePose(
          duoLeftPanePadding,
          SystemVerticalBarEdge.unknown,
        ),
        isNull,
      );
    });

    test('"none" never removes a pose the insets find', () {
      expect(
        DuoLayout.resolvePose(duoPadding, SystemVerticalBarEdge.none),
        isNotNull,
      );
    });

    test('an ordinary iPhone or iPad stays horizontal', () {
      const iPhonePortrait = EdgeInsets.only(top: 62, bottom: 34);
      const iPhoneLandscape = EdgeInsets.only(left: 62, right: 62, bottom: 21);
      const iPad = EdgeInsets.only(top: 24, bottom: 20);
      for (final padding in [iPhonePortrait, iPhoneLandscape, iPad]) {
        for (final edge in [
          SystemVerticalBarEdge.none,
          SystemVerticalBarEdge.unknown,
        ]) {
          expect(DuoLayout.resolvePose(padding, edge), isNull);
        }
      }
    });

    test('the wire format maps to a physical edge, unknown otherwise', () {
      expect(
        SystemVerticalBarEdge.fromWire('left'),
        SystemVerticalBarEdge.left,
      );
      expect(
        SystemVerticalBarEdge.fromWire('right'),
        SystemVerticalBarEdge.right,
      );
      expect(
        SystemVerticalBarEdge.fromWire('none'),
        SystemVerticalBarEdge.none,
      );
      expect(
        SystemVerticalBarEdge.fromWire('unsupported'),
        SystemVerticalBarEdge.unknown,
      );
      expect(
        SystemVerticalBarEdge.fromWire(null),
        SystemVerticalBarEdge.unknown,
      );
    });
  });

  group('DuoLayout: clearance follows the camera through rotations', () {
    const coverLandscape = Size(678, 466);

    test(
      'landscape, strip right: the camera is at the bottom of the strip',
      () {
        final insets = DuoLayout.barInsets(
          size: coverLandscape,
          pose: poseOf(duoPadding),
          regions: const [
            ReservedRegion(
              kind: ReservedRegionKind.occlusion,
              bounds: Rect.fromLTWH(594, 384, 84, 82),
              isActive: true,
            ),
          ],
        );
        expect(insets.top, kDuoBarEdgeMargin);
        expect(insets.bottom, 466 - 384 + kDuoBarRegionGap);
      },
    );

    test(
      'inset fallback, strip left: the camera is at the top of the strip',
      () {
        // The left-inset pose was not observed on hardware or in the simulator.
        final insets = DuoLayout.barInsets(
          size: coverLandscape,
          pose: poseOf(const EdgeInsets.only(left: 84, bottom: 34)),
          regions: const [
            ReservedRegion(
              kind: ReservedRegionKind.occlusion,
              bounds: Rect.fromLTWH(0, 0, 84, 82),
              isActive: true,
            ),
          ],
        );
        expect(insets.top, 82);
        expect(insets.bottom, kDuoBarEdgeMargin);
      },
    );

    test('a bar-only strip keeps edge margins and ignores regions', () {
      final insets = DuoLayout.barInsets(
        size: duoSplitPane,
        pose: const DuoPose(
          side: DuoBarSide.left,
          stripWidth: 84,
          reservedBySystem: false,
        ),
        regions: const [],
      );
      // Not kDuoStatusClusterFallbackHeight: no region will ever arrive.
      expect(insets.top, kDuoBarOnlyTopMargin);
      expect(insets.bottom, kDuoBarEdgeMargin);

      // Even a region in the strip (a stale reading from another pose) does
      // not move the bar.
      final withRegion = DuoLayout.barInsets(
        size: duoSplitPane,
        pose: const DuoPose(
          side: DuoBarSide.left,
          stripWidth: 84,
          reservedBySystem: false,
        ),
        regions: const [
          ReservedRegion(
            kind: ReservedRegionKind.occlusion,
            bounds: Rect.fromLTRB(0, 0, 84, 120),
            isActive: true,
          ),
        ],
      );
      expect(withRegion, insets);
    });
  });

  group('DuoLayout: geometry', () {
    test('the bar takes the strip the system reserves', () {
      expect(poseOf(duoPadding).stripWidth, 84);
      expect(poseOf(duoPadding).bandWidth, 84 + kDuoVerticalBarBezelInset);
    });

    test('falls back when no inset is reported on the bar side', () {
      final pose = DuoLayout.resolvePose(
        EdgeInsets.zero,
        SystemVerticalBarEdge.right,
      )!;
      expect(pose.stripWidth, kDuoVerticalBarWidth);
      expect(kDuoVerticalBarWidth, 84);
    });

    test('controls start below the camera, not under it', () {
      expect(
        DuoLayout.topClearance(
          size: duoLandscape,
          pose: poseOf(duoPadding),
          regions: const [duoCamera, duoFlatFold],
        ),
        120,
      );
    });

    test('on the cover display too', () {
      expect(
        DuoLayout.topClearance(
          size: duoCover,
          pose: poseOf(duoPadding),
          regions: const [duoCoverCluster],
        ),
        170,
      );
    });

    test('a stale region from the other display is ignored while folding', () {
      // Just folded: the window is the cover display, the regions are still
      // the inner display's. Using them would park the bar 50pt too high.
      expect(
        DuoLayout.topClearance(
          size: duoCover,
          pose: poseOf(duoPadding),
          regions: const [duoCamera],
        ),
        kDuoStatusClusterFallbackHeight,
      );
    });

    test('stays clear of the cluster until regions are reported', () {
      expect(
        DuoLayout.topClearance(
          size: duoLandscape,
          pose: poseOf(duoPadding),
          regions: const [],
        ),
        kDuoStatusClusterFallbackHeight,
      );
    });

    test('inactive or non-overlapping occlusions are ignored', () {
      const inactive = ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: Rect.fromLTRB(867, 0, 951, 120),
        isActive: false,
      );
      const leftSide = ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: Rect.fromLTRB(0, 0, 80, 120),
        isActive: true,
      );
      expect(
        DuoLayout.topClearance(
          size: duoLandscape,
          pose: poseOf(const EdgeInsets.only(right: 84)),
          regions: const [inactive, leftSide, duoFlatFold],
        ),
        kDuoStatusClusterFallbackHeight,
      );
    });
  });
}
