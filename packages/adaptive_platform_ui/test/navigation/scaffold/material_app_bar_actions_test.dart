import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The test host renders the Material path.
  testWidgets('actions before a flexible spacer take the leading slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Home',
            actions: [
              AdaptiveAppBarAction(
                icon: const AdaptiveIcon(icon: Icons.menu),
                label: 'Menu',
                spacerAfter: ToolbarSpacerType.flexible,
                onPressed: () {},
              ),
              AdaptiveAppBarAction(
                icon: const AdaptiveIcon(icon: Icons.search),
                label: 'Search',
                onPressed: () {},
              ),
            ],
          ),
          drawer: const Drawer(child: Text('Drawer')),
          body: const SizedBox(),
        ),
      ),
    );

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      find.descendant(
        of: find.byWidget(bar.leading!),
        matching: find.byIcon(Icons.menu),
      ),
      findsOneWidget,
    );
    expect(bar.actions, hasLength(1));
    // The implied drawer button is replaced, not added beside it.
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('without a flexible spacer every action trails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Home',
            actions: [
              AdaptiveAppBarAction(
                icon: const AdaptiveIcon(icon: Icons.search),
                label: 'Search',
                onPressed: () {},
              ),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.leading, isNull);
    expect(bar.actions, hasLength(1));
  });
}
