import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reserved_region.dart';

/// Where the system places its vertical bar for this window, as a physical
/// side (`UITraitCollection.verticalBarEdge`, iOS 27.1).
enum SystemVerticalBarEdge {
  /// No reading: not iOS, iOS < 27.1, or the first reading has not arrived.
  unknown,

  /// The system keeps horizontal bars here.
  none,

  /// The system puts its vertical bar on the left edge.
  left,

  /// The system puts its vertical bar on the right edge.
  right;

  /// The edge for a value sent over the channel; anything unrecognised
  /// (including the native "unsupported") is [unknown].
  static SystemVerticalBarEdge fromWire(Object? value) => switch (value) {
    'none' => none,
    'left' => left,
    'right' => right,
    _ => unknown,
  };
}

/// The system's vertical bar edge, streamed from the native side.
///
/// One shared subscription: an [EventChannel] supports a single native
/// listener, and both the toolbar host and every scaffold without a host need
/// the value.
abstract final class SystemVerticalBar {
  static const EventChannel _channel = EventChannel(
    'adaptive_platform_ui/vertical_bar_edge',
  );
  static final ValueNotifier<SystemVerticalBarEdge> _edge = ValueNotifier(
    SystemVerticalBarEdge.unknown,
  );
  static StreamSubscription<Object?>? _sub;
  static final ValueNotifier<List<ReservedRegion>> _regions = ValueNotifier(
    const [],
  );

  /// Latest camera/status occlusions, without starting a platform subscription.
  static List<ReservedRegion> get currentRegions => _regions.value;

  /// Shares the edge subscription; updates even when only region bounds change.
  static ValueListenable<List<ReservedRegion>> get regions {
    edge;
    return _regions;
  }

  static const MethodChannel _titleBandChannel = MethodChannel(
    'adaptive_platform_ui/duo_title_band',
  );
  static final ValueNotifier<DuoTitleBandMetrics?> _titleBand = ValueNotifier(
    null,
  );

  /// The current edge. Starts listening on first use, so only read it where
  /// the channel exists (iOS 26+); it stays [SystemVerticalBarEdge.unknown]
  /// until the first reading arrives.
  static ValueListenable<SystemVerticalBarEdge> get edge {
    _sub ??= _channel.receiveBroadcastStream().listen((value) {
      final map = value is Map ? value : null;
      final regions = ReservedRegion.fromWire(map?['regions']);
      if (!listEquals(_regions.value, regions)) _regions.value = regions;
      _edge.value = SystemVerticalBarEdge.fromWire(map?['edge'] ?? value);
      _measureTitleBand();
    }, onError: (Object _) {});
    return _edge;
  }

  /// Where UIKit lays out a navigation title in this window while it uses a
  /// vertical bar, measured from a hidden native navigation controller.
  /// Null until measured, and while the system keeps horizontal bars.
  static ValueListenable<DuoTitleBandMetrics?> get titleBand {
    edge;
    return _titleBand;
  }

  static Future<void> _measureTitleBand() async {
    final edge = _edge.value;
    if (edge != SystemVerticalBarEdge.left &&
        edge != SystemVerticalBarEdge.right) {
      return;
    }
    try {
      final result = await _titleBandChannel.invokeMapMethod<String, double>(
        'measure',
      );
      if (result != null && _edge.value == edge) {
        _titleBand.value = DuoTitleBandMetrics.fromWire(result);
      }
    } on PlatformException {
      // Keep the previous reading.
    } on MissingPluginException {
      // Older native side: no measurement.
    }
  }
}

/// Where UIKit puts a navigation title on iPhone Duo, in logical pixels from
/// the top-left of the Flutter view, and the type it sets each title in.
@immutable
class DuoTitleBandMetrics {
  const DuoTitleBandMetrics({
    required this.contentTop,
    required this.largeTitleMidY,
    required this.inlineTitleMidY,
    required this.titleMinX,
    this.largeTitleFontSize,
    this.largeTitleFontWeight,
    this.inlineTitleFontSize,
    this.inlineTitleFontWeight,
  });

  /// Where the system starts page content below the title.
  final double contentTop;

  /// Vertical centre of a large title.
  final double largeTitleMidY;

  /// Vertical centre of an inline title.
  final double inlineTitleMidY;

  /// Leading edge of the title.
  final double titleMinX;

  /// Type of a large title; null keeps the theme's.
  final double? largeTitleFontSize;
  final FontWeight? largeTitleFontWeight;

  /// Type of an inline title; null keeps the theme's.
  final double? inlineTitleFontSize;
  final FontWeight? inlineTitleFontWeight;

  static DuoTitleBandMetrics? fromWire(Map<String, double> map) {
    final contentTop = map['contentTop'];
    final large = map['largeTitleMidY'];
    final inline = map['inlineTitleMidY'];
    final minX = map['titleMinX'];
    if (contentTop == null || large == null || inline == null || minX == null) {
      return null;
    }
    return DuoTitleBandMetrics(
      contentTop: contentTop,
      largeTitleMidY: large,
      inlineTitleMidY: inline,
      titleMinX: minX,
      largeTitleFontSize: map['largeTitleFontSize'],
      largeTitleFontWeight: _weight(map['largeTitleFontWeight']),
      inlineTitleFontSize: map['inlineTitleFontSize'],
      inlineTitleFontWeight: _weight(map['inlineTitleFontWeight']),
    );
  }

  /// UIKit's weights from ultra light to black line up with
  /// [FontWeight.values] from w100 to w900.
  static FontWeight? _weight(double? index) {
    if (index == null) return null;
    final i = index.round();
    return i >= 0 && i < FontWeight.values.length ? FontWeight.values[i] : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DuoTitleBandMetrics &&
      other.contentTop == contentTop &&
      other.largeTitleMidY == largeTitleMidY &&
      other.inlineTitleMidY == inlineTitleMidY &&
      other.titleMinX == titleMinX &&
      other.largeTitleFontSize == largeTitleFontSize &&
      other.largeTitleFontWeight == largeTitleFontWeight &&
      other.inlineTitleFontSize == inlineTitleFontSize &&
      other.inlineTitleFontWeight == inlineTitleFontWeight;

  @override
  int get hashCode => Object.hash(
    contentTop,
    largeTitleMidY,
    inlineTitleMidY,
    titleMinX,
    largeTitleFontSize,
    largeTitleFontWeight,
    inlineTitleFontSize,
    inlineTitleFontWeight,
  );
}
