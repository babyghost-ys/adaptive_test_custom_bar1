import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum OrderSide { buy, sell }

enum OrderStatus { open, filled, cancelled }

enum Account {
  personal('Personal', Icons.person_outline_rounded),
  isa('ISA', Icons.savings_outlined),
  pension('Pension', Icons.account_balance_outlined);

  const Account(this.title, this.icon);
  final String title;
  final IconData icon;
}

class Order extends Equatable {
  const Order(
    this.symbol,
    this.side,
    this.quantity,
    this.price,
    this.status,
    this.account, {
    this.limit = false,
  });

  final String symbol;
  final OrderSide side;
  final double quantity, price;
  final OrderStatus status;
  final Account account;

  /// A limit order rather than a market order.
  final bool limit;

  double get value => quantity * price;

  @override
  List<Object> get props => [
    symbol,
    side,
    quantity,
    price,
    status,
    account,
    limit,
  ];
}

/// Newest first.
const orders = [
  Order('NVDA', OrderSide.buy, 10, 142.87, OrderStatus.open, Account.personal),
  Order(
    'VOO',
    OrderSide.buy,
    4,
    538.26,
    OrderStatus.filled,
    Account.isa,
    limit: true,
  ),
  Order(
    'AAPL',
    OrderSide.sell,
    6,
    237.49,
    OrderStatus.filled,
    Account.personal,
  ),
  Order(
    'MSFT',
    OrderSide.buy,
    2,
    428.76,
    OrderStatus.cancelled,
    Account.pension,
    limit: true,
  ),
  Order('VTI', OrderSide.buy, 12, 291.42, OrderStatus.filled, Account.pension),
  Order(
    'AMZN',
    OrderSide.sell,
    8,
    219.32,
    OrderStatus.open,
    Account.isa,
    limit: true,
  ),
  Order('NVDA', OrderSide.sell, 15, 142.87, OrderStatus.filled, Account.isa),
  Order(
    'AAPL',
    OrderSide.buy,
    3,
    237.49,
    OrderStatus.cancelled,
    Account.personal,
  ),
  Order(
    'VOO',
    OrderSide.sell,
    1,
    538.26,
    OrderStatus.open,
    Account.pension,
    limit: true,
  ),
  Order('MSFT', OrderSide.buy, 5, 428.76, OrderStatus.filled, Account.personal),
];
