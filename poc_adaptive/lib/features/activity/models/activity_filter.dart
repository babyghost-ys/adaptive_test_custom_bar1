import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

enum ActivityKind { all, bought, dividends }

/// The day of demo row [index]: one row per day, newest first, from 19 Oct.
DateTime activityDate(int index) => DateTime(2026, 10, 19 - index);

/// How far back to look. The demo rows are one per day, newest first.
enum ActivityPeriod {
  all(12),
  week(7),
  threeDays(3);

  const ActivityPeriod(this.days);
  final int days;
}

class ActivityFilter extends Equatable {
  const ActivityFilter({
    this.kind = ActivityKind.all,
    this.symbols = const {},
    this.period = ActivityPeriod.all,
    this.minAmount = 0,
    this.since,
  });

  static const double maxAmount = 600;

  final ActivityKind kind;

  /// Empty means every symbol.
  final Set<String> symbols;
  final ActivityPeriod period;
  final double minAmount;

  /// Only activity on or after this day. Null means any date.
  final DateTime? since;

  int get activeCount =>
      (kind != ActivityKind.all ? 1 : 0) +
      (symbols.isEmpty ? 0 : 1) +
      (period != ActivityPeriod.all ? 1 : 0) +
      (minAmount > 0 ? 1 : 0) +
      (since != null ? 1 : 0);

  ActivityFilter copyWith({
    ActivityKind? kind,
    Set<String>? symbols,
    ActivityPeriod? period,
    double? minAmount,
    DateTime? since,
    bool clearSince = false,
  }) => ActivityFilter(
    kind: kind ?? this.kind,
    symbols: symbols ?? this.symbols,
    period: period ?? this.period,
    minAmount: minAmount ?? this.minAmount,
    since: clearSince ? null : (since ?? this.since),
  );

  bool allows({
    required bool dividend,
    required String symbol,
    required int day,
    required double amount,
    required DateTime date,
  }) =>
      switch (kind) {
        ActivityKind.all => true,
        ActivityKind.bought => !dividend,
        ActivityKind.dividends => dividend,
      } &&
      (symbols.isEmpty || symbols.contains(symbol)) &&
      day < period.days &&
      amount >= minAmount &&
      (since == null ||
          !date.isBefore(DateTime(since!.year, since!.month, since!.day)));

  /// Indices of the demo rows that pass the filter. Every third row is a
  /// VOO dividend; the rest are purchases of the cycling demo assets.
  List<int> matching(List<Asset> assets) => [
    for (var i = 0; i < 12; i++)
      if (allows(
        dividend: i % 3 == 0,
        symbol: i % 3 == 0 ? 'VOO' : assets[i % 6].symbol,
        day: i,
        amount: i % 3 == 0 ? 128.40 : assets[i % 6].price,
        date: activityDate(i),
      ))
        i,
  ];

  @override
  List<Object?> get props => [kind, symbols, period, minAmount, since];
}
