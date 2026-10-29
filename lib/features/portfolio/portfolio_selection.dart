import 'package:flutter/foundation.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

/// Identifies an asset opened from Portfolio, so it can move into its detail
/// column when the available width changes.
class PortfolioAssetOrigin {
  const PortfolioAssetOrigin({
    required this.filter,
    required this.scrollOffset,
  });
  final ValueNotifier<HoldingsFilter> filter;
  final double scrollOffset;
}
