import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:native_widgets_on_duo/app/theme/palette.dart';
import 'package:native_widgets_on_duo/app/theme/typography.dart';
import 'package:native_widgets_on_duo/features/activity/view/activity_filter_sheet.dart';
import 'package:native_widgets_on_duo/features/activity/view/activity_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The package's Flutter-drawn sheet with adaptive controls inside.
  useFlutterSheet = true;
  runApp(const ActivityRotationApp());
}

final _router = GoRouter(
  initialLocation: '/activity',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ActivityShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/activity',
              builder: (context, state) => const Activity(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class ActivityRotationApp extends StatelessWidget {
  const ActivityRotationApp({super.key});

  @override
  Widget build(BuildContext context) => AdaptiveApp.router(
    routerConfig: _router,
    title: 'Meridian',
    themeMode: ThemeMode.light,
    theme: const AdaptiveThemeData(
      primaryColor: red,
      background: paper,
      barStyle: AdaptiveBarStyle.solid(
        red,
        foreground: Colors.white,
        shadow: true,
        plainButtons: true,
        duoStripGradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [red, redLight],
        ),
      ),
    ),
  );
}

class _ActivityShell extends StatelessWidget {
  const _ActivityShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    extendBody: true,
    extendBodyBehindSides: true,
    appBar: AdaptiveAppBar(
      titleStyle: barTitleStyle,
      actions: [
        AdaptiveAppBarAction(
          icon: const AdaptiveIcon(
            sfSymbol: 'line.3.horizontal',
            icon: Icons.menu_rounded,
          ),
          label: 'Menu',
          spacerAfter: ToolbarSpacerType.flexible,
          onPressed: () {},
        ),
        AdaptiveAppBarAction(
          icon: const AdaptiveIcon(
            sfSymbol: 'magnifyingglass',
            icon: Icons.search,
          ),
          label: 'Search',
          onPressed: () {},
        ),
      ],
    ),
    bottomNavigationBar: AdaptiveBottomNavigationBar(
      selectedIndex: 3,
      selectedItemColor: red,
      onTap: (_) {},
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
        AdaptiveNavigationDestination(
          icon: AdaptiveIcon(
            sfSymbol: 'list.bullet.rectangle',
            icon: Icons.receipt_long_outlined,
          ),
          selectedIcon: AdaptiveIcon(
            sfSymbol: 'list.bullet.rectangle.fill',
            icon: Icons.receipt_long,
          ),
          label: 'Orders',
        ),
      ],
    ),
    body: shell,
  );
}
