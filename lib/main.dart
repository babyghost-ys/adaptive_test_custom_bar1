import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'features/investment_bloc.dart';

const red = Color(0xFFB52132),
    ink = Color(0xFF20262A),
    muted = Color(0xFF798080),
    paper = Color(0xFFF6F5F1),
    green = Color(0xFF297159);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BlocProvider(create: (_) => InvestmentBloc(), child: const MeridianApp()),
  );
}

class MeridianApp extends StatelessWidget {
  const MeridianApp({super.key});
  @override
  Widget build(BuildContext context) => AdaptiveApp(
    title: 'Meridian',
    themeMode: ThemeMode.light,
    cupertinoLightTheme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: red,
      scaffoldBackgroundColor: paper,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          color: ink,
          fontSize: 15,
        ),
      ),
    ),
    materialLightTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: red),
      scaffoldBackgroundColor: paper,
    ),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    builder: (context, child) => Theme(
      data: ThemeData(
        useMaterial3: true,
        fontFamily: '.SF Pro Text',
        colorScheme: ColorScheme.fromSeed(seedColor: red),
        scaffoldBackgroundColor: paper,
      ),
      child: child!,
    ),
    home: const InvestmentHome(),
  );
}

String money(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '\$$whole.${parts.last}';
}

Text label(
  String text, {
  double size = 15,
  Color color = ink,
  FontWeight weight = FontWeight.w400,
}) => Text(
  text,
  style: TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: size > 30 ? -1.5 : -0.2,
  ),
);

class InvestmentHome extends StatefulWidget {
  const InvestmentHome({super.key});
  @override
  State<InvestmentHome> createState() => _InvestmentHomeState();
}

class _InvestmentHomeState extends State<InvestmentHome> {
  final drawerKey = GlobalKey<ScaffoldState>();
  bool menuVisible = true;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvestmentBloc, InvestmentState>(
    builder: (context, state) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 620;
        return AdaptiveScaffold(
          backgroundColor: paper,
          scaffoldKey: drawerKey,
          useFixedToolbar: false,
          drawer: wide
              ? null
              : Drawer(
                  backgroundColor: paper,
                  width: 290,
                  child: SafeArea(
                    child: AccountMenu(
                      state: state,
                      onSelect: (i) {
                        context.read<InvestmentBloc>().add(AccountSelected(i));
                        drawerKey.currentState?.closeDrawer();
                      },
                    ),
                  ),
                ),
          bottomNavigationBar: AdaptiveBottomNavigationBar(
            selectedIndex: state.tab,
            selectedItemColor: red,
            onTap: (i) {
              drawerKey.currentState?.closeDrawer();
              context.read<InvestmentBloc>().add(TabSelected(i));
            },
            items: const [
              AdaptiveNavigationDestination(
                icon: 'chart.pie',
                selectedIcon: 'chart.pie.fill',
                label: 'Portfolio',
              ),
              AdaptiveNavigationDestination(
                icon: 'chart.xyaxis.line',
                label: 'Markets',
              ),
              AdaptiveNavigationDestination(
                icon: 'star',
                selectedIcon: 'star.fill',
                label: 'Watchlist',
              ),
              AdaptiveNavigationDestination(
                icon: 'clock.arrow.circlepath',
                label: 'Activity',
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle.dark,
                  child: Container(
                    height: 64,
                    color: red,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: wide ? 'Toggle accounts' : 'Open accounts',
                          onPressed: () {
                            if (wide) {
                              setState(() => menuVisible = !menuVisible);
                            } else {
                              drawerKey.currentState?.openDrawer();
                            }
                          },
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        label(
                          [
                            'Portfolio',
                            'Markets',
                            'Watchlist',
                            'Activity',
                          ][state.tab],
                          size: 21,
                          color: Colors.white,
                          weight: FontWeight.w600,
                        ),
                        const Spacer(),
                        if (wide)
                          Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: label(
                              'MERIDIAN',
                              size: 13,
                              color: Colors.white70,
                              weight: FontWeight.w700,
                            ),
                          ),
                        Semantics(
                          button: true,
                          label: 'Profile',
                          child: GestureDetector(
                            onTap: () => openPage(
                              context,
                              'Profile',
                              const ProfileContent(),
                            ),
                            child: const CircleAvatar(
                              radius: 17,
                              backgroundColor: Color(0xFFD2626D),
                              child: Text(
                                'PL',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide && menuVisible)
                        SizedBox(
                          width: 210,
                          child: AccountMenu(
                            state: state,
                            onSelect: (i) => context.read<InvestmentBloc>().add(
                              AccountSelected(i),
                            ),
                          ),
                        ),
                      Expanded(
                        child: IndexedStack(
                          index: state.tab,
                          children: [
                            Portfolio(state: state),
                            const Markets(),
                            Watchlist(state: state),
                            const Activity(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, required this.state, required this.onSelect});
  final InvestmentState state;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFEEEDE7),
      border: Border(right: BorderSide(color: Color(0xFFE2E1DA))),
    ),
    child: ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        26,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: label('MERIDIAN', size: 18, weight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: label('Demo investing', size: 12, color: muted),
        ),
        const SizedBox(height: 32),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Semantics(
              button: true,
              selected: state.account == i,
              child: Material(
                color: state.account == i ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          [
                            Icons.grid_view_rounded,
                            Icons.person_outline,
                            Icons.spa_outlined,
                            Icons.shield_outlined,
                          ][i],
                          size: 20,
                          color: state.account == i ? red : muted,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: label(
                            [
                              'All accounts',
                              'Personal',
                              'Retirement',
                              'Tax-free',
                            ][i],
                            size: 14,
                            weight: state.account == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 25),
        const Divider(color: Color(0xFFDADAD2)),
        const SizedBox(height: 16),
        menuLink(
          context,
          Icons.tune,
          'Preferences',
          const PreferencesContent(),
        ),
        menuLink(
          context,
          Icons.description_outlined,
          'Statements',
          const StatementsContent(),
        ),
      ],
    ),
  );
  Widget menuLink(
    BuildContext context,
    IconData icon,
    String title,
    Widget content,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    leading: Icon(icon, size: 20, color: muted),
    title: label(title, size: 13),
    onTap: () {
      Scaffold.maybeOf(context)?.closeDrawer();
      openPage(context, title, content);
    },
  );
}

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children, this.storageKey});
  final List<Widget> children;
  final String? storageKey;
  @override
  Widget build(BuildContext context) => ListView(
    key: PageStorageKey(storageKey ?? 'page'),
    padding: EdgeInsets.fromLTRB(
      24,
      28,
      24,
      MediaQuery.paddingOf(context).bottom + 28,
    ),
    children: children,
  );
}

class Portfolio extends StatelessWidget {
  const Portfolio({super.key, required this.state});
  final InvestmentState state;
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'portfolio',
    children: [
      Row(
        children: [
          label(state.accountName, color: muted),
          const Spacer(),
          label('USD', size: 12, color: muted),
        ],
      ),
      const SizedBox(height: 10),
      FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: label(money(state.balance), size: 44, weight: FontWeight.w600),
      ),
      const SizedBox(height: 9),
      Row(
        children: [
          const Icon(Icons.north_east, size: 15, color: green),
          const SizedBox(width: 4),
          label(
            '+${money(state.balance * [0.008, 0.025, 0.0842, 0.146, 0.218][state.range])} (${[0.8, 2.5, 8.42, 14.6, 21.8][state.range]}%)',
            color: green,
            size: 14,
            weight: FontWeight.w500,
          ),
        ],
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 170,
        child: CustomPaint(
          painter: ChartPainter(seed: state.range, filled: true),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          5,
          (i) => GestureDetector(
            onTap: () => context.read<InvestmentBloc>().add(RangeSelected(i)),
            child: Semantics(
              button: true,
              selected: i == state.range,
              label: [
                'One day',
                'One week',
                'One month',
                'One year',
                'All time',
              ][i],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: i == state.range ? ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: label(
                  ['1D', '1W', '1M', '1Y', 'ALL'][i],
                  size: 12,
                  color: i == state.range ? Colors.white : muted,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(child: metric('Invested', money(state.invested))),
            const SizedBox(width: 12),
            Expanded(child: metric('Available cash', money(state.cash))),
          ],
        ),
      ),
      const SizedBox(height: 32),
      section('Holdings', '${assets.length} assets'),
      const SizedBox(height: 10),
      ...assets.map(
        (asset) =>
            AssetRow(asset: asset, holding: true, scale: state.accountScale),
      ),
      const SizedBox(height: 28),
      section('Allocation', ''),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                flex: [51, 42, 7][i],
                child: Container(
                  height: 10,
                  color: [
                    red,
                    const Color(0xFFCCA68B),
                    const Color(0xFFDCD9D0),
                  ][i],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          label('Stocks 51%', size: 12),
          label('ETFs 42%', size: 12),
          label('Cash 7%', size: 12),
        ],
      ),
    ],
  );
}

Widget metric(String title, String value) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      label(title, color: muted, size: 12),
      const SizedBox(height: 9),
      FittedBox(child: label(value, size: 20, weight: FontWeight.w600)),
    ],
  ),
);
Widget section(String title, String trailing) => Row(
  children: [
    label(title, size: 20, weight: FontWeight.w600),
    const Spacer(),
    label(trailing, size: 12, color: muted),
  ],
);

class AssetRow extends StatelessWidget {
  const AssetRow({
    super.key,
    required this.asset,
    this.holding = false,
    this.scale = 1,
  });
  final Asset asset;
  final bool holding;
  final double scale;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            openPage(context, asset.symbol, AssetDetails(asset: asset)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE6E5DF))),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color(asset.color),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: label(
                  asset.symbol == 'AAPL' ? 'a' : asset.symbol.substring(0, 1),
                  size: 22,
                  color: Colors.white,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label(asset.symbol, weight: FontWeight.w600),
                    const SizedBox(height: 4),
                    Text(
                      holding
                          ? '${(asset.shares * scale).toStringAsFixed(1)} shares'
                          : asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                height: 25,
                child: CustomPaint(
                  painter: ChartPainter(
                    seed: assets.indexOf(asset),
                    color: asset.change < 0 ? red : green,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  label(
                    money(
                      holding
                          ? asset.price * asset.shares * scale
                          : asset.price,
                    ),
                    weight: FontWeight.w500,
                  ),
                  const SizedBox(height: 4),
                  label(
                    '${asset.change > 0 ? '+' : ''}${asset.change.toStringAsFixed(2)}%',
                    color: asset.change < 0 ? red : green,
                    size: 12,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Markets extends StatelessWidget {
  const Markets({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'markets',
    children: [
      section('Market overview', 'Demo prices'),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: metric('S&P 500', '5,892.16')),
          const SizedBox(width: 12),
          Expanded(child: metric('NASDAQ', '18,421.09')),
        ],
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 150,
        child: CustomPaint(painter: ChartPainter(seed: 7, filled: true)),
      ),
      const SizedBox(height: 24),
      section('Explore', 'USD'),
      const SizedBox(height: 8),
      ...assets.map((a) => AssetRow(asset: a)),
    ],
  );
}

class Watchlist extends StatelessWidget {
  const Watchlist({super.key, required this.state});
  final InvestmentState state;
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'watchlist',
    children: [
      section('Following', '${state.watchlist.length} assets'),
      const SizedBox(height: 12),
      ...assets
          .where((a) => state.watchlist.contains(a.symbol))
          .map((a) => AssetRow(asset: a)),
      const SizedBox(height: 28),
      label('Discover', size: 20, weight: FontWeight.w600),
      ...assets
          .where((a) => !state.watchlist.contains(a.symbol))
          .map((a) => AssetRow(asset: a)),
    ],
  );
}

class Activity extends StatelessWidget {
  const Activity({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    storageKey: 'activity',
    children: [
      section('Recent activity', 'Demo'),
      const SizedBox(height: 20),
      for (var i = 0; i < 12; i++)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE5EBE1),
            child: Icon(
              i % 3 == 0 ? Icons.south_west : Icons.add,
              color: green,
              size: 20,
            ),
          ),
          title: label(
            i % 3 == 0 ? 'Dividend · VOO' : 'Bought ${assets[i % 6].symbol}',
            weight: FontWeight.w500,
          ),
          subtitle: label('Oct ${19 - i} · Personal', size: 12, color: muted),
          trailing: label(
            i % 3 == 0 ? '+\$128.40' : money(assets[i % 6].price),
            size: 14,
          ),
        ),
    ],
  );
}

void openPage(BuildContext context, String title, Widget content) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => AdaptiveScaffold(
          backgroundColor: paper,
          appBar: AdaptiveAppBar(title: title),
          body: SafeArea(bottom: false, child: content),
        ),
      ),
    );

class AssetDetails extends StatelessWidget {
  const AssetDetails({super.key, required this.asset});
  final Asset asset;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<InvestmentBloc, InvestmentState>(
    builder: (context, state) => PageScroll(
      storageKey: asset.symbol,
      children: [
        label(asset.name, color: muted),
        const SizedBox(height: 14),
        label(money(asset.price), size: 44, weight: FontWeight.w600),
        const SizedBox(height: 8),
        label(
          '${asset.change > 0 ? '+' : ''}${asset.change}% today',
          color: asset.change < 0 ? red : green,
        ),
        const SizedBox(height: 30),
        SizedBox(
          height: 210,
          child: CustomPaint(
            painter: ChartPainter(seed: assets.indexOf(asset), filled: true),
          ),
        ),
        const SizedBox(height: 28),
        AdaptiveButton(
          onPressed: () =>
              context.read<InvestmentBloc>().add(WatchToggled(asset.symbol)),
          label: state.watchlist.contains(asset.symbol)
              ? 'Remove from watchlist'
              : 'Add to watchlist',
        ),
        const SizedBox(height: 30),
        section('Your position', ''),
        const SizedBox(height: 16),
        metric(
          'Market value',
          money(asset.price * asset.shares * state.accountScale),
        ),
        const SizedBox(height: 12),
        metric(
          'Shares',
          (asset.shares * state.accountScale).toStringAsFixed(1),
        ),
        const SizedBox(height: 12),
        metric('Average cost', money(asset.price * 0.92)),
        const SizedBox(height: 24),
        label('Illustrative data · No real trades', size: 12, color: muted),
      ],
    ),
  );
}

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      const Center(
        child: CircleAvatar(
          radius: 42,
          backgroundColor: red,
          child: Text(
            'PL',
            style: TextStyle(color: Colors.white, fontSize: 28),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Center(child: label('Peter Leung', size: 25, weight: FontWeight.w600)),
      const SizedBox(height: 32),
      metric('Account', 'Demo investor'),
      const SizedBox(height: 12),
      metric('Base currency', 'USD'),
    ],
  );
}

class PreferencesContent extends StatefulWidget {
  const PreferencesContent({super.key});
  @override
  State<PreferencesContent> createState() => _PreferencesContentState();
}

class _PreferencesContentState extends State<PreferencesContent> {
  bool alerts = true;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      Row(
        children: [
          Expanded(child: label('Price alerts')),
          AdaptiveSwitch(
            value: alerts,
            onChanged: (v) => setState(() => alerts = v),
          ),
        ],
      ),
      const SizedBox(height: 24),
      metric('Currency', 'USD'),
      const SizedBox(height: 12),
      metric('Environment', 'Demo'),
    ],
  );
}

class StatementsContent extends StatelessWidget {
  const StatementsContent({super.key});
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      for (final month in ['September', 'August', 'July'])
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          leading: const Icon(Icons.description_outlined, color: red),
          title: label('$month 2026'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openPage(
            context,
            '$month statement',
            PageScroll(
              children: [
                metric('Closing balance', '\$118,473.20'),
                const SizedBox(height: 12),
                metric('Dividends received', '\$128.40'),
                const SizedBox(height: 20),
                label('Demo statement', color: muted, size: 12),
              ],
            ),
          ),
        ),
    ],
  );
}

class ChartPainter extends CustomPainter {
  ChartPainter({this.seed = 0, this.filled = false, this.color = red});
  final int seed;
  final bool filled;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final random = math.Random(seed + 41);
    for (var i = 0; i <= 60; i++) {
      final x = size.width * i / 60;
      final trend = 0.8 - i / 60 * 0.58;
      final y =
          size.height *
          (trend +
              math.sin(i * 0.64 + seed) * 0.06 +
              (random.nextDouble() - 0.5) * 0.1);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    if (filled) {
      final grid = Paint()
        ..color = const Color(0xFFE6E4DE)
        ..strokeWidth = 1;
      for (var i = 1; i <= 3; i++) {
        canvas.drawLine(
          Offset(0, size.height * i / 4),
          Offset(size.width, size.height * i / 4),
          grid,
        );
      }
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = filled ? 2.4 : 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant ChartPainter old) =>
      old.seed != seed || old.color != color || old.filled != filled;
}
