import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

class WatchlistFilter extends Equatable {
  const WatchlistFilter({
    this.movement = MarketMovement.all,
    this.maxPrice = ceiling,
    this.types = const {},
  });

  static const double ceiling = 600;

  final MarketMovement movement;
  final double maxPrice;

  /// Empty means every type.
  final Set<HoldingType> types;

  int get activeCount =>
      (movement == MarketMovement.all ? 0 : 1) +
      (maxPrice < ceiling ? 1 : 0) +
      (types.isEmpty ? 0 : 1);

  WatchlistFilter copyWith({
    MarketMovement? movement,
    double? maxPrice,
    Set<HoldingType>? types,
  }) => WatchlistFilter(
    movement: movement ?? this.movement,
    maxPrice: maxPrice ?? this.maxPrice,
    types: types ?? this.types,
  );

  bool allows(Asset a) =>
      a.price <= maxPrice &&
      (types.isEmpty || types.contains(holdingType(a))) &&
      switch (movement) {
        MarketMovement.all => true,
        MarketMovement.gainers => a.change > 0,
        MarketMovement.losers => a.change < 0,
      };

  @override
  List<Object> get props => [movement, maxPrice, types];
}
