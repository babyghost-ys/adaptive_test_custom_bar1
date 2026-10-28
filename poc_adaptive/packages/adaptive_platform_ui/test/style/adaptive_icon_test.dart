import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveIcon.iconData', () {
    test('prefers the Material icon', () {
      const icon = AdaptiveIcon(sfSymbol: 'house', icon: Icons.home_outlined);
      expect(icon.iconData, Icons.home_outlined);
    });

    test('maps a known SF Symbol to its Cupertino glyph', () {
      expect(
        const AdaptiveIcon(sfSymbol: 'house.fill').iconData,
        CupertinoIcons.house_fill,
      );
    });

    test('draws a neutral circle for an unknown symbol', () {
      expect(const AdaptiveIcon(sfSymbol: 'chart.pie').iconData, Icons.circle);
    });
  });

  group('AdaptiveIcon.build', () {
    test('uses the widget first', () {
      const child = Text('A');
      expect(
        const AdaptiveIcon(icon: Icons.home, widget: child).build(),
        same(child),
      );
    });

    test('draws an image as an ImageIcon', () {
      const image = AssetImage('assets/avatar.png');
      final built = const AdaptiveIcon(image: image).build(color: Colors.red);
      expect(built, isA<ImageIcon>());
      expect((built as ImageIcon).color, Colors.red);
    });

    test('draws an icon with the given colour and size', () {
      final built = const AdaptiveIcon(
        icon: Icons.star,
      ).build(color: Colors.red, size: 18);
      expect(built, isA<Icon>());
      expect((built as Icon).icon, Icons.star);
      expect(built.color, Colors.red);
      expect(built.size, 18);
    });
  });

  test('equal icons compare equal', () {
    expect(
      const AdaptiveIcon(sfSymbol: 'star', icon: Icons.star),
      const AdaptiveIcon(sfSymbol: 'star', icon: Icons.star),
    );
    expect(
      const AdaptiveIcon(sfSymbol: 'star'),
      isNot(const AdaptiveIcon(sfSymbol: 'star.fill')),
    );
  });

  test('needs at least one source', () {
    expect(AdaptiveIcon.new, throwsAssertionError);
  });
}
