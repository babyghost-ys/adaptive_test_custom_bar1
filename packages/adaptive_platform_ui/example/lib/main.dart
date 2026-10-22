import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(
  const AdaptiveApp(
    title: 'Example',
    // Required: the Drawer and ListTile need MaterialLocalizations on iOS.
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Home(),
  ),
);

Color _tone(int i) =>
    i.isEven ? const Color(0xFF9CC7E8) : const Color(0xFFF2B880);

Widget _row(BuildContext context, int i, {VoidCallback? onTap}) {
  final band = Container(
    width: double.infinity,
    color: _tone(i),
    padding: const EdgeInsets.all(16),
    child: Text('Row $i', style: const TextStyle(color: Colors.black)),
  );
  // Pushed pages have no Material ancestor, so only tappable rows use ink.
  return onTap == null
      ? band
      : Semantics(
          button: true,
          child: InkWell(onTap: onTap, child: band),
        );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _key = GlobalKey<ScaffoldState>();
  int _index = 0;
  bool _on = false;
  final _scroll = AdaptiveNavigationScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    scaffoldKey: _key,
    appBar: AdaptiveAppBar(
      title: ['Large', 'Slivers', 'Static'][_index],
      largeTitle: _index == 0,
      scrollController: _index == 0 ? _scroll : null,
      actions: [
        AdaptiveAppBarAction(
          iosSymbol: 'line.3.horizontal',
          icon: Icons.menu,
          label: 'Menu',
          onPressed: () => _key.currentState?.openDrawer(),
        ),
      ],
    ),
    drawer: const Drawer(child: Center(child: Text('Drawer'))),
    bottomNavigationBar: AdaptiveBottomNavigationBar(
      selectedIndex: _index,
      onTap: (i) => setState(() => _index = i),
      items: const [
        AdaptiveNavigationDestination(icon: 'house', label: 'List'),
        AdaptiveNavigationDestination(icon: 'star', label: 'Sliver'),
        AdaptiveNavigationDestination(icon: 'gear', label: 'Static'),
      ],
    ),
    body: switch (_index) {
      0 => ListView.builder(
        controller: _scroll,
        itemCount: 40,
        itemBuilder: (context, i) => _row(
          context,
          i + 1,
          onTap: () =>
              AdaptiveNavigator.push(context, (_) => Detail(number: i + 1)),
        ),
      ),
      1 => CustomScrollView(
        slivers: [
          SliverList.builder(
            itemCount: 40,
            itemBuilder: (context, i) => _row(context, i + 1),
          ),
        ],
      ),
      _ => Column(
        children: [
          _band('TOP EDGE'),
          const ListTile(title: Text('Material ListTile')),
          AdaptiveSwitch(value: _on, onChanged: (v) => setState(() => _on = v)),
          const Spacer(),
          _band('BOTTOM EDGE'),
        ],
      ),
    },
  );
}

Widget _band(String text) => Container(
  width: double.infinity,
  color: const Color(0xFFB8E0B0),
  padding: const EdgeInsets.all(16),
  child: Text(text, style: const TextStyle(color: Colors.black)),
);

class Detail extends StatelessWidget {
  const Detail({super.key, required this.number});
  final int number;

  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    appBar: AdaptiveAppBar(title: 'Detail $number'),
    body: ListView.builder(
      itemCount: 40,
      itemBuilder: (context, i) => _row(context, i + 1),
    ),
  );
}
