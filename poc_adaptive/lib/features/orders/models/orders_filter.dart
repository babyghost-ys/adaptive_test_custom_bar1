import 'package:equatable/equatable.dart';

import 'package:native_widgets_on_duo/features/orders/models/order.dart';

enum OrderSort { newest, value }

class OrdersFilter extends Equatable {
  const OrdersFilter({
    this.side,
    this.sort = OrderSort.newest,
    this.minValue = 0,
    this.limitOnly = false,
    this.showCancelled = true,
    this.accounts = const {},
  });

  static const double maxValue = 4000;

  /// Null means buys and sells.
  final OrderSide? side;
  final OrderSort sort;
  final double minValue;
  final bool limitOnly;
  final bool showCancelled;

  /// Empty means every account.
  final Set<Account> accounts;

  int get activeCount =>
      (side != null ? 1 : 0) +
      (sort != OrderSort.newest ? 1 : 0) +
      (minValue > 0 ? 1 : 0) +
      (limitOnly ? 1 : 0) +
      (showCancelled ? 0 : 1) +
      (accounts.isEmpty ? 0 : 1);

  OrdersFilter copyWith({
    OrderSide? side,
    bool clearSide = false,
    OrderSort? sort,
    double? minValue,
    bool? limitOnly,
    bool? showCancelled,
    Set<Account>? accounts,
  }) => OrdersFilter(
    side: clearSide ? null : (side ?? this.side),
    sort: sort ?? this.sort,
    minValue: minValue ?? this.minValue,
    limitOnly: limitOnly ?? this.limitOnly,
    showCancelled: showCancelled ?? this.showCancelled,
    accounts: accounts ?? this.accounts,
  );

  bool allows(Order o) =>
      (side == null || o.side == side) &&
      o.value >= minValue &&
      (!limitOnly || o.limit) &&
      (showCancelled || o.status != OrderStatus.cancelled) &&
      (accounts.isEmpty || accounts.contains(o.account));

  List<Order> apply(List<Order> all) {
    final kept = all.where(allows).toList();
    if (sort == OrderSort.value) {
      kept.sort((a, b) => b.value.compareTo(a.value));
    }
    return kept;
  }

  @override
  List<Object?> get props => [
    side,
    sort,
    minValue,
    limitOnly,
    showCancelled,
    accounts,
  ];
}
