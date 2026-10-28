import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The test host renders the Material drawer; the native panel needs iOS.
  Future<(GlobalKey<AdaptiveScaffoldState>, List<String>, List<bool>)> pump(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<AdaptiveScaffoldState>();
    final selected = <String>[];
    final changes = <bool>[];
    await tester.pumpWidget(
      AdaptiveApp(
        home: AdaptiveScaffold(
          key: key,
          appBar: const AdaptiveAppBar(title: 'Home'),
          onDrawerChanged: changes.add,
          drawer: AdaptiveDrawer(
            title: 'Accounts',
            subtitle: 'Demo',
            selectedId: 'personal',
            sections: const [
              [
                AdaptiveDrawerItem(
                  icon: AdaptiveIcon(
                    sfSymbol: 'square.grid.2x2',
                    icon: Icons.grid_view,
                  ),
                  id: 'all',
                  title: 'All accounts',
                ),
                AdaptiveDrawerItem(
                  icon: AdaptiveIcon(
                    sfSymbol: 'person',
                    icon: Icons.person_outline,
                  ),
                  id: 'personal',
                  title: 'Personal',
                ),
              ],
              [
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
            onSelected: selected.add,
          ),
          body: const SizedBox(),
        ),
      ),
    );
    return (key, selected, changes);
  }

  testWidgets('opens from AdaptiveScaffoldState and lists its sections', (
    tester,
  ) async {
    final (key, _, changes) = await pump(tester);
    expect(key.currentState!.isDrawerOpen, isFalse);
    await key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(key.currentState!.isDrawerOpen, isTrue);
    expect(changes, [true]);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    final personal = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Personal'),
    );
    expect(personal.selected, isTrue);
  });

  testWidgets('choosing an item closes the drawer and reports its id', (
    tester,
  ) async {
    final (key, selected, changes) = await pump(tester);
    await key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(selected, ['profile']);
    expect(key.currentState!.isDrawerOpen, isFalse);
    expect(changes, [true, false]);
  });

  testWidgets('closeDrawer closes without a selection', (tester) async {
    final (key, selected, _) = await pump(tester);
    await key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    key.currentState!.closeDrawer();
    await tester.pumpAndSettle();

    expect(key.currentState!.isDrawerOpen, isFalse);
    expect(selected, isEmpty);
  });
}
