part of 'investment_bloc.dart';

final class InvestmentState extends Equatable {
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

  @override
  List<Object> get props => [account, range, watchlist];
}
