import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/app/theme/typography.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';
import 'package:native_widgets_on_duo/features/sign_in/view/sign_in_sheet.dart';

/// The home drawer's own content, handed to [AdaptiveDrawer.custom].
class MeridianDrawer extends StatelessWidget {
  const MeridianDrawer({super.key});

  static const _accounts = [
    (Icons.grid_view_rounded, 'All accounts'),
    (Icons.person_outline, 'Personal'),
    (Icons.spa_outlined, 'Retirement'),
    (Icons.shield_outlined, 'Tax-free'),
  ];

  static const _links = [
    (Icons.tune, 'preferences'),
    (Icons.description_outlined, 'statements'),
    (Icons.account_circle_outlined, 'profile'),
  ];

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InvestmentBloc, InvestmentState>(
        builder: (context, state) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'MERIDIAN',
                style: barTitleStyle.copyWith(color: red),
              ),
            ),
            const SizedBox(height: 16),
            for (final (index, (icon, name)) in _accounts.indexed)
              ListTile(
                leading: Icon(icon, color: index == state.account ? red : null),
                title: Text(name),
                trailing: Text(
                  '\$${state.copy(account: index).balance.toStringAsFixed(0)}',
                ),
                selected: index == state.account,
                selectedColor: red,
                onTap: () {
                  context.read<InvestmentBloc>().add(AccountSelected(index));
                  AdaptiveScaffold.of(context).closeDrawer();
                },
              ),
            const Divider(height: 32),
            for (final (icon, route) in _links)
              ListTile(
                leading: Icon(icon),
                title: Text(route[0].toUpperCase() + route.substring(1)),
                // The page opens once the menu is away, so the menu is not
                // left half closed under it.
                onTap: () async {
                  final router = GoRouter.of(context);
                  await AdaptiveScaffold.of(context).closeDrawer();
                  router.push('/$route');
                },
              ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: const Text('Sign in'),
              // The menu stays open under the sheet, so closing the sheet
              // returns to it, and the page's last frame behind the sheet is
              // still current. Signing in closes it.
              onTap: () async {
                final scaffold = AdaptiveScaffold.of(context);
                if (await showSignInSheet(context) != null) {
                  scaffold.closeDrawer();
                }
              },
            ),
          ],
        ),
      );
}
