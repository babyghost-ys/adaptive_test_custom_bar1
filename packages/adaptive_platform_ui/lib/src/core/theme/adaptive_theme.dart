import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// How navigation bars look across the app.
@immutable
class AdaptiveBarStyle {
  /// The platform's own bar: Liquid Glass on iOS 26+, the classic bar on
  /// earlier iOS, the theme's app bar on Android.
  const AdaptiveBarStyle.system()
    : color = null,
      foreground = null,
      shadow = false,
      plainButtons = false;

  /// A solid [color] bar with [foreground] title, back button and actions.
  /// [shadow] draws a subtle shadow below it; [plainButtons] removes the
  /// glass background behind its buttons on iOS 26+.
  const AdaptiveBarStyle.solid(
    Color this.color, {
    this.foreground,
    this.shadow = false,
    this.plainButtons = false,
  });

  final Color? color;
  final Color? foreground;
  final bool shadow;
  final bool plainButtons;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveBarStyle &&
      color == other.color &&
      foreground == other.foreground &&
      shadow == other.shadow &&
      plainButtons == other.plainButtons;

  @override
  int get hashCode => Object.hash(color, foreground, shadow, plainButtons);
}

/// The app's look, set once on `AdaptiveApp` and shared by every platform.
///
/// `AdaptiveApp` derives its Material and Cupertino themes from this, so an
/// app states its colours once. Explicit Material or Cupertino themes passed
/// to `AdaptiveApp` still win.
@immutable
class AdaptiveThemeData {
  const AdaptiveThemeData({
    this.primaryColor,
    this.background,
    this.barStyle = const AdaptiveBarStyle.system(),
  });

  /// Accent for controls, selected tabs and links. Null keeps the platform
  /// default (system blue on iOS, the Material baseline on Android).
  final Color? primaryColor;

  /// Page background. Null keeps the platform default.
  final Color? background;

  final AdaptiveBarStyle barStyle;

  /// Cupertino theme for [brightness].
  CupertinoThemeData cupertino(Brightness brightness) => CupertinoThemeData(
    brightness: brightness,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: background,
  );

  /// Material theme for [brightness].
  ThemeData material(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: primaryColor == null
        ? null
        : ColorScheme.fromSeed(
            seedColor: primaryColor!,
            brightness: brightness,
          ),
    scaffoldBackgroundColor: background,
  );

  @override
  bool operator ==(Object other) =>
      other is AdaptiveThemeData &&
      primaryColor == other.primaryColor &&
      background == other.background &&
      barStyle == other.barStyle;

  @override
  int get hashCode => Object.hash(primaryColor, background, barStyle);
}

/// Provides the current [AdaptiveThemeData]. `AdaptiveApp` installs it.
class AdaptiveTheme extends InheritedWidget {
  const AdaptiveTheme({super.key, required this.data, required super.child});

  final AdaptiveThemeData data;

  static const _fallback = AdaptiveThemeData();

  /// The nearest theme, or the platform defaults when none is installed.
  static AdaptiveThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveTheme>()?.data ??
      _fallback;

  @override
  bool updateShouldNotify(AdaptiveTheme oldWidget) => data != oldWidget.data;
}
