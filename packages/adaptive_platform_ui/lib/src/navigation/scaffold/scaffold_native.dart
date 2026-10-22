part of 'adaptive_scaffold.dart';

/// The UIKit path: the running system's own navigation and tab bars.
extension _NativeScaffold on AdaptiveScaffoldState {
  Widget _buildNative(
    BuildContext context,
    AdaptiveBottomNavigationBar? bottomBar,
  ) {
    final appBar = _appBar;
    // The body is the app's own tab switcher (an `IndexedStack`, a
    // `StatefulNavigationShell`, `pages[index]`...), so it is mounted
    // exactly once. Earlier versions built one copy per tab, which ran
    // every page's `initState` once per destination (#76).
    final placement = BodyPlacement.resolve(
      body: widget.body,
      largeTitle: appBar?.largeTitle ?? false,
      extendBehindTop: widget.extendBodyBehindAppBar,
      extendBehindBottom: widget.extendBody,
    );
    Widget body = _MaterialAncestor(
      child:
          (placement.underTop || placement.underBottom
              ? BodyPlacement.withInsetSlivers(widget.body)
              : widget.body) ??
          const SizedBox.shrink(),
    );
    final chrome = ToolbarChromeScope.maybeOf(context);
    final navigation = _pageScrollLink;
    if (navigation != null) {
      // A plain vertical scroll view in the body attaches to this, so the
      // native bar follows it without the app wiring a controller.
      body = PrimaryScrollController(controller: navigation, child: body);
    }
    final titleOverlay = _buildIOS26TitleOverlay();
    if (_usesFixedToolbar(context) &&
        (chrome?.hostsToolbar ?? false) &&
        !(chrome?.hostsDuoControls ?? false) &&
        appBar?.title != null &&
        titleOverlay == null &&
        navigation != null) {
      // A newly selected page has no UIKit inset yet. Keep its scroll view
      // mounted (including PageStorage restoration), but do not paint or
      // expose controls at the compact-bar fallback position. The first
      // native metrics update rebuilds this and AdaptiveListView together,
      // so the first visible content already has UIKit's real inset.
      // Retained tabs already have metrics and appear immediately.
      body = ValueListenableBuilder<double?>(
        valueListenable: navigation.contentTopInset,
        child: body,
        builder: (context, inset, child) => Visibility(
          visible: inset != null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: child!,
        ),
      );
    }
    if (widget.floatingActionButton != null) {
      body = Stack(
        children: [
          body,
          // Clear of the native tab bar.
          Positioned(
            right: 16,
            bottom: 96,
            child: widget.floatingActionButton!,
          ),
        ],
      );
    }

    return _wrapWithDrawerIfNeeded(
      NativeScaffold(
        largeTitle: appBar?.largeTitle ?? false,
        scrollController: navigation,
        bottomNavigationBar: bottomBar,
        title: appBar?.title,
        actions: appBar?.actions,
        leading: appBar?.leading,
        tintColor: appBar?.tintColor,
        navigationBarColor: appBar?.navigationBarColor,
        navigationBarShadow: appBar?.navigationBarShadow ?? false,
        titleStyle: appBar?.titleStyle,
        hidesNavigationButtonBackground:
            appBar?.hidesNavigationButtonBackground ?? false,
        titleWidget: titleOverlay,
        backgroundColor: widget.backgroundColor,
        useHeroBackButton: widget.useHeroBackButton,
        useFixedToolbar: _usesFixedToolbar(context),
        tabBarHidden: widget.tabBarHidden,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        bodyPlacement: placement,
        children: [body],
      ),
    );
  }
}
