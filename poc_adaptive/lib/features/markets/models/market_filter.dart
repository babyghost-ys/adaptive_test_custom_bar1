import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';

enum MarketMovement { all, gainers, losers }

enum MarketSort { symbol, price, change }

class MarketFilter extends Equatable {
  const MarketFilter({
    this.movement = MarketMovement.all,
    this.sort = MarketSort.symbol,
    this.maxPrice = ceiling,
    this.types = const {},
    this.minChange = floor,
    this.symbols = const {},
  });

  static const double ceiling = 600;
  static const double floor = -5;

  final MarketMovement movement;
  final MarketSort sort;
  final double maxPrice;

  /// Empty means every type.
  final Set<HoldingType> types;
  final double minChange;

  /// Empty means every symbol.
  final Set<String> symbols;

  int get activeCount =>
      (movement != MarketMovement.all ? 1 : 0) +
      (sort != MarketSort.symbol ? 1 : 0) +
      (maxPrice < ceiling ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (minChange > floor ? 1 : 0) +
      (symbols.isEmpty ? 0 : 1);

  MarketFilter copyWith({
    MarketMovement? movement,
    MarketSort? sort,
    double? maxPrice,
    Set<HoldingType>? types,
    double? minChange,
    Set<String>? symbols,
  }) => MarketFilter(
    movement: movement ?? this.movement,
    sort: sort ?? this.sort,
    maxPrice: maxPrice ?? this.maxPrice,
    types: types ?? this.types,
    minChange: minChange ?? this.minChange,
    symbols: symbols ?? this.symbols,
  );

  List<Asset> apply(List<Asset> source) {
    final result = source
        .where(
          (a) =>
              a.price <= maxPrice &&
              a.change >= minChange &&
              (types.isEmpty || types.contains(holdingType(a))) &&
              (symbols.isEmpty || symbols.contains(a.symbol)) &&
              switch (movement) {
                MarketMovement.all => true,
                MarketMovement.gainers => a.change > 0,
                MarketMovement.losers => a.change < 0,
              },
        )
        .toList();
    result.sort(
      (a, b) => switch (sort) {
        MarketSort.symbol => a.symbol.compareTo(b.symbol),
        MarketSort.price => b.price.compareTo(a.price),
        MarketSort.change => b.change.compareTo(a.change),
      },
    );
    return result;
  }

  @override
  List<Object> get props => [
    movement,
    sort,
    maxPrice,
    types,
    minChange,
    symbols,
  ];
}
