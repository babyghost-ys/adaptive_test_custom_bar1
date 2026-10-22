import 'package:flutter/cupertino.dart';

import '../app_bar/adaptive_navigation_scroll_controller.dart';
import '../app_bar/adaptive_app_bar_action.dart';
import '../app_bar/ios26_native_toolbar.dart';
import 'toolbar_blend.dart';
import 'toolbar_registry.dart';

/// Height of the toolbar's content area, excluding the status bar.
const double kHostedToolbarHeight = 44.0;

/// What one page contributes to the top toolbar.
@immutable
class TopToolbarContent {
  const TopToolbarContent({
    this.title,
    this.scrollController,
    this.largeTitle = false,
    this.titleOverlay,
    this.customLeading,
    this.impliesBack = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
    this.navigationBarColor,
    this.navigationBarShadow = false,
    this.hidesNavigationButtonBackground = false,
    this.navigator,
  });

  /// No page owns the chrome, the page has no toolbar, or it draws a
  /// non-native bar of its own: nothing to show.
  ///
  /// [titleOnly] selects Duo presentation: UIKit puts the controls in the
  /// system vertical bar, so a Flutter leading widget has nowhere to go.
  factory TopToolbarContent.of(ToolbarEntry? entry, {bool titleOnly = false}) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const TopToolbarContent();
    }
    return TopToolbarContent(
      title: appBar.title,
      scrollController: entry.titleOverlay == null
          ? appBar.scrollController
          : null,
      largeTitle: appBar.largeTitle,
      titleOverlay: entry.titleOverlay,
      customLeading: titleOnly ? null : appBar.leading,
      impliesBack: entry.impliesBackButton,
      actions: appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
      navigationBarColor: appBar.navigationBarColor,
      navigationBarShadow: appBar.navigationBarShadow ?? false,
      hidesNavigationButtonBackground:
          appBar.hidesNavigationButtonBackground ?? false,
      navigator: entry.navigator,
    );
  }

  final String? title;
  final bool largeTitle;
  final AdaptiveNavigationScrollController? scrollController;

  /// A Flutter-drawn title (custom widget, or title with subtitle). The
  /// native title is left empty while one is shown.
  final Widget? titleOverlay;
  final Widget? customLeading;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;
  final Color? navigationBarColor;
  final bool navigationBarShadow;
  final bool hidesNavigationButtonBackground;
  final NavigatorState? navigator;

  bool get isEmpty =>
      title == null &&
      titleOverlay == null &&
      customLeading == null &&
      !impliesBack &&
      actions.isEmpty;
}

/// Publishes each page's navigation configuration to the native toolbar host.
///
/// Each layer is a channel anchor; UIKit owns the real navigation items,
/// their content controllers and managed route transitions. Managed route
/// ownership changes immediately so the incoming native item is ready before
/// UIKit starts its animation. Unmanaged Flutter routes keep the blending
/// supplied by [ToolbarBlend].
class HostedTopToolbar extends StatefulWidget {
  const HostedTopToolbar({
    super.key,
    required this.blend,
    this.titleOnly = false,
  });

  final ToolbarBlend blend;

  /// True on iPhone Duo: UIKit lays the bar out as the system vertical bar.
  final bool titleOnly;

  @override
  State<HostedTopToolbar> createState() => _HostedTopToolbarState();
}

class _HostedTopToolbarState extends State<HostedTopToolbar> {
  // Keep a native navigation controller for each mounted page/tab. Pushing a
  // detail or switching tabs must not recreate UIKit's collapsing title state.
  final _pages =
      <(Object, AdaptiveNavigationScrollController?), TopToolbarContent>{};
  ToolbarBlend get blend => widget.blend;
  bool get titleOnly => widget.titleOnly;

  @override
  void didUpdateWidget(HostedTopToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Folding or unfolding an iPhone Duo switches the bar's layout. Layers
    // cached in one layout would otherwise resurface under another page.
    if (oldWidget.titleOnly != widget.titleOnly) _pages.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([blend, blend.registry]),
      builder: (context, child) => Visibility(
        visible: !titleOnly || !blend.registry.nativeSearchHandoff,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: _buildChrome(context),
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    final upperEntry = blend.upper;
    final lowerEntry = blend.lower;
    final upper = TopToolbarContent.of(upperEntry, titleOnly: titleOnly);
    final lower = TopToolbarContent.of(lowerEntry, titleOnly: titleOnly);
    final upperKey = upperEntry == null
        ? null
        : (upperEntry.id, upper.scrollController);
    final lowerKey = lowerEntry == null
        ? null
        : (lowerEntry.id, lower.scrollController);
    if (upperKey != null && !upper.isEmpty) _pages[upperKey] = upper;
    if (lowerKey != null && !lower.isEmpty) _pages[lowerKey] = lower;
    if (titleOnly) {
      // Without scroll controllers in the keys, every tab of one scaffold
      // shares a key. A tab without a toolbar (the search tab) must not keep
      // showing the previous tab's title under that key.
      if (upperKey != null && upper.isEmpty) _pages.remove(upperKey);
      if (lowerKey != null && lower.isEmpty) _pages.remove(lowerKey);
    }
    _pages.removeWhere(
      (key, _) =>
          key != upperKey &&
          key != lowerKey &&
          blend.registry.byId(key.$1) == null,
    );
    final upperOwns = blend.upperOwns;
    final controllers = [
      upper.scrollController,
      lower.scrollController,
    ].nonNulls.toList();
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final controller in controllers) controller.navigationBarBottom,
      ]),
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: titleOnly || controllers.isEmpty
              ? (titleOnly
                    ? MediaQuery.sizeOf(context).height
                    : kHostedToolbarHeight +
                          MediaQuery.viewPaddingOf(context).top)
              : controllers
                    .map(
                      (c) =>
                          c.navigationBarBottom.value ??
                          MediaQuery.sizeOf(context).height,
                    )
                    .reduce((a, b) => a > b ? a : b),
          child: IgnorePointer(
            ignoring: blend.ownerIsCovered,
            child: FadeTransition(
              opacity: blend.chromeOpacity,
              // Every layer is keyed, so a page's native bar survives the start
              // and the end of a blend instead of being torn down and rebuilt.
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  for (final page in _pages.entries)
                    _layer(
                      key: ValueKey(page.key),
                      content: page.value,
                      opacity: page.key == upperKey
                          ? blend.upperOpacity
                          : page.key == lowerKey
                          ? blend.lowerOpacity
                          : kAlwaysDismissedAnimation,
                      interactive:
                          page.key == (upperOwns ? upperKey : lowerKey),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One page's native bar, including its native back action.
  Widget _layer({
    required Key key,
    required TopToolbarContent content,
    required Animation<double> opacity,
    required bool interactive,
  }) {
    // alwaysIncludeSemantics: a layer that fades to zero during a back swipe
    // must not drop its semantics and restore them when the swipe comes back;
    // doing that mid gesture trips SemanticsNode._replaceChildren with the
    // native bar inside. The layer that is not the page in front is excluded
    // explicitly instead, so a screen reader never lands on invisible items.
    return FadeTransition(
      key: key,
      opacity: opacity,
      alwaysIncludeSemantics: true,
      child: ExcludeSemantics(
        excluding: !interactive,
        child: IgnorePointer(
          ignoring: !interactive,
          child: Align(
            alignment: Alignment.topCenter,
            child: IOS26NativeToolbar(
              // A native navigation controller must never be retargeted to a
              // different scroll view while UIKit is collapsing it.
              key: ValueKey(content.scrollController),
              scrollController: content.scrollController,
              // Behind a sheet or dialog the native bar stays on screen,
              // dimmed and inert, as UIKit leaves it.
              active: interactive,
              covered: interactive && blend.ownerIsCovered,
              largeTitle: content.largeTitle,
              verticalNavigation: titleOnly,
              leadingText: content.impliesBack ? '' : null,
              onLeadingTap: () => content.navigator?.maybePop(),
              title: content.title,
              titleWidget: content.titleOverlay,
              leading: content.customLeading,
              actions: content.actions,
              tintColor: content.tint,
              navigationBarColor: content.navigationBarColor,
              navigationBarShadow: content.navigationBarShadow,
              hidesNavigationButtonBackground:
                  content.hidesNavigationButtonBackground,
              showsGradient: false,
              onActionTap: (index) {
                if (index >= 0 && index < content.actions.length) {
                  content.actions[index].onPressed();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
