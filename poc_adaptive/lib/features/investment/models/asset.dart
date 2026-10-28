import 'package:equatable/equatable.dart';

class Asset extends Equatable {
  const Asset(
    this.symbol,
    this.name,
    this.price,
    this.change,
    this.shares,
    this.color,
  );
  final String symbol, name;
  final double price, change, shares;
  final int color;

  @override
  List<Object> get props => [symbol, name, price, change, shares, color];
}
