import '../../style/adaptive_icon.dart';
import '../../core/adaptive_style.dart';
import '../tab_bar/native_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/adaptive_theme.dart';
import '../app_bar/adaptive_app_bar.dart';
import '../app_bar/adaptive_navigation_scroll_controller.dart';
import '../search/adaptive_navigation_search_bar.dart';
import '../../content/badge/adaptive_badge.dart';
import '../tab_bar/adaptive_bottom_navigation_bar.dart';
import '../drawer/adaptive_drawer.dart';
import 'body_placement.dart';
import 'native_scaffold.dart';
import 'native_bottom_bar_layout.dart';
import '../search/native_search_tab_scaffold.dart';
import '../chrome/toolbar_chrome_scope.dart';
import '../chrome/toolbar_registry.dart';
import '../app_bar/adaptive_app_bar_action.dart';

part 'scaffold_native.dart';
part 'scaffold_cupertino.dart';
part 'scaffold_material.dart';

/// Navigation destination for bottom navigation
class AdaptiveNavigationDestination {
  const AdaptiveNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.isSearch = false,
    this.badgeCount,
    this.badgeText,
    this.badgeColor,
    this.badgeTextColor,
    this.addSpacerAfter = false,
  });

  /// Icon to display. The native iOS tab bar uses its SF Symbol or image;
  /// Flutter-drawn tab bars draw an image as a round avatar.
  final AdaptiveIcon icon;

  /// Label text for the destination
  final String label;

  /// Icon for the selected state, such as a filled symbol. Falls back to
  /// [icon] when null.
  final AdaptiveIcon? selectedIcon;

  /// Whether this is a search tab (iOS 26+)
  /// Search tabs are visually separated and transform into a search field
  final bool isSearch;

  /// Badge count to display on the tab (null means no badge)
  /// On iOS 26+: Uses native UITabBarItem.badgeValue
  /// On iOS <26 and Android: Uses AdaptiveBadge widget
  final int? badgeCount;

  /// Arbitrary badge text, such as "NEW", "!" or a glyph. Takes precedence
  /// over [badgeCount] when non-null.
  ///
  /// - iOS 26+: `UITabBarItem.badgeValue`
  /// - iOS <26 and Android: the label of the [AdaptiveBadge] drawn on the icon
  ///
  /// Tip: combine `badgeText: "●"` with a transparent [badgeColor] and a
  /// [badgeTextColor] to render a dot indicator without a pill background.
  final String? badgeText;

  /// Badge background color. Null means the platform default (system red).
  /// A transparent color removes the pill background, e.g. for a dot.
  ///
  /// - iOS 26+: `UITabBarItem.badgeColor`
  /// - iOS <26 and Android: [AdaptiveBadge.backgroundColor]
  final Color? badgeColor;

  /// Badge text color. Null means the platform default (white).
  ///
  /// - iOS 26+: the badge's text attributes
  /// - iOS <26 and Android: [AdaptiveBadge.textColor]
  final Color? badgeTextColor;

  /// Whether this destination shows a badge on any platform.
  bool get hasBadge =>
      (badgeText != null && badgeText!.isNotEmpty) ||
      (badgeCount != null && badgeCount! > 0);

  /// [child] with this destination's badge drawn on it, for the iOS <26 and
  /// Android tab bars. The native iOS 26+ bar draws its own badge.
  Widget wrapWithBadge(Widget child) => AdaptiveBadge(
    label: badgeText,
    count: badgeText == null ? badgeCount : null,
    backgroundColor: badgeColor,
    textColor: badgeTextColor,
    child: child,
  );

  /// [child] with the badge when this destination has one.
  Widget wrapIfBadged(Widget child) => hasBadge ? wrapWithBadge(child) : child;

  /// Add flexible space after this tab item (iOS 26+ only)
  /// Useful for creating grouped tabs (e.g., left group and right group)
  /// Only applies to iOS 26+ native tab bar
  final bool addSpacerAfter;
}

/// An adaptive scaffold that renders platform-specific navigation
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.body,
    this.resizeToAvoidBottomInset,
    this.floatingActionButton,
    this.extendBodyBehindAppBar,
    this.extendBody,
    this.backgroundColor,
    this.customHeaderBackgroundColor,
    this.customHeaderHeight = 0,
    this.drawer,
    this.endDrawer,
    this.drawerScrimColor,
    this.onDrawerChanged,
    this.onEndDrawerChanged,
    this.drawerEnableOpenDragGesture = true,
    this.endDrawerEnableOpenDragGesture = true,
    this.scaffoldKey,
    this.useHeroBackButton = true,
    this.useFixedToolbar = true,
    this.tabBarHidden = false,
  });

  /// App bar configuration
  /// If null, no app bar or toolbar will be shown
  final AdaptiveAppBar? appBar;

  /// Bottom navigation bar configuration
  /// If null, no bottom navigation will be shown
  final AdaptiveBottomNavigationBar? bottomNavigationBar;

  /// Body widget
  final Widget? body;

  /// Whether the scaffold should resize when the on-screen keyboard appears.
  ///
  /// When null, each platform path uses its existing default behavior.
  /// Set to `false` to keep bottom navigation pinned while the keyboard
  /// overlays content, such as on iOS tab-based layouts.
  final bool? resizeToAvoidBottomInset;

  /// Floating action button (Material only)
  final Widget? floatingActionButton;

  /// Whether the body runs under the top bar, like
  /// [Scaffold.extendBodyBehindAppBar]. The bar's height then stays in
  /// [MediaQuery.padding] for the body's scroll view to apply.
  ///
  /// Null decides for you: on iOS a body that is itself a vertical scroll
  /// view runs under the glass bar on iOS 26+, and under a large title on
  /// every version; anything else sits below the bar. Android keeps the body
  /// below its app bar.
  final bool? extendBodyBehindAppBar;

  /// Whether the body runs under [bottomNavigationBar], like
  /// [Scaffold.extendBody]. Null decides for you as
  /// [extendBodyBehindAppBar] does: under the glass tab bar of iOS 26+ for a
  /// body that is a scroll view, above the bar otherwise.
  final bool? extendBody;

  /// Background colour of the page on every platform. Null keeps the
  /// platform default: the Material or Cupertino theme's scaffold colour
  /// (#60, #95). An opaque colour also sets the status bar style to
  /// contrast with it, so a dark page in a light theme keeps a readable
  /// status bar (#77).
  final Color? backgroundColor;

  /// Extends an explicitly custom header behind native side chrome.
  final Color? customHeaderBackgroundColor;
  final double customHeaderHeight;

  /// A panel displayed to the side of the body. An [AdaptiveDrawer] opens
  /// as a native panel on iOS and a Material drawer elsewhere; any other
  /// widget is a Material drawer everywhere. Open it with
  /// [AdaptiveScaffoldState.openDrawer].
  final Widget? drawer;

  /// A panel displayed on the opposite side of the drawer.
  /// Open programmatically via `Scaffold.of(context).openEndDrawer()`.
  final Widget? endDrawer;

  /// The color to use for the scrim that obscures the content behind the drawer.
  final Color? drawerScrimColor;

  /// Called when the drawer is opened or closed.
  final DrawerCallback? onDrawerChanged;

  /// Called when the end drawer is opened or closed.
  final DrawerCallback? onEndDrawerChanged;

  /// Whether to enable the drag gesture to open the drawer.
  final bool drawerEnableOpenDragGesture;

  /// Whether to enable the drag gesture to open the end drawer.
  final bool endDrawerEnableOpenDragGesture;

  /// A key to use for the internal [Scaffold] that provides drawer behavior.
  /// Use this to open the drawer programmatically via
  /// `scaffoldKey.currentState?.openDrawer()`.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// Whether to use Hero animation for the back button on iOS 26+
  /// When true, the back button stays pinned during page transitions.
  /// Only affects iOS 26+. Defaults to true.
  final bool useHeroBackButton;

  /// Whether this page hands its app bar to the fixed toolbar that
  /// [AdaptiveApp] keeps above the navigator on iOS 26+ (see
  /// [AdaptiveToolbarHost]). Defaults to true.
  ///
  /// Set it to false for a scaffold that does not fill the screen from the
  /// top, such as one pane of a side by side layout: the fixed toolbar sits at
  /// the top of the app, so such a page should keep drawing a toolbar of its
  /// own, where it is. Scaffolds shown in a sheet, dialog or popup (any route
  /// that is not a page) do this automatically.
  final bool useFixedToolbar;

  /// Whether to hide the native tab bar (iOS 26+ only).
  /// Use this to hide the tab bar when showing modal bottom sheets
  /// to prevent native platform views from bleeding through.
  final bool tabBarHidden;

  /// The nearest [AdaptiveScaffoldState] above [context].
  static AdaptiveScaffoldState of(BuildContext context) =>
      context.findAncestorStateOfType<AdaptiveScaffoldState>()!;

  @override
  State<AdaptiveScaffold> createState() => AdaptiveScaffoldState();
}

/// The state of an [AdaptiveScaffold]. Opens and closes its drawer, like
/// [ScaffoldState]: give the scaffold a `GlobalKey<AdaptiveScaffoldState>`,
/// or find it with [AdaptiveScaffold.of].
class AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  final GlobalKey<ScaffoldState> _ownScaffoldKey = GlobalKey<ScaffoldState>();
  GlobalKey<ScaffoldState> get _scaffoldKey =>
      widget.scaffoldKey ?? _ownScaffoldKey;

  /// An [AdaptiveDrawer] on iOS opens as a native panel instead of a
  /// Material drawer.
  AdaptiveDrawer? get _nativeDrawer {
    final drawer = widget.drawer;
    return _native && drawer is AdaptiveDrawer ? drawer : null;
  }

  bool _nativeDrawerOpen = false;

  /// Whether this page renders the native iOS family.
  bool get _native => AdaptiveStyle.of(context) == AdaptiveStyle.native;

  /// Whether the drawer is showing.
  bool get isDrawerOpen =>
      _nativeDrawerOpen || (_scaffoldKey.currentState?.isDrawerOpen ?? false);

  /// Opens [AdaptiveScaffold.drawer].
  Future<void> openDrawer() async {
    final drawer = _nativeDrawer;
    if (drawer == null) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    if (_nativeDrawerOpen) return;
    _nativeDrawerOpen = true;
    widget.onDrawerChanged?.call(true);
    try {
      await drawer.presentNative(context);
    } finally {
      _nativeDrawerOpen = false;
      if (mounted) widget.onDrawerChanged?.call(false);
    }
  }

  /// Closes the drawer without a selection.
  void closeDrawer() {
    if (_nativeDrawerOpen) {
      AdaptiveDrawer.dismissNative();
    } else {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  /// The fixed toolbar chrome this page publishes its app bar to, if an
  /// [AdaptiveToolbarHost] is installed above the navigator.
  ToolbarRegistry? _toolbarRegistry;

  /// Links the body's scroll view to the native bar when the app brought no
  /// controller of its own: UIKit reports this page's bar metrics through
  /// it, and follows its offset to collapse a large title.
  AdaptiveNavigationScrollController? _pageScroll;
  AdaptiveBarStyle _barStyle = const AdaptiveBarStyle.system();
  AdaptiveAppBar? _appBarSource;
  AdaptiveBarStyle? _appBarSourceStyle;
  AdaptiveBottomNavigationBar? _appBarSourceTabs;
  AdaptiveAppBar? _resolvedAppBar;

  /// [AdaptiveScaffold.appBar] as drawn: unset colours and flags taken from
  /// the app's [AdaptiveBarStyle], a tab root's missing title taken from its
  /// selected tab, and on the native iOS path the page's own scroll
  /// controller filled in.
  AdaptiveAppBar? get _appBar {
    final appBar = widget.appBar;
    if (appBar == null) return null;
    final tabs = widget.bottomNavigationBar;
    if (!identical(appBar, _appBarSource) ||
        _barStyle != _appBarSourceStyle ||
        !identical(tabs, _appBarSourceTabs)) {
      _appBarSource = appBar;
      _appBarSourceStyle = _barStyle;
      _appBarSourceTabs = tabs;
      final items = tabs?.items;
      final index = tabs?.selectedIndex;
      final tabTitle =
          appBar.title == null &&
              appBar.titleWidget == null &&
              items != null &&
              index != null &&
              index >= 0 &&
              index < items.length
          ? items[index].label
          : null;
      final linksScroll =
          _native && appBar.useNativeToolbar && appBar.scrollController == null;
      _resolvedAppBar = appBar.copyWith(
        title: tabTitle,
        navigationBarColor: appBar.navigationBarColor ?? _barStyle.color,
        tintColor: appBar.tintColor ?? _barStyle.foreground,
        navigationBarShadow: appBar.navigationBarShadow ?? _barStyle.shadow,
        hidesNavigationButtonBackground:
            appBar.hidesNavigationButtonBackground ?? _barStyle.plainButtons,
        scrollController: linksScroll
            ? _pageScroll ??= AdaptiveNavigationScrollController()
            : null,
      );
    }
    return _resolvedAppBar;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barStyle = AdaptiveTheme.of(context).barStyle;
    _syncToolbarEntry();
  }

  @override
  void didUpdateWidget(AdaptiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appBar != widget.appBar ||
        oldWidget.useFixedToolbar != widget.useFixedToolbar ||
        oldWidget.tabBarHidden != widget.tabBarHidden ||
        oldWidget.bottomNavigationBar != widget.bottomNavigationBar) {
      _syncToolbarEntry();
    }
    if (oldWidget.bottomNavigationBar?.selectedIndex !=
        widget.bottomNavigationBar?.selectedIndex) {
      // Another tab's scroll view takes over the shared controller once the
      // new tab is on stage.
      final scroll = _appBar?.scrollController;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scroll?.activeChanged(),
      );
    }
  }

  @override
  void dispose() {
    _toolbarRegistry?.remove(this);
    _pageScroll?.dispose();
    super.dispose();
  }

  /// Publishes this page's app bar to the fixed toolbar chrome.
  ///
  /// Reading [ModalRoute.of], `TickerMode.of` and [Visibility.of] here
  /// registers dependencies on the route's live status and on the page's
  /// visibility, so this re-runs exactly when the page stops (or starts) being
  /// the current route, or is hidden/shown by a tab switch: the moments the
  /// chrome has to pick another page's items. No-op when no host is installed.
  ///
  /// Both visibility signals are needed because tab containers hide pages
  /// differently: GoRouter's `StatefulShellRoute.indexedStack` and
  /// `CupertinoTabScaffold` use `Offstage` + a disabled [TickerMode], while a
  /// plain [IndexedStack] uses [Visibility.maintain], which keeps tickers
  /// enabled and is only observable through [Visibility.of].
  /// Whether this scaffold's toolbar belongs in the fixed chrome: it asked
  /// for it and it is a page. A sheet or dialog is not at the top of the
  /// screen, so a scaffold inside one keeps its own toolbar.
  bool _usesFixedToolbar(BuildContext context) {
    if (!widget.useFixedToolbar) return false;
    final route = ModalRoute.of(context);
    return route == null || route is PageRoute;
  }

  /// The tab bar the fixed chrome may draw in the iPhone Duo trailing bar:
  /// only the native one. A custom `CupertinoTabBar` or bottom widget
  /// (`useNativeBottomBar: false`) is the app's own and stays where it is.
  AdaptiveBottomNavigationBar? get _tabBarForChrome {
    final bar = widget.bottomNavigationBar;
    if (bar == null || widget.tabBarHidden || !bar.useNativeBottomBar) {
      return null;
    }
    if (bar.items == null || bar.selectedIndex == null || bar.onTap == null) {
      return null;
    }
    return bar;
  }

  bool _tabsInTrailingBar(BuildContext context) =>
      _usesFixedToolbar(context) &&
      (ToolbarChromeScope.maybeOf(context)?.hostsDuoControls ?? false);

  void _syncToolbarEntry() {
    final registry = ToolbarRegistry.maybeOf(context);
    if (registry == null) return;
    if (!_usesFixedToolbar(context)) {
      _toolbarRegistry?.remove(this);
      _toolbarRegistry = null;
      return;
    }
    _toolbarRegistry = registry;
    final navigator = Navigator.maybeOf(context);
    // Routes of the navigators around this page's own one (tabs, shell
    // routes). `Navigator.maybeOf` would hand a navigator's context straight
    // back to itself, so step to its ancestor explicitly.
    final enclosingRoutes = <ModalRoute<Object?>>[];
    var outer = navigator?.context;
    while (outer != null) {
      final route = ModalRoute.of(outer);
      if (route == null) break;
      enclosingRoutes.add(route);
      outer = outer.findAncestorStateOfType<NavigatorState>()?.context;
    }
    registry.upsert(
      ToolbarEntry(
        id: this,
        appBar: _appBar,
        route: ModalRoute.of(context),
        navigator: navigator,
        enclosingRoutes: enclosingRoutes,
        titleOverlay: _buildIOS26TitleOverlay(),
        // `TickerMode.valuesOf` replaces this, but only exists in Flutter
        // releases after 3.35; `of` works on every supported version.
        // ignore: deprecated_member_use
        visible: TickerMode.of(context) && Visibility.of(context),
        shownInPlace: Visibility.of(context),
        tabBar: _tabBarForChrome,
      ),
    );
  }

  /// Builds the app bar title area, optionally with a subtitle below it.
  ///
  /// Returns [AdaptiveAppBar.titleWidget] verbatim when provided; otherwise a
  /// title (plus subtitle when set). When [nativeTitleFallback] is true the
  /// plain-title case returns null so the iOS 26 native toolbar can render the
  /// title itself; the other paths return a plain `Text` instead.
  Widget? _buildAppBarTitle({
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    TextStyle? titleStyle,
    double subtitleFontSize = 12,
    Color? subtitleColor,
    bool nativeTitleFallback = false,
  }) {
    if (_appBar?.titleWidget != null) return _appBar!.titleWidget;
    final title = _appBar?.title;
    if (title == null) return null;
    final subtitle = _appBar?.subtitle;
    if (subtitle == null || subtitle.isEmpty) {
      return nativeTitleFallback ? null : Text(title, style: titleStyle);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(title, style: titleStyle),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.normal,
            color: subtitleColor,
          ),
        ),
      ],
    );
  }

  /// iOS 26+ native toolbar title overlay. The native title is a plain string,
  /// so a subtitle (or custom widget) is drawn as a Flutter overlay instead.
  /// Colors resolve from the ambient brightness so the overlay matches the
  /// native title in light and dark mode.
  Widget? _buildIOS26TitleOverlay() {
    return _buildAppBarTitle(
      nativeTitleFallback: true,
      titleStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: CupertinoColors.label.resolveFrom(context),
      ),
      subtitleColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
  }

  Widget _wrapWithDrawerIfNeeded(Widget child) {
    final drawer = _nativeDrawer == null ? widget.drawer : null;
    if (drawer == null && widget.endDrawer == null) {
      return child;
    }
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      body: child,
      drawer: drawer,
      endDrawer: widget.endDrawer,
      drawerScrimColor: widget.drawerScrimColor,
      onDrawerChanged: widget.onDrawerChanged,
      onEndDrawerChanged: widget.onEndDrawerChanged,
      drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.bottomNavigationBar;
    final nativeTabs =
        _native &&
        bar?.useNativeBottomBar == true &&
        bar?.items?.isNotEmpty == true &&
        bar?.selectedIndex != null &&
        bar?.onTap != null;
    final nativeSearch = nativeTabs && bar?.search != null;
    assert(
      !nativeSearch ||
          (bar!.items!.where((item) => item.isSearch).length == 1 &&
              bar.selectedIndex != null &&
              bar.onTap != null),
      'Native tab search requires one search destination, selectedIndex and onTap.',
    );
    final page = nativeTabs
        ? NativeSearchTabScaffold(
            bar: bar!,
            headerBackgroundColor: widget.customHeaderBackgroundColor,
            headerHeight: widget.customHeaderHeight,
            backgroundColor: widget.backgroundColor,
            hidden:
                widget.tabBarHidden ||
                !(ModalRoute.of(context)?.isCurrent ?? true),
            releasesBottomInset: widget.tabBarHidden,
            builder: (context) => _buildPage(context, omitBottomBar: true),
          )
        : _buildPage(context);
    final bg = _appBar?.navigationBarColor ?? widget.backgroundColor;
    if (bg == null || bg.a < 0.5) return page;
    // A page that sets its own background keeps the status bar legible
    // over it, whatever the app theme says: light icons on a dark page and
    // dark icons on a light one. Pages without a colour follow the theme
    // through AdaptiveApp, and an inner AnnotatedRegion still wins (#77).
    final dark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: page,
    );
  }

  /// The page in this scaffold's style: native UIKit bars, a custom iOS
  /// bar when the app bar opts out of the native toolbar, or Material.
  Widget _buildPage(BuildContext context, {bool omitBottomBar = false}) {
    final bottomBar = omitBottomBar ? null : widget.bottomNavigationBar;
    if (!_native) return _buildMaterial(context, bottomBar);
    return (_appBar?.useNativeToolbar ?? false)
        ? _buildNative(context, bottomBar)
        : _buildCupertino(context, bottomBar);
  }

  /// A Flutter-drawn tab icon: an image as a round avatar, anything else
  /// as the icon's own widget or glyph.
  Widget _buildNavigationIconWidget({
    required AdaptiveIcon rawIcon,
    Color? color,
  }) {
    final image = rawIcon.widget == null ? rawIcon.image : null;
    if (image != null) return _NavigationImageIcon(image: image);
    return rawIcon.build(color: color);
  }
}

class _NavigationImageIcon extends StatelessWidget {
  const _NavigationImageIcon({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: ClipOval(
        child: Image(
          image: image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(CupertinoIcons.person_crop_circle),
        ),
      ),
    );
  }
}

/// Gives an iOS page body the [Material] ancestor that ink effects and
/// [ListTile] need, without changing its text style the way a [Material]
/// does by default.
class _MaterialAncestor extends StatelessWidget {
  const _MaterialAncestor({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    textStyle: DefaultTextStyle.of(context).style,
    child: child,
  );
}
