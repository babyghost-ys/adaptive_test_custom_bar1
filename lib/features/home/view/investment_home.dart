import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/features/investment/bloc/investment_bloc.dart';

class InvestmentHome extends StatefulWidget {
  const InvestmentHome({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  State<InvestmentHome> createState() => _InvestmentHomeState();
}

class _InvestmentHomeState extends State<InvestmentHome> {
  final scaffoldKey = GlobalKey<AdaptiveScaffoldState>();
  bool menuOpen = false;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvestmentBloc, InvestmentState>(
    builder: (context, state) => AdaptiveScaffold(
      key: scaffoldKey,
      extendBody: true,
      appBar: AdaptiveAppBar(
        actions: [
          AdaptiveAppBarAction(
            icon: AdaptiveIcon(
              sfSymbol: menuOpen ? 'xmark' : 'line.3.horizontal',
              icon: menuOpen ? Icons.close : Icons.menu_rounded,
            ),
            label: menuOpen ? 'Close accounts' : 'Open accounts',
            spacerAfter: ToolbarSpacerType.flexible,
            onPressed: () => scaffoldKey.currentState?.openDrawer(),
          ),
          AdaptiveAppBarAction(
            icon: AdaptiveIcon(sfSymbol: 'magnifyingglass', icon: Icons.search),
            label: 'Search',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      onDrawerChanged: (open) => setState(() => menuOpen = open),
      drawer: AdaptiveDrawer(
        title: 'MERIDIAN',
        subtitle: 'Demo investing',
        backgroundColor: const Color(0xFFEEEDE7),
        selectedId: 'account:${state.account}',
        sections: const [
          [
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'square.grid.2x2.fill',
                icon: Icons.grid_view_rounded,
              ),
              id: 'account:0',
              title: 'All accounts',
            ),
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'person',
                icon: Icons.person_outline,
              ),
              id: 'account:1',
              title: 'Personal',
            ),
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(sfSymbol: 'leaf', icon: Icons.spa_outlined),
              id: 'account:2',
              title: 'Retirement',
            ),
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'shield',
                icon: Icons.shield_outlined,
              ),
              id: 'account:3',
              title: 'Tax-free',
            ),
          ],
          [
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'slider.horizontal.3',
                icon: Icons.tune,
              ),
              id: 'preferences',
              title: 'Preferences',
            ),
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'doc.text',
                icon: Icons.description_outlined,
              ),
              id: 'statements',
              title: 'Statements',
            ),
            AdaptiveDrawerItem(
              icon: AdaptiveIcon(
                sfSymbol: 'person.crop.circle',
                icon: Icons.account_circle_outlined,
              ),
              id: 'profile',
              title: 'Profile',
            ),
          ],
        ],
        onSelected: (id) => id.startsWith('account:')
            ? context.read<InvestmentBloc>().add(
                AccountSelected(int.parse(id.split(':').last)),
              )
            : context.push('/$id'),
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: widget.shell.currentIndex,
        selectedItemColor: red,
        onTap: (i) {
          scaffoldKey.currentState?.closeDrawer();
          widget.shell.goBranch(
            i,
            initialLocation: i == widget.shell.currentIndex,
          );
        },
        items: const [
          AdaptiveNavigationDestination(
            icon: AdaptiveIcon(
              sfSymbol: 'chart.pie',
              icon: Icons.pie_chart_outline,
            ),
            selectedIcon: AdaptiveIcon(
              sfSymbol: 'chart.pie.fill',
              icon: Icons.pie_chart,
            ),
            label: 'Portfolio',
          ),
          AdaptiveNavigationDestination(
            icon: AdaptiveIcon(
              sfSymbol: 'chart.xyaxis.line',
              icon: Icons.show_chart,
            ),
            label: 'Markets',
          ),
          AdaptiveNavigationDestination(
            icon: AdaptiveIcon(sfSymbol: 'star', icon: Icons.star_outline),
            selectedIcon: AdaptiveIcon(sfSymbol: 'star.fill', icon: Icons.star),
            label: 'Watchlist',
          ),
          AdaptiveNavigationDestination(
            icon: AdaptiveIcon(
              sfSymbol: 'clock.arrow.circlepath',
              icon: Icons.history,
            ),
            label: 'Activity',
          ),
        ],
      ),
      body: widget.shell,
    ),
  );
}
