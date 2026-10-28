import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The test host is not iOS, so the native family is never available here.
  group('AdaptiveStyle', () {
    test('defaults to Material off iOS', () {
      expect(AdaptiveStyle.platformDefault, AdaptiveStyle.material);
    });

    Future<AdaptiveStyle> styleUnder(
      WidgetTester tester,
      AdaptiveStyle? requested,
    ) async {
      late AdaptiveStyle style;
      final probe = Builder(
        builder: (context) {
          style = AdaptiveStyle.of(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        requested == null
            ? probe
            : AdaptiveStyleScope(style: requested, child: probe),
      );
      return style;
    }

    testWidgets('without a scope uses the platform default', (tester) async {
      expect(await styleUnder(tester, null), AdaptiveStyle.material);
    });

    testWidgets('a scope asking for native falls back to Material off iOS', (
      tester,
    ) async {
      expect(
        await styleUnder(tester, AdaptiveStyle.native),
        AdaptiveStyle.material,
      );
    });

    testWidgets('AdaptiveApp installs the style for everything below', (
      tester,
    ) async {
      late AdaptiveStyle style;
      await tester.pumpWidget(
        AdaptiveApp(
          style: AdaptiveStyle.material,
          home: Builder(
            builder: (context) {
              style = AdaptiveStyle.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style, AdaptiveStyle.material);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('AdaptiveCapabilities', () {
    test('report nothing iOS-only off iOS', () {
      expect(AdaptiveCapabilities.liquidGlass, isFalse);
      expect(AdaptiveCapabilities.systemVerticalBarEdge, isFalse);
    });
  });
}
