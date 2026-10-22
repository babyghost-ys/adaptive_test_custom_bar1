part of 'adaptive_scaffold.dart';

/// The iOS path for an app bar that opts out of the native toolbar
/// (`useNativeToolbar: false`): a Flutter `CupertinoNavigationBar`, the app's
/// own bar, or an `AdaptiveNavigationSearchBar`.
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

  /// The app's own bar, or one built from the app bar when it has anything
  /// to show (a back button counts).
  ObstructingPreferredSizeWidget? _cupertinoNavigationBar(
    BuildContext context,
  ) {
    final appBar = _appBar;
    if (appBar == null) return null;
    if (appBar.cupertinoNavigationBar != null) {
      return appBar.cupertinoNavigationBar as ObstructingPreferredSizeWidget;
    }
    final actions = appBar.actions ?? const <AdaptiveAppBarAction>[];
    final hasContent =
        appBar.title != null ||
        appBar.titleWidget != null ||
        actions.isNotEmpty ||
        appBar.leading != null ||
        (Navigator.maybeOf(context)?.canPop() ?? false);
    if (!hasContent) return null;
    return CupertinoNavigationBar(
      backgroundColor: appBar.navigationBarColor,
      middle: _buildAppBarTitle(),
      leading: appBar.leading,
      trailing: actions.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  Builder(
                    builder: (context) => CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => action.press(context),
                      child: action.wrapWithBadge(
                        action.title != null
                            ? Text(action.title!)
                            : action.iconWidget ??
                                  Icon(action.icon ?? CupertinoIcons.circle),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// The native tab bar when [native], otherwise the app's own
  /// `CupertinoTabBar` or one built from the destinations.
  Widget _cupertinoTabBar(
    BuildContext context,
    AdaptiveBottomNavigationBar bar, {
    required bool native,
  }) {
    if (native) {
      return IOS26NativeTabBar(
        destinations: bar.items!,
        selectedIndex: bar.selectedIndex!,
        onTap: bar.onTap!,
        tint: bar.selectedItemColor ?? CupertinoTheme.of(context).primaryColor,
        unselectedItemTint: bar.unselectedItemColor,
        minimizeBehavior: TabBarMinimizeBehavior.never,
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
                platform: TargetPlatform.iOS,
              ),
            ),
            activeIcon: destination.wrapIfBadged(
              _buildNavigationIconWidget(
                rawIcon: destination.selectedIcon ?? destination.icon,
                platform: TargetPlatform.iOS,
              ),
            ),
            label: destination.label,
          ),
      ],
    );
  }
}
