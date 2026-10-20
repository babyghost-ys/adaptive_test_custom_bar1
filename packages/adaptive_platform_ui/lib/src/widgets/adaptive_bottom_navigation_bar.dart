import 'package:flutter/cupertino.dart';
import 'adaptive_scaffold.dart';
import 'adaptive_tab_search.dart';

/// Configuration for an adaptive bottom navigation bar in [AdaptiveScaffold].
///
/// The default native iOS path uses UIKit tab bars on iOS 15+, including iOS 18.
/// Supply nonempty [items], [selectedIndex] and [onTap]; UIKit supplies the
/// running OS's appearance. [search] optionally adds native search presentation.
/// The explicit legacy/custom scaffold path can use CupertinoTabBar.
/// Android uses a Material NavigationBar.
///
/// [cupertinoTabBar] supplies a custom tab bar for the legacy iOS path;
/// [bottomNavigationBar] supplies a custom Android bar. Otherwise [items]
/// configure the applicable platform bar.
class AdaptiveBottomNavigationBar {
  /// Creates an adaptive bottom navigation bar configuration
  const AdaptiveBottomNavigationBar({
    this.items,
    this.selectedIndex,
    this.onTap,
    this.useNativeBottomBar = true,
    this.cupertinoTabBar,
    this.bottomNavigationBar,
    this.selectedItemColor,
    this.unselectedItemColor,
    this.search,
  });

  /// Navigation items for bottom navigation bar
  /// These will be used to build the platform-specific navigation items if custom
  /// bars are not provided.
  final List<AdaptiveNavigationDestination>? items;

  /// Currently selected item index
  /// If null, no item will be selected
  final int? selectedIndex;

  /// Called when a navigation item is tapped
  /// If null, navigation will not be interactive
  final ValueChanged<int>? onTap;

  /// Enables a native UIKit search destination on supported iOS versions.
  /// iOS 26+ uses UISearchTab and its system search presentation; iOS 18 uses
  /// a native navigation search field at the top. UIKit adapts side-bar layouts.
  /// Requires [useNativeBottomBar] and exactly one isSearch destination.
  /// Render its content when [onTap] selects that index and omit its app bar;
  /// UIKit owns the search title. Use SF Symbol string tab icons.
  final AdaptiveTabSearch? search;

  /// Requests native UIKit tab rendering; defaults to true.
  /// On iOS 15+, nonempty [items], [selectedIndex] and [onTap] select the native
  /// tab host. [search] is optional. UIKit owns the running OS's tab appearance.
  ///
  /// In the explicit legacy scaffold path, false uses [cupertinoTabBar] when
  /// supplied and otherwise creates a CupertinoTabBar. Custom Cupertino bars
  /// belong to that legacy path, selected by an app bar with
  /// useNativeToolbar: false. The native app-bar scaffold owns its UIKit tab
  /// rendering and does not consume a custom [cupertinoTabBar].
  final bool useNativeBottomBar;

  /// Custom CupertinoTabBar for the explicit legacy iOS scaffold path.
  /// Used when that path has native bottom rendering disabled.
  /// The native app-bar and default native tab/search hosts ignore it.
  /// When omitted, the legacy path creates its tab bar from [items].
  /// Ignored on Android.
  final CupertinoTabBar? cupertinoTabBar;

  /// Custom NavigationBar or BottomNavigationBar for Android
  ///
  /// When provided, this custom navigation bar will be used instead of building one
  /// from [items].
  ///
  /// Ignored on iOS platforms.
  final Widget? bottomNavigationBar;

  /// Color for the selected navigation item
  ///
  /// When provided:
  /// - Native iOS rendering: configures the selected-item tint.
  /// - Legacy CupertinoTabBar: sets activeColor.
  /// - Android (NavigationBar): sets indicatorColor and pairs an inherited
  ///   selected icon with a contrasting foreground. Explicit colors in custom
  ///   icon widgets remain the caller's responsibility.
  ///
  /// If null, uses platform defaults.
  final Color? selectedItemColor;

  /// Color for unselected navigation items
  ///
  /// When provided:
  /// - Native iOS rendering: configures the unselected-item tint when supported.
  /// - Legacy CupertinoTabBar: sets inactiveColor.
  /// - Android (NavigationBar): Not directly supported, but can affect icon colors
  ///
  /// If null, uses platform defaults.
  final Color? unselectedItemColor;

  /// Creates a copy of this bottom navigation bar with the given fields replaced
  AdaptiveBottomNavigationBar copyWith({
    List<AdaptiveNavigationDestination>? items,
    int? selectedIndex,
    ValueChanged<int>? onTap,
    bool? useNativeBottomBar,
    CupertinoTabBar? cupertinoTabBar,
    Widget? bottomNavigationBar,
    Color? selectedItemColor,
    Color? unselectedItemColor,
    AdaptiveTabSearch? search,
  }) {
    return AdaptiveBottomNavigationBar(
      items: items ?? this.items,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      onTap: onTap ?? this.onTap,
      useNativeBottomBar: useNativeBottomBar ?? this.useNativeBottomBar,
      cupertinoTabBar: cupertinoTabBar ?? this.cupertinoTabBar,
      bottomNavigationBar: bottomNavigationBar ?? this.bottomNavigationBar,
      selectedItemColor: selectedItemColor ?? this.selectedItemColor,
      unselectedItemColor: unselectedItemColor ?? this.unselectedItemColor,
      search: search ?? this.search,
    );
  }
}
