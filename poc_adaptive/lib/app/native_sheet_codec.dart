import 'package:native_widgets_on_duo/features/activity/models/activity_filter.dart';
import 'package:native_widgets_on_duo/features/markets/models/market_filter.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';
import 'package:native_widgets_on_duo/features/portfolio/models/holdings_filter.dart';
import 'package:native_widgets_on_duo/features/watchlist/models/watchlist_filter.dart';

/// Sheet engines have independent isolates. Only these plain values cross
/// their platform channels; draft objects stay owned by their sheet.
abstract final class NativeSheetCodec {
  static Object? encode(Object? value) => switch (value) {
    null => null,
    WatchlistFilter filter => {
      'movement': filter.movement.name,
      'maxPrice': filter.maxPrice,
      'types': filter.types.map((type) => type.name).toList(),
    },
    MarketFilter filter => {
      'movement': filter.movement.name,
      'sort': filter.sort.name,
      'maxPrice': filter.maxPrice,
      'types': filter.types.map((type) => type.name).toList(),
      'minChange': filter.minChange,
      'symbols': filter.symbols.toList(),
    },
    ActivityFilter filter => {
      'kind': filter.kind.name,
      'symbols': filter.symbols.toList(),
      'period': filter.period.name,
      'minAmount': filter.minAmount,
      'since': filter.since?.toIso8601String(),
    },
    OrdersFilter filter => {
      'side': filter.side?.name,
      'sort': filter.sort.name,
      'minValue': filter.minValue,
      'limitOnly': filter.limitOnly,
      'showCancelled': filter.showCancelled,
      'accounts': filter.accounts.map((account) => account.name).toList(),
    },
    DateTime date => date.toIso8601String(),
    Set<Account> accounts => accounts.map((account) => account.name).toList(),
    String text => text,
    _ => throw ArgumentError.value(value, 'value', 'Unsupported sheet result'),
  };

  static Map<Object?, Object?> _map(Object value) =>
      Map<Object?, Object?>.from(value as Map);

  static Set<String> _strings(Object? value) =>
      (value as List).cast<String>().toSet();

  static WatchlistFilter watchlist(Object value) {
    final data = _map(value);
    return WatchlistFilter(
      movement: MarketMovement.values.byName(data['movement'] as String),
      maxPrice: (data['maxPrice'] as num).toDouble(),
      types: _strings(data['types']).map(HoldingType.values.byName).toSet(),
    );
  }

  static MarketFilter markets(Object value) {
    final data = _map(value);
    return MarketFilter(
      movement: MarketMovement.values.byName(data['movement'] as String),
      sort: MarketSort.values.byName(data['sort'] as String),
      maxPrice: (data['maxPrice'] as num).toDouble(),
      types: _strings(data['types']).map(HoldingType.values.byName).toSet(),
      minChange: (data['minChange'] as num).toDouble(),
      symbols: _strings(data['symbols']),
    );
  }

  static ActivityFilter activity(Object value) {
    final data = _map(value);
    return ActivityFilter(
      kind: ActivityKind.values.byName(data['kind'] as String),
      symbols: _strings(data['symbols']),
      period: ActivityPeriod.values.byName(data['period'] as String),
      minAmount: (data['minAmount'] as num).toDouble(),
      since: data['since'] == null ? null : date(data['since']!),
    );
  }

  static OrdersFilter orders(Object value) {
    final data = _map(value);
    return OrdersFilter(
      side: data['side'] == null
          ? null
          : OrderSide.values.byName(data['side'] as String),
      sort: OrderSort.values.byName(data['sort'] as String),
      minValue: (data['minValue'] as num).toDouble(),
      limitOnly: data['limitOnly'] as bool,
      showCancelled: data['showCancelled'] as bool,
      accounts: accounts(data['accounts']!),
    );
  }

  static DateTime date(Object value) => DateTime.parse(value as String);

  static Set<Account> accounts(Object value) =>
      _strings(value).map(Account.values.byName).toSet();
}
