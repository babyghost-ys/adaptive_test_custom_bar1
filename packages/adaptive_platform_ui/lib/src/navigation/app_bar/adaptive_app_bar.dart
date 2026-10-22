import 'package:flutter/widgets.dart';
import '../../core/theme/adaptive_theme.dart';
import 'adaptive_app_bar_action.dart';

/// Configuration for an adaptive app bar in [AdaptiveScaffold].
///
/// On iOS the bar is the running system's own UINavigationBar: UIKit supplies
/// its appearance, title collapse and bar buttons. [cupertinoNavigationBar]
/// replaces it with the app's own bar, such as an
/// `AdaptiveNavigationSearchBar`. Android uses a Material AppBar, or [appBar]
/// when supplied.
class AdaptiveAppBar {
  /// Creates an adaptive app bar configuration
  const AdaptiveAppBar({
    this.title,
    this.largeTitle = false,
    this.subtitle,
    this.actions,
    this.leading,
    this.tintColor,
    this.navigationBarColor,
    this.navigationBarShadow,
    this.hidesNavigationButtonBackground,
    this.titleWidget,
    this.cupertinoNavigationBar,
    this.appBar,
  });

  /// Title for the app bar
  final String? title;

  /// Native scrolling large title on iOS 15+, including iOS 18.
  /// The page's scroll view collapses it; no controller or spacer is needed.
  /// Other platform and explicit legacy paths keep their compact bars.
  final bool largeTitle;

  /// Optional subtitle displayed below the title
  final String? subtitle;

  /// Action buttons in the app bar
  /// - Native iOS path: UIBarButtonItems in the system navigation bar.
  /// - Explicit legacy iOS path: buttons in CupertinoNavigationBar.
  /// - Android: IconButtons in Material AppBar.
  final List<AdaptiveAppBarAction>? actions;

  /// Leading widget in the app bar (e.g., back button, menu button)
  /// If null and navigation is possible, an automatic back button will be shown
  final Widget? leading;

  /// Whether iOS shows the native UIKit bar: true unless the app supplies
  /// its own [cupertinoNavigationBar].
  bool get useNativeToolbar => cupertinoNavigationBar == null;

  /// Custom widget to display in the title area
  ///
  /// When set, this widget replaces the default title text rendering.
  /// On the native iOS path, it is overlaid centered over the toolbar.
  /// On the explicit legacy iOS path, it is the CupertinoNavigationBar middle.
  /// Use [title] to keep system-owned native title rendering and collapse.
  /// On Android, it is used as the AppBar title.
  final Widget? titleWidget;

  /// Tint color for action and back buttons on the native iOS path.
  /// Null takes the foreground of the app's [AdaptiveBarStyle].
  ///
  /// When set, this color is applied to the navigation bar's tintColor,
  /// which colors all bar button items (action buttons and back button).
  /// If null, the system default tint color is used.
  final Color? tintColor;

  /// Opaque native navigation background, including its scroll-edge appearance.
  /// Null takes the colour of the app's [AdaptiveBarStyle].
  final Color? navigationBarColor;

  /// Draws a subtle native shadow below a [navigationBarColor] bar on the
  /// native iOS path. Ignored without [navigationBarColor].
  /// Null takes the app's [AdaptiveBarStyle.shadow].
  final bool? navigationBarShadow;

  /// Removes the shared glass background from native navigation buttons.
  /// Null takes the app's [AdaptiveBarStyle.plainButtons].
  final bool? hidesNavigationButtonBackground;

  /// Custom iOS navigation bar, including AdaptiveNavigationSearchBar.
  ///
  /// When provided and [useNativeToolbar] is false, this custom navigation bar will be used
  /// instead of building one from [title], [actions], and [leading].
  ///
  /// Ignored when [useNativeToolbar] is true or on non-iOS platforms.
  final PreferredSizeWidget? cupertinoNavigationBar;

  /// Custom AppBar for Android
  ///
  /// When provided, this custom app bar will be used instead of building one
  /// from [title], [actions], and [leading].
  ///
  /// Ignored on iOS platforms.
  final PreferredSizeWidget? appBar;

  /// Creates a copy of this app bar with the given fields replaced
  AdaptiveAppBar copyWith({
    String? title,
    bool? largeTitle,
    String? subtitle,
    List<AdaptiveAppBarAction>? actions,
    Widget? leading,
    Color? tintColor,
    Color? navigationBarColor,
    bool? navigationBarShadow,
    bool? hidesNavigationButtonBackground,
    Widget? titleWidget,
    PreferredSizeWidget? cupertinoNavigationBar,
    PreferredSizeWidget? appBar,
  }) {
    return AdaptiveAppBar(
      title: title ?? this.title,
      largeTitle: largeTitle ?? this.largeTitle,
      subtitle: subtitle ?? this.subtitle,
      actions: actions ?? this.actions,
      leading: leading ?? this.leading,
      tintColor: tintColor ?? this.tintColor,
      navigationBarColor: navigationBarColor ?? this.navigationBarColor,
      navigationBarShadow: navigationBarShadow ?? this.navigationBarShadow,
      hidesNavigationButtonBackground:
          hidesNavigationButtonBackground ??
          this.hidesNavigationButtonBackground,
      titleWidget: titleWidget ?? this.titleWidget,
      cupertinoNavigationBar:
          cupertinoNavigationBar ?? this.cupertinoNavigationBar,
      appBar: appBar ?? this.appBar,
    );
  }
}
