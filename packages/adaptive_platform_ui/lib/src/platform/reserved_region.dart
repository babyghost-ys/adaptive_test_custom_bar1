import 'package:flutter/widgets.dart';

/// A system-reserved area in Flutter-view logical coordinates.
/// Only occlusions affect toolbar clearance; divisions never obscure controls.
enum ReservedRegionKind { occlusion, division }

@immutable
class ReservedRegion {
  const ReservedRegion({
    required this.kind,
    required this.bounds,
    required this.isActive,
  });

  final ReservedRegionKind kind;
  final Rect bounds;
  final bool isActive;

  static List<ReservedRegion> fromWire(Object? value) {
    if (value is! List) return const [];
    final regions = <ReservedRegion>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final x = entry['x'];
      final y = entry['y'];
      final width = entry['width'];
      final height = entry['height'];
      if (x is! num || y is! num || width is! num || height is! num) continue;
      if (![x, y, width, height].every((v) => v.isFinite) ||
          width <= 0 ||
          height <= 0)
        continue;
      regions.add(
        ReservedRegion(
          kind: ReservedRegionKind.occlusion,
          bounds: Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            width.toDouble(),
            height.toDouble(),
          ),
          isActive: true,
        ),
      );
    }
    return List.unmodifiable(regions);
  }

  @override
  bool operator ==(Object other) =>
      other is ReservedRegion &&
      kind == other.kind &&
      bounds == other.bounds &&
      isActive == other.isActive;

  @override
  int get hashCode => Object.hash(kind, bounds, isActive);
}
