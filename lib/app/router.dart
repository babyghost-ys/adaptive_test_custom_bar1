import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/features/activity/view/activity_page.dart';
import 'package:native_widgets_on_duo/features/asset_detail/view/asset_details_page.dart';
import 'package:native_widgets_on_duo/features/home/view/investment_home.dart';
import 'package:native_widgets_on_duo/features/investment/data/demo_assets.dart';
import 'package:native_widgets_on_duo/features/markets/view/markets_page.dart';
import 'package:native_widgets_on_duo/features/portfolio/view/portfolio_page.dart';
import 'package:native_widgets_on_duo/features/preferences/view/preferences_page.dart';
import 'package:native_widgets_on_duo/features/profile/view/profile_page.dart';
import 'package:native_widgets_on_duo/features/search/view/search_page.dart';
import 'package:native_widgets_on_duo/features/statements/view/statement_page.dart';
import 'package:native_widgets_on_duo/core/widgets/bar_title.dart';
import 'package:native_widgets_on_duo/features/statements/view/statements_page.dart';
import 'package:native_widgets_on_duo/features/watchlist/view/watchlist_page.dart';

/// Details sit on the root navigator above the tabs, so UIKit pushes them
/// over the whole tab layout.
final router = GoRouter(
  initialLocation: '/portfolio',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => InvestmentHome(shell: shell),
      branches: [
        for (final (path, page) in [
          ('/portfolio', const PortfolioTab()),
          ('/markets', const Markets()),
          ('/watchlist', const WatchlistTab()),
          ('/activity', const Activity()),
        ])
          StatefulShellBranch(
            routes: [GoRoute(path: path, builder: (context, state) => page)],
          ),
      ],
    ),
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) =>
          detailPage(state, 'Search', const SearchContent()),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) =>
          detailPage(state, 'Profile', const ProfileContent()),
    ),
    GoRoute(
      path: '/preferences',
      pageBuilder: (context, state) =>
          detailPage(state, 'Preferences', const PreferencesContent()),
    ),
    GoRoute(
      path: '/statements',
      pageBuilder: (context, state) =>
          detailPage(state, 'Statements', const StatementsContent()),
      routes: [
        GoRoute(
          path: ':month',
          pageBuilder: (context, state) {
            final month = state.pathParameters['month']!;
            return detailPage(
              state,
              '$month statement',
              const StatementContent(),
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/asset/:symbol',
      pageBuilder: (context, state) {
        final asset = assets.firstWhere(
          (a) => a.symbol == state.pathParameters['symbol'],
        );
        return detailPage(state, asset.symbol, AssetDetails(asset: asset));
      },
    ),
  ],
);

/// A pushed page whose title, Back button and swipe-back UIKit owns.
Page<void> detailPage(GoRouterState state, String title, Widget content) =>
    AdaptivePage<void>(
      key: state.pageKey,
      name: state.uri.path,
      child: AdaptiveScaffold(
        extendBody: true,
        appBar: AdaptiveAppBar(title: title, titleWidget: barTitle(title)),
        body: content,
      ),
    );
