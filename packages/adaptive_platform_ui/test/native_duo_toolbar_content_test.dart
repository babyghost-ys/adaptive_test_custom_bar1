import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Duo preserves native large title, scroll bridge and actions', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final scroll = AdaptiveNavigationScrollController();
    addTearDown(scroll.dispose);
    var pressed = false;
    final action = AdaptiveAppBarAction(
      iosSymbol: 'person.crop.circle',
      label: 'Profile',
      onPressed: () => pressed = true,
    );
    final entry = ToolbarEntry(
      id: Object(),
      appBar: AdaptiveAppBar(
        title: 'Spending',
        largeTitle: true,
        scrollController: scroll,
        actions: [action],
      ),
      route: null,
      navigator: null,
      visible: true,
    );
    final duo = TopToolbarContent.of(entry, titleOnly: true);
    final phone = TopToolbarContent.of(entry);
    expect(duo.title, phone.title);
    expect(duo.largeTitle, isTrue);
    expect(duo.scrollController, same(scroll));
    expect(duo.titleOverlay, isNull);
    expect(duo.actions.single, same(action));
    duo.actions.single.onPressed();
    expect(pressed, isTrue);
  });
}
