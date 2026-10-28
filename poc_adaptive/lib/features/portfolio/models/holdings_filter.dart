import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';

enum HoldingsSort { value, change, symbol }

enum HoldingType { stock, etf }

const _etfs = {'VOO', 'VTI'};

HoldingType holdingType(Asset a) =>
    _etfs.contains(a.symbol) ? HoldingType.etf : HoldingType.stock;

class HoldingsFilter extends Equatable {
  const HoldingsFilter({
    this.sort = HoldingsSort.value,
    this.movement = MarketMovement.all,
    this.types = const {},
    this.symbols = const {},
    this.minValue = 0,
    this.minChange = floor,
  });

  static const double floor = -5;
  static const double maxValue = 50000;

  final HoldingsSort sort;
  final MarketMovement movement;

  /// Empty means every type.
  final Set<HoldingType> types;

  /// Empty means every symbol.
  final Set<String> symbols;
  final double minValue;
  final double minChange;

  int get activeCount =>
      (sort != HoldingsSort.value ? 1 : 0) +
      (movement != MarketMovement.all ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (symbols.isEmpty ? 0 : 1) +
      (minValue > 0 ? 1 : 0) +
      (minChange > floor ? 1 : 0);

  HoldingsFilter copyWith({
    HoldingsSort? sort,
    MarketMovement? movement,
    Set<HoldingType>? types,
    Set<String>? symbols,
    double? minValue,
    double? minChange,
  }) => HoldingsFilter(
    sort: sort ?? this.sort,
    movement: movement ?? this.movement,
    types: types ?? this.types,
    symbols: symbols ?? this.symbols,
    minValue: minValue ?? this.minValue,
    minChange: minChange ?? this.minChange,
  );

  List<Asset> apply(List<Asset> source, double scale) {
    double value(Asset a) => a.price * a.shares * scale;
    final result = source
        .where(
          (a) =>
              value(a) >= minValue &&
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
        HoldingsSort.value => value(b).compareTo(value(a)),
        HoldingsSort.change => b.change.compareTo(a.change),
        HoldingsSort.symbol => a.symbol.compareTo(b.symbol),
      },
    );
    return result;
  }

  @override
  List<Object> get props => [
    sort,
    movement,
    types,
    symbols,
    minValue,
    minChange,
  ];
}
