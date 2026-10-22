import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';

class WatchlistFilter extends Equatable {
  const WatchlistFilter({this.movement = MarketMovement.all});
  final MarketMovement movement;

  int get activeCount => movement == MarketMovement.all ? 0 : 1;

  bool allows(Asset a) => switch (movement) {
    MarketMovement.all => true,
    MarketMovement.gainers => a.change > 0,
    MarketMovement.losers => a.change < 0,
  };

  @override
  List<Object> get props => [movement];
}
