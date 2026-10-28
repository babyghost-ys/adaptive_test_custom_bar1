part of 'investment_bloc.dart';

sealed class InvestmentEvent extends Equatable {
  const InvestmentEvent();
}

final class AccountSelected extends InvestmentEvent {
  const AccountSelected(this.index);
  final int index;

  @override
  List<Object> get props => [index];
}

final class RangeSelected extends InvestmentEvent {
  const RangeSelected(this.index);
  final int index;

  @override
  List<Object> get props => [index];
}

final class WatchToggled extends InvestmentEvent {
  const WatchToggled(this.symbol);
  final String symbol;

  @override
  List<Object> get props => [symbol];
}
