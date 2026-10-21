import 'package:flutter_bloc/flutter_bloc.dart';

class Asset {
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
}

const assets = [
  Asset('AAPL', 'Apple', 237.49, 1.24, 80, 0xFF20232A),
  Asset('NVDA', 'NVIDIA', 142.87, 2.81, 120, 0xFF719B39),
  Asset('VOO', 'Vanguard S&P 500', 538.26, 0.86, 90, 0xFFB52E39),
  Asset('MSFT', 'Microsoft', 428.76, -0.42, 60, 0xFF477AC2),
  Asset('AMZN', 'Amazon', 219.32, 1.67, 45, 0xFFB97824),
  Asset('VTI', 'Vanguard Total Market', 291.42, 0.72, 36, 0xFF8866A7),
];

sealed class InvestmentEvent {}

class AccountSelected extends InvestmentEvent {
  AccountSelected(this.index);
  final int index;
}

class RangeSelected extends InvestmentEvent {
  RangeSelected(this.index);
  final int index;
}

class WatchToggled extends InvestmentEvent {
  WatchToggled(this.symbol);
  final String symbol;
}

class InvestmentState {
  const InvestmentState({
    this.account = 0,
    this.range = 2,
    this.watchlist = const {'AAPL', 'NVDA', 'VOO'},
  });
  final int account, range;
  final Set<String> watchlist;
  InvestmentState copy({int? account, int? range, Set<String>? watchlist}) =>
      InvestmentState(
        account: account ?? this.account,
        range: range ?? this.range,
        watchlist: watchlist ?? this.watchlist,
      );
  double get accountScale => [1.0, 0.6, 0.3, 0.1][account];
  double get invested =>
      assets.fold<double>(
        0,
        (total, asset) => total + asset.price * asset.shares,
      ) *
      accountScale;
  double get cash => 9980.62 * accountScale;
  double get balance => invested + cash;
  String get accountName =>
      ['All accounts', 'Personal', 'Retirement', 'Tax-free'][account];
}

class InvestmentBloc extends Bloc<InvestmentEvent, InvestmentState> {
  InvestmentBloc() : super(const InvestmentState()) {
    on<AccountSelected>(
      (event, emit) => emit(state.copy(account: event.index)),
    );
    on<RangeSelected>((event, emit) => emit(state.copy(range: event.index)));
    on<WatchToggled>((event, emit) {
      final next = {...state.watchlist};
      next.contains(event.symbol)
          ? next.remove(event.symbol)
          : next.add(event.symbol);
      emit(state.copy(watchlist: next));
    });
  }
}
