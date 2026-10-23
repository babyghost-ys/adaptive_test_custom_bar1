import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/core/formatting/money.dart';
import 'package:native_widgets_on_duo/core/widgets/label.dart';
import 'package:native_widgets_on_duo/core/widgets/sheet_frame.dart';
import 'package:native_widgets_on_duo/features/orders/models/order.dart';
import 'package:native_widgets_on_duo/features/orders/models/orders_filter.dart';

/// A native sheet holding the app's own widget, built from the package's
/// native controls: segmented controls, a slider and switches, each a real
/// UIKit view on iOS. The accounts line opens a second native sheet on top,
/// holding another widget of native switches.
Future<OrdersFilter?> showOrdersFilterSheet(
  BuildContext context,
  OrdersFilter current,
) {
  final draft = ValueNotifier(current);
  return AdaptiveNativeSheet.show<OrdersFilter>(
    context: context,
    builder: (_) => OrdersFilterContent(draft: draft),
  ).whenComplete(draft.dispose);
}

class OrdersFilterContent extends StatelessWidget {
  const OrdersFilterContent({super.key, required this.draft});

  final ValueNotifier<OrdersFilter> draft;

  /// Opens the accounts as a second sheet over this one.
  Future<void> _pickAccounts(BuildContext context) async {
    final picked = await showAccountsSheet(context, draft.value.accounts);
    if (picked != null) draft.value = draft.value.copyWith(accounts: picked);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OrdersFilter>(
    valueListenable: draft,
    builder: (context, filter, _) => SheetFrame(
      count: filter.apply(orders).length,
      onReset: filter == const OrdersFilter()
          ? null
          : () => draft.value = const OrdersFilter(),
      onApply: () => AdaptiveNativeSheet.pop(context, draft.value),
      children: [
        AdaptiveSegmentedControl(
          labels: const ['All', 'Buy', 'Sell'],
          icons: const [
            AdaptiveIcon(
              sfSymbol: 'arrow.up.arrow.down',
              icon: Icons.swap_vert_rounded,
            ),
            AdaptiveIcon(
              sfSymbol: 'arrow.down.left',
              icon: Icons.south_west_rounded,
            ),
            AdaptiveIcon(
              sfSymbol: 'arrow.up.right',
              icon: Icons.north_east_rounded,
            ),
          ],
          selectedIndex: filter.side == null ? 0 : filter.side!.index + 1,
          onValueChanged: (i) => draft.value = i == 0
              ? filter.copyWith(clearSide: true)
              : filter.copyWith(side: OrderSide.values[i - 1]),
        ),
        const SizedBox(height: 16),
        AdaptiveSegmentedControl(
          labels: const ['Newest', 'Value'],
          icons: const [
            AdaptiveIcon(sfSymbol: 'clock', icon: Icons.schedule_rounded),
            AdaptiveIcon(
              sfSymbol: 'dollarsign.circle',
              icon: Icons.paid_outlined,
            ),
          ],
          selectedIndex: filter.sort.index,
          onValueChanged: (i) =>
              draft.value = filter.copyWith(sort: OrderSort.values[i]),
        ),
        const SizedBox(height: 24),
        label(
          filter.minValue <= 0 ? 'Any value' : 'Over ${money(filter.minValue)}',
          size: 28,
          weight: FontWeight.w600,
        ),
        AdaptiveSlider(
          value: filter.minValue,
          max: OrdersFilter.maxValue,
          activeColor: red,
          onChanged: (v) => draft.value = filter.copyWith(minValue: v),
        ),
        const SizedBox(height: 8),
        _SwitchLine(
          icon: Icons.price_change_outlined,
          text: 'Limit only',
          value: filter.limitOnly,
          onChanged: (on) => draft.value = filter.copyWith(limitOnly: on),
        ),
        _SwitchLine(
          icon: Icons.block_rounded,
          text: 'Cancelled',
          value: filter.showCancelled,
          onChanged: (on) => draft.value = filter.copyWith(showCancelled: on),
        ),
        _AccountsLine(
          accounts: filter.accounts,
          onTap: () => _pickAccounts(context),
        ),
      ],
    ),
  );
}

/// An icon and title with a native switch at the trailing edge.
class _SwitchLine extends StatelessWidget {
  const _SwitchLine({
    required this.icon,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: muted),
        const SizedBox(width: 14),
        Expanded(child: label(text, size: 17)),
        AdaptiveSwitch(value: value, activeColor: red, onChanged: onChanged),
      ],
    ),
  );
}

/// A tappable line showing the chosen accounts, opening the accounts sheet.
class _AccountsLine extends StatelessWidget {
  const _AccountsLine({required this.accounts, required this.onTap});

  final Set<Account> accounts;
  final VoidCallback onTap;

  // No ink: the sheet opening is the feedback, and a ripple would be
  // caught mid-animation in the still frame this sheet shows underneath.
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: muted),
          const SizedBox(width: 14),
          Expanded(
            child: accounts.isEmpty
                ? label('All accounts', size: 17)
                : Row(
                    children: [
                      for (final a in Account.values)
                        if (accounts.contains(a))
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(a.icon, color: red),
                          ),
                    ],
                  ),
          ),
          const Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    ),
  );
}

/// Opens a second native sheet over the first, holding a native switch per
/// account. Returns the chosen accounts, or null when the sheet is dragged
/// away. An empty set means every account.
Future<Set<Account>?> showAccountsSheet(
  BuildContext context,
  Set<Account> initial,
) {
  final chosen = ValueNotifier(
    initial.isEmpty ? Account.values.toSet() : initial,
  );
  return AdaptiveNativeSheet.show<Set<Account>>(
    context: context,
    builder: (_) => AccountsSheetContent(chosen: chosen),
  ).whenComplete(chosen.dispose);
}

/// The second sheet's widget: a native switch per account, and a Done button.
class AccountsSheetContent extends StatelessWidget {
  const AccountsSheetContent({super.key, required this.chosen});

  final ValueNotifier<Set<Account>> chosen;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: ValueListenableBuilder<Set<Account>>(
          valueListenable: chosen,
          builder: (context, set, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Accounts', size: 22, weight: FontWeight.w600),
              const SizedBox(height: 12),
              for (final a in Account.values)
                _SwitchLine(
                  icon: a.icon,
                  text: a.title,
                  value: set.contains(a),
                  onChanged: (on) =>
                      chosen.value = on ? {...set, a} : ({...set}..remove(a)),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  // Every account, or none, both mean no account filter.
                  onPressed: set.isEmpty
                      ? null
                      : () => AdaptiveNativeSheet.pop(
                          context,
                          set.length == Account.values.length
                              ? <Account>{}
                              : set,
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('${set.length}'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
