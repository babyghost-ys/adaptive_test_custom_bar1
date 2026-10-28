import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const red = Color(0xFFB52132);
const paper = Color(0xFFF6F5F1);

void main() {
  group('AdaptiveThemeData', () {
    const data = AdaptiveThemeData(primaryColor: red, background: paper);

    test('derives a Material theme for each brightness', () {
      final light = data.material(Brightness.light);
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, paper);
      final dark = data.material(Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    test('derives a Cupertino theme', () {
      final theme = data.cupertino(Brightness.light);
      expect(theme.primaryColor, red);
      expect(theme.scaffoldBackgroundColor, paper);
    });

    test('compares by value', () {
      expect(
        const AdaptiveThemeData(
          barStyle: AdaptiveBarStyle.solid(red, shadow: true),
        ),
        const AdaptiveThemeData(
          barStyle: AdaptiveBarStyle.solid(red, shadow: true),
        ),
      );
      expect(
        const AdaptiveBarStyle.system(),
        isNot(const AdaptiveBarStyle.solid(red)),
      );
    });
  });

  testWidgets('AdaptiveTheme.of falls back to the platform defaults', (
    tester,
  ) async {
    late AdaptiveThemeData data;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          data = AdaptiveTheme.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(data.primaryColor, isNull);
    expect(data.barStyle, const AdaptiveBarStyle.system());
  });

  group('AdaptiveApp(theme:)', () {
    Future<(AdaptiveThemeData, ThemeData)> themesIn(
      WidgetTester tester, {
      ThemeMode mode = ThemeMode.light,
    }) async {
      late AdaptiveThemeData adaptive;
      late ThemeData material;
      await tester.pumpWidget(
        AdaptiveApp(
          themeMode: mode,
          theme: const AdaptiveThemeData(
            primaryColor: red,
            background: paper,
            barStyle: AdaptiveBarStyle.solid(red),
          ),
          home: Builder(
            builder: (context) {
              adaptive = AdaptiveTheme.of(context);
              material = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return (adaptive, material);
    }

    testWidgets('installs the theme and its Material theme', (tester) async {
      final (adaptive, material) = await themesIn(tester);
      expect(adaptive.barStyle.color, red);
      expect(material.scaffoldBackgroundColor, paper);
    });

    testWidgets('derives dark mode without the light background', (
      tester,
    ) async {
      final (adaptive, material) = await themesIn(tester, mode: ThemeMode.dark);
      expect(adaptive.primaryColor, red);
      expect(adaptive.background, isNull);
      expect(adaptive.barStyle.color, red);
      expect(material.brightness, Brightness.dark);
      expect(material.scaffoldBackgroundColor, isNot(paper));
    });
  });

  testWidgets('app bars take the bar style unless they set their own', (
    tester,
  ) async {
    await tester.pumpWidget(
      const AdaptiveApp(
        theme: AdaptiveThemeData(
          barStyle: AdaptiveBarStyle.solid(red, foreground: Colors.white),
        ),
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(title: 'Styled'),
          body: SizedBox(),
        ),
      ),
    );
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, red);
    expect(bar.foregroundColor, Colors.white);

    await tester.pumpWidget(
      const AdaptiveApp(
        theme: AdaptiveThemeData(barStyle: AdaptiveBarStyle.solid(red)),
        home: AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: 'Own colour',
            navigationBarColor: Colors.teal,
          ),
          body: SizedBox(),
        ),
      ),
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      Colors.teal,
    );
  });
}
