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
      plainButtons = false,
      fillsDuoStrip = false,
      duoStripGradient = null;

  /// A solid [color] bar with [foreground] title, back button and actions.
  /// [shadow] draws a subtle shadow below it; [plainButtons] removes the
  /// glass background behind its buttons on iOS 26+.
  ///
  /// On iPhone Duo the system reserves a strip at one edge of the window for
  /// the vertical bar. [fillsDuoStrip] paints that strip with [color], so the
  /// bar reads as one band from the top of the window down the strip. Pass
  /// false to leave the strip in the page background. [duoStripGradient]
  /// paints the strip with a gradient instead of [color]; start a vertical
  /// one at [color] so it joins the solid top bar without a seam.
  const AdaptiveBarStyle.solid(
    Color this.color, {
    this.foreground,
    this.shadow = false,
    this.plainButtons = false,
    this.fillsDuoStrip = true,
    this.duoStripGradient,
  });

  final Color? color;
  final Color? foreground;
  final bool shadow;
  final bool plainButtons;

  /// Whether the iPhone Duo vertical bar strip is painted with [color].
  final bool fillsDuoStrip;

  /// Paints the iPhone Duo strip in place of [color] when [fillsDuoStrip].
  final Gradient? duoStripGradient;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveBarStyle &&
      color == other.color &&
      foreground == other.foreground &&
      shadow == other.shadow &&
      plainButtons == other.plainButtons &&
      fillsDuoStrip == other.fillsDuoStrip &&
      duoStripGradient == other.duoStripGradient;

  @override
  int get hashCode => Object.hash(
    color,
    foreground,
    shadow,
    plainButtons,
    fillsDuoStrip,
    duoStripGradient,
  );
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
