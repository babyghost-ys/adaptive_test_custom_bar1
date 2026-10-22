part of 'adaptive_scaffold.dart';

/// The Material path: Android, and any platform or subtree that asks for
/// [AdaptiveStyle.material].
extension _MaterialScaffold on AdaptiveScaffoldState {
  Widget _buildMaterial(
    BuildContext context,
    AdaptiveBottomNavigationBar? bottomBar,
  ) {
    final hasTabs =
        bottomBar != null &&
        (bottomBar.items?.isNotEmpty ?? false) &&
        bottomBar.selectedIndex != null &&
        bottomBar.onTap != null;
    return Scaffold(
      key: _scaffoldKey,
      // A tab root shows an app bar only when it has something in it; any
      // other page keeps one for its automatic back button.
      appBar: _materialAppBar(context, requireContent: hasTabs),
      body: widget.body ?? const SizedBox.shrink(),
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      bottomNavigationBar: hasTabs
          ? _materialNavigationBar(context, bottomBar)
          : null,
      floatingActionButton: widget.floatingActionButton,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar ?? false,
      extendBody: widget.extendBody ?? false,
      backgroundColor: widget.backgroundColor,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      drawerScrimColor: widget.drawerScrimColor,
      onDrawerChanged: widget.onDrawerChanged,
      onEndDrawerChanged: widget.onEndDrawerChanged,
      drawerEnableOpenDragGesture: widget.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: widget.endDrawerEnableOpenDragGesture,
    );
  }

  PreferredSizeWidget? _materialAppBar(
    BuildContext context, {
    required bool requireContent,
  }) {
    final appBar = _appBar;
    if (appBar == null) return null;
    if (appBar.appBar != null) return appBar.appBar;
    final actions = appBar.actions ?? const <AdaptiveAppBarAction>[];
    if (requireContent &&
        appBar.title == null &&
        appBar.titleWidget == null &&
        actions.isEmpty &&
        appBar.leading == null) {
      return null;
    }
    // As in the native toolbar, actions up to the last flexible spacer sit
    // on the leading side; they replace the implied drawer or back button.
    final split =
        actions.lastIndexWhere(
          (action) => action.spacerAfter == ToolbarSpacerType.flexible,
        ) +
        1;
    final leadingActions = appBar.leading == null
        ? actions.sublist(0, split)
        : const <AdaptiveAppBarAction>[];
    final trailingActions = actions.sublist(leadingActions.length);
    Widget button(AdaptiveAppBarAction action) => Builder(
      builder: (context) => action.title != null
          ? TextButton(
              onPressed: () => action.press(context),
              child: Text(action.title!),
            )
          : IconButton(
              icon: action.wrapWithBadge(
                action.icon?.build() ?? const Icon(Icons.circle),
              ),
              tooltip: action.effectiveLabel,
              onPressed: () => action.press(context),
            ),
    );
    return AppBar(
      backgroundColor: appBar.navigationBarColor,
      foregroundColor: appBar.tintColor,
      title: _buildAppBarTitle(
        crossAxisAlignment: CrossAxisAlignment.start,
        subtitleFontSize: 13,
        subtitleColor: Theme.of(
          context,
        ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
      ),
      centerTitle: appBar.titleWidget != null,
      leading: leadingActions.isEmpty
          ? appBar.leading
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final action in leadingActions) button(action)],
            ),
      leadingWidth: leadingActions.length > 1
          ? kMinInteractiveDimension * leadingActions.length +
                NavigationToolbar.kMiddleSpacing
          : null,
      actions: [for (final action in trailingActions) button(action)],
    );
  }

  /// The app's own bottom bar, or a Material [NavigationBar] built from the
  /// destinations.
  Widget _materialNavigationBar(
    BuildContext context,
    AdaptiveBottomNavigationBar bar,
  ) {
    if (bar.bottomNavigationBar != null) return bar.bottomNavigationBar!;
    final indicator = bar.selectedItemColor;
    final indicatorBackground = indicator == null
        ? null
        : Color.alphaBlend(
            indicator,
            NavigationBarTheme.of(context).backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainer,
          );
    // A custom indicator cannot use Material's default foreground, which
    // is paired with secondaryContainer rather than the supplied color.
    final indicatorForeground = indicatorBackground == null
        ? null
        : indicatorBackground.computeLuminance() > 0.179
        ? Colors.black
        : Colors.white;
    return NavigationBar(
      selectedIndex: bar.selectedIndex!,
      onDestinationSelected: bar.onTap!,
      indicatorColor: indicator,
      destinations: [
        for (final destination in bar.items!)
          NavigationDestination(
            icon: destination.wrapIfBadged(
              _buildNavigationIconWidget(rawIcon: destination.icon),
            ),
            selectedIcon: destination.wrapIfBadged(
              indicatorForeground == null
                  ? _buildNavigationIconWidget(
                      rawIcon: destination.selectedIcon ?? destination.icon,
                    )
                  : IconTheme.merge(
                      data: IconThemeData(color: indicatorForeground),
                      child: _buildNavigationIconWidget(
                        rawIcon: destination.selectedIcon ?? destination.icon,
                      ),
                    ),
            ),
            label: destination.label,
          ),
      ],
    );
  }
}
