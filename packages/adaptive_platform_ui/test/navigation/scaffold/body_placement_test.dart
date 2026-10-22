import 'package:adaptive_platform_ui/src/navigation/scaffold/body_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BodyPlacement.appliesInsets', () {
    test('a plain vertical list or grid applies the media padding', () {
      expect(BodyPlacement.appliesInsets(ListView()), isTrue);
      expect(
        BodyPlacement.appliesInsets(
          GridView.count(crossAxisCount: 2, children: const []),
        ),
        isTrue,
      );
    });

    test('a custom scroll view qualifies; its slivers get wrapped', () {
      expect(BodyPlacement.appliesInsets(const CustomScrollView()), isTrue);
    });

    test('a list with its own padding, a horizontal list or a column does '
        'not', () {
      expect(
        BodyPlacement.appliesInsets(ListView(padding: EdgeInsets.zero)),
        isFalse,
      );
      expect(
        BodyPlacement.appliesInsets(ListView(scrollDirection: Axis.horizontal)),
        isFalse,
      );
      expect(BodyPlacement.appliesInsets(const Column()), isFalse);
      expect(BodyPlacement.appliesInsets(null), isFalse);
    });
  });

  group('BodyPlacement.resolve', () {
    // The test host has no Liquid Glass bars.
    test('off glass, a scroll view sits between the bars', () {
      final placement = BodyPlacement.resolve(
        body: ListView(),
        largeTitle: false,
      );
      expect(placement.underTop, isFalse);
      expect(placement.underBottom, isFalse);
    });

    test('a large title keeps its scroll view under the top bar', () {
      final placement = BodyPlacement.resolve(
        body: ListView(),
        largeTitle: true,
      );
      expect(placement.underTop, isTrue);
      expect(placement.underBottom, isFalse);
    });

    test('a large title over a column still pads it', () {
      final placement = BodyPlacement.resolve(
        body: const Column(),
        largeTitle: true,
      );
      expect(placement.underTop, isFalse);
    });

    test('explicit extend flags win', () {
      final placement = BodyPlacement.resolve(
        body: const Column(),
        largeTitle: false,
        extendBehindTop: true,
        extendBehindBottom: true,
      );
      expect(placement.underTop, isTrue);
      expect(placement.underBottom, isTrue);
    });
  });

  test('withInsetSlivers wraps a custom scroll view in a SliverSafeArea', () {
    const sliver = SliverToBoxAdapter(child: SizedBox());
    final wrapped =
        BodyPlacement.withInsetSlivers(
              const CustomScrollView(slivers: [sliver]),
            )!
            as CustomScrollView;
    expect(wrapped.slivers.single, isA<SliverSafeArea>());
    final safe = wrapped.slivers.single as SliverSafeArea;
    expect(safe.left, isFalse);
    expect(safe.right, isFalse);
    expect((safe.sliver as SliverMainAxisGroup).children.single, same(sliver));
  });

  group('PlacedBody', () {
    // On the default 800 x 600 test surface.
    const insets = EdgeInsets.fromLTRB(4, 100, 6, 80);

    Future<(Rect, EdgeInsets)> place(
      WidgetTester tester,
      BodyPlacement placement,
    ) async {
      late EdgeInsets inner;
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: insets),
          child: PlacedBody(
            placement: placement,
            child: Builder(
              key: key,
              builder: (context) {
                inner = MediaQuery.paddingOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return (tester.getRect(find.byKey(key)), inner);
    }

    testWidgets('pads every edge it does not run under', (tester) async {
      final (rect, inner) = await place(
        tester,
        const BodyPlacement(underTop: false, underBottom: false),
      );
      expect(rect, const Rect.fromLTRB(4, 100, 794, 520));
      expect(inner, EdgeInsets.zero);
    });

    testWidgets('leaves the edges it runs under to the scroll view', (
      tester,
    ) async {
      final (rect, inner) = await place(
        tester,
        const BodyPlacement(underTop: true, underBottom: true),
      );
      expect(rect, const Rect.fromLTRB(4, 0, 794, 600));
      expect(inner, const EdgeInsets.only(top: 100, bottom: 80));
    });
  });
}
