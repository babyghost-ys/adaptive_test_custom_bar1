import 'package:flutter/material.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/filter_section_header.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/page_scroll.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';
import 'package:native_widgets_on_duo/features/orders/view/orders_filter_sheet.dart';

class Orders extends StatefulWidget {
  const Orders({super.key});
  @override
  State<Orders> createState() => _OrdersState();
}

class _OrdersState extends State<Orders> {
  OrdersFilter filter = const OrdersFilter();

  Future<void> openFilters() async {
    final result = await showOrdersFilterSheet(context, filter);
    if (result != null && mounted) setState(() => filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final rows = filter.apply(orders);
    return PageScroll(
      storageKey: 'orders',
      children: [
        FilterSectionHeader(
          title: 'Recent orders',
          onPressed: openFilters,
          activeCount: filter.activeCount,
        ),
        const SizedBox(height: 20),
        for (final o in rows) _OrderRow(order: o),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Icon(Icons.search_off_rounded, size: 40, color: muted),
          ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final buy = order.side == OrderSide.buy;
    final cancelled = order.status == OrderStatus.cancelled;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 9),
      leading: CircleAvatar(
        backgroundColor: buy
            ? const Color(0xFFE5EBE1)
            : const Color(0xFFF3E1E2),
        child: Icon(
          buy ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: buy ? green : red,
          size: 20,
        ),
      ),
      title: label(
        '${order.quantity.toStringAsFixed(0)} ${order.symbol}',
        weight: FontWeight.w500,
        color: cancelled ? muted : ink,
      ),
      subtitle: Row(
        children: [
          Icon(order.account.icon, size: 14, color: muted),
          if (order.limit) ...[
            const SizedBox(width: 6),
            const Icon(Icons.price_change_outlined, size: 14, color: muted),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          label(money(order.value), size: 14, color: cancelled ? muted : ink),
          const SizedBox(width: 10),
          Icon(
            switch (order.status) {
              OrderStatus.open => Icons.schedule_rounded,
              OrderStatus.filled => Icons.check_circle_rounded,
              OrderStatus.cancelled => Icons.block_rounded,
            },
            size: 18,
            color: order.status == OrderStatus.filled ? green : muted,
          ),
        ],
      ),
    );
  }
}
