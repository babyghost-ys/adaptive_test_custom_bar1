part of 'adaptive_scaffold.dart';

/// The iOS path for a page without a native toolbar: one whose app bar brings
/// its own `cupertinoNavigationBar` (such as an `AdaptiveNavigationSearchBar`),
/// or one with no app bar.
extension _CupertinoScaffold on AdaptiveScaffoldState {
  Widget _buildCupertino(
    BuildContext context,
    AdaptiveBottomNavigationBar? bottomBar,
  ) {
    final navigationBar = _cupertinoNavigationBar(context);
    final hasTabs =
        bottomBar != null &&
        (bottomBar.items?.isNotEmpty ?? false) &&
        bottomBar.selectedIndex != null &&
        bottomBar.onTap != null;
    // The native tab bar floats over the body on iOS 26+; any other tab bar
    // sits below it.
    final nativeTabBar =
        hasTabs &&
        AdaptiveCapabilities.liquidGlass &&
        bottomBar.useNativeBottomBar;

    Widget body = _MaterialAncestor(
      child: widget.body ?? const SizedBox.shrink(),
    );
    if (navigationBar is AdaptiveNavigationSearchBar) {
      // The native search header reports how far it reaches. A plain scroll
      // view in the body links to it and starts below it, as on the native
      // bar path.
      final link = navigationBar.controller.scrollController;
      body = PrimaryScrollController(
        controller: link,
        child: ValueListenableBuilder<double?>(
          valueListenable: link.contentTopInset,
          child: body,
          builder: (context, inset, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(
                  top: inset ?? media.padding.top,
                ),
              ),
              child: child!,
            );
          },
        ),
      );
    }
    if (hasTabs) {
      final tabBar = _cupertinoTabBar(context, bottomBar, native: nativeTabBar);
      body = nativeTabBar
          ? NativeBottomBarLayout(
              body: body,
              bottomBar: _tabsInTrailingBar(context) ? null : tabBar,
              barVisible: !widget.tabBarHidden,
            )
          : Column(
              children: [
                Expanded(child: body),
                tabBar,
              ],
            );
    }
    if (widget.floatingActionButton != null) {
      body = Stack(
        children: [
          body,
          Positioned(
            right: 16,
            // Clear of a tab bar laid out below the body.
            bottom: hasTabs && !nativeTabBar ? 96 : 16,
            child: widget.floatingActionButton!,
          ),
        ],
      );
    }
    body = DefaultTextStyle.merge(
      style: TextStyle(
        color: MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? CupertinoColors.white
            : CupertinoColors.black,
        fontSize: 17,
      ),
      child: body,
    );

    // The native tab bar is a bottom-aligned overlay: let the keyboard cover
    // it instead of pushing it up.
    Widget page() => _wrapWithDrawerIfNeeded(
      CupertinoPageScaffold(
        backgroundColor: widget.backgroundColor,
        resizeToAvoidBottomInset:
            widget.resizeToAvoidBottomInset ?? !nativeTabBar,
        navigationBar: navigationBar,
        child: body,
      ),
    );

    // Search focus changes both the native header and the content inset.
    // Rebuild the scaffold itself: rebuilding only the bar leaves the old gap.
    if (navigationBar is AdaptiveNavigationSearchBar) {
      return ListenableBuilder(
        listenable: navigationBar.controller,
        builder: (context, _) => page(),
      );
    }
    return page();
  }

  /// The app's own bar. This path only runs when the app bar brings one, or
  /// when there is no app bar at all.
  ObstructingPreferredSizeWidget? _cupertinoNavigationBar(
    BuildContext context,
  ) => _appBar?.cupertinoNavigationBar as ObstructingPreferredSizeWidget?;

  /// The native tab bar when [native], otherwise the app's own
  /// `CupertinoTabBar` or one built from the destinations.
  Widget _cupertinoTabBar(
    BuildContext context,
    AdaptiveBottomNavigationBar bar, {
    required bool native,
  }) {
    if (native) {
      return NativeTabBar(
        destinations: bar.items!,
        selectedIndex: bar.selectedIndex!,
        onTap: bar.onTap!,
        tint: bar.selectedItemColor ?? CupertinoTheme.of(context).primaryColor,
        unselectedItemTint: bar.unselectedItemColor,
        hidden: widget.tabBarHidden,
      );
    }
    if (bar.cupertinoTabBar != null) return bar.cupertinoTabBar!;
    return CupertinoTabBar(
      currentIndex: bar.selectedIndex!,
      onTap: bar.onTap!,
      activeColor: bar.selectedItemColor,
      items: [
        for (final destination in bar.items!)
          BottomNavigationBarItem(
            icon: destination.wrapIfBadged(
              _buildNavigationIconWidget(
                rawIcon: destination.icon,
                color: bar.unselectedItemColor,
              ),
            ),
            activeIcon: destination.wrapIfBadged(
              _buildNavigationIconWidget(
                rawIcon: destination.selectedIcon ?? destination.icon,
              ),
            ),
            label: destination.label,
          ),
      ],
    );
  }
}
