import 'package:adaptive_platform_ui/src/navigation/app_bar/native_toolbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Duo controls block underlying views, content stays interactive',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      int? viewId;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = (call.arguments as Map)['id'] as int;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      var underlyingTouches = 0;
      await tester.pumpWidget(
        CupertinoApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => underlyingTouches++,
                  child: const SizedBox.expand(),
                ),
              ),
              const NativeToolbar(title: 'Cards', verticalNavigation: true),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(viewId, isNotNull);
      await messenger.handlePlatformMessage(
        'adaptive_platform_ui/ios26_toolbar_$viewId',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onNavigationMetrics', {
            'generation': 0,
            'contentInset': 80.0,
            'barBottom': 80.0,
            'chromeRegions': [
              [0.0, 0.0, 800.0, 80.0],
              [720.0, 100.0, 60.0, 60.0],
            ],
          }),
        ),
        (_) {},
      );
      await tester.pump();
      await tester.tapAt(const Offset(750, 130));
      expect(
        underlyingTouches,
        0,
        reason: 'Menu taps must not reach the tab/search layer',
      );
      await tester.tapAt(const Offset(250, 300));
      expect(
        underlyingTouches,
        1,
        reason: 'Content outside native chrome must stay interactive',
      );
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
