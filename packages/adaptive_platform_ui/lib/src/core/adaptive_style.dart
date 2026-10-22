import 'package:flutter/widgets.dart';

import 'platform_info.dart';

/// Which family of controls the package's widgets render.
///
/// Every `Adaptive*` widget switches on this once, so a whole app, a screen
/// or a test can be moved to the other family by wrapping it in an
/// [AdaptiveStyleScope].
enum AdaptiveStyle {
  /// Flutter's Material widgets and the app's Material theme.
  material,

  /// The running iOS release's own UIKit controls. Only available on iOS;
  /// requesting it elsewhere resolves to [material].
  native;

  /// The platform's own family: [native] on iOS, [material] elsewhere.
  static AdaptiveStyle get platformDefault =>
      PlatformInfo.isIOS ? native : material;

  /// The style for [context]: the nearest [AdaptiveStyleScope], or the
  /// platform's own family.
  static AdaptiveStyle of(BuildContext context) {
    final requested =
        context
            .dependOnInheritedWidgetOfExactType<AdaptiveStyleScope>()
            ?.style ??
        platformDefault;
    return requested == native && !PlatformInfo.isIOS ? material : requested;
  }
}

/// Sets the [AdaptiveStyle] for its subtree.
class AdaptiveStyleScope extends InheritedWidget {
  const AdaptiveStyleScope({
    super.key,
    required this.style,
    required super.child,
  });

  final AdaptiveStyle style;

  @override
  bool updateShouldNotify(AdaptiveStyleScope oldWidget) =>
      style != oldWidget.style;
}

/// What the running system can draw. The iOS version is read here only;
/// widgets ask for a capability, never for a version number.
abstract final class AdaptiveCapabilities {
  /// Liquid Glass bars and controls that content scrolls under (iOS 26+).
  static bool get liquidGlass => PlatformInfo.isIOS26OrHigher();

  /// The system reports where it puts its vertical bar (iPhone Duo). The
  /// channel answers from iOS 26; earlier releases never place one.
  static bool get systemVerticalBarEdge => PlatformInfo.isIOS26OrHigher();
}
