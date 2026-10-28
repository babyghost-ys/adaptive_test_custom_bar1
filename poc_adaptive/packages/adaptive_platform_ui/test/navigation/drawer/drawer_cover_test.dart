import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/navigation/drawer/drawer_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An app's own drawer widget around an [AdaptiveDrawer.custom], the way an
/// app usually keeps its menu in a file of its own.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) => const AdaptiveDrawer.custom(
    width: 300,
    backgroundColor: Color(0xFFEEEDE7),
    child: Text('Menu'),
  );
}

void main() {
  // The test host is not iOS, so the scaffold never takes the native path
  // here. These drive what it puts around its drawer on that path: the
  // scope and the reporter that has UIKit cut the bars open.
  const channel = MethodChannel('adaptive_platform_ui/navigation');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<GlobalKey<ScaffoldState>> pump(
    WidgetTester tester,
    Widget drawer,
  ) async {
    final key = GlobalKey<ScaffoldState>();
    final pulse = DrawerCoverPulse();
    var open = false;
    addTearDown(pulse.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: key,
          onDrawerChanged: (isOpen) {
            open = isOpen;
            pulse.ping();
          },
          drawer: DrawerCoverScope(
            pulse: pulse,
            isOpen: () => open,
            child: DrawerCoverReporter(
              pulse: pulse,
              isOpen: () => open,
              child: drawer,
            ),
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    return key;
  }

  Map<Object?, Object?> lastCover() =>
      calls.lastWhere((c) => c.method == 'setDrawerCover').arguments
          as Map<Object?, Object?>;

  testWidgets('follows a drawer wrapped in the app\'s own widget', (
    tester,
  ) async {
    final key = await pump(tester, const _AppDrawer());
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final cover = lastCover();
    expect(cover['x'], 0.0);
    expect(cover['width'], 300.0);
    // The colour comes from the AdaptiveDrawer.custom inside the wrapper.
    expect(cover['background'], const Color(0xFFEEEDE7).toARGB32());
  });

  testWidgets('follows a plain Drawer, in the theme\'s drawer colour', (
    tester,
  ) async {
    final key = await pump(
      tester,
      const Drawer(width: 280, child: Text('Menu')),
    );
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final cover = lastCover();
    expect(cover['x'], 0.0);
    expect(cover['width'], 280.0);
    final theme = Theme.of(tester.element(find.text('Menu')));
    expect(
      cover['background'],
      AdaptiveDrawer.defaultBackground(theme).toARGB32(),
    );
  });

  testWidgets('clears the cover once the drawer has closed', (tester) async {
    final key = await pump(tester, const _AppDrawer());
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    key.currentState!.closeDrawer();
    await tester.pumpAndSettle();

    expect(calls.last.method, 'clearDrawerCover');
  });
}
