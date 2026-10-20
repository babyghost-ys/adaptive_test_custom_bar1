import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../style/sf_symbol.dart';
import '../widgets/adaptive_navigation_scroll_controller.dart';
import '../widgets/adaptive_app_bar_action.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/ios26/ios26_native_toolbar.dart';
import 'duo_vertical_bar.dart';
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
    this.pageScrollController,
    this.largeTitle = false,
    this.titleOverlay,
    this.customLeading,
    this.impliesBack = false,
    this.actions = const <AdaptiveAppBarAction>[],
    this.tint,
    this.navigationBarColor,
    this.navigator,
  });

  /// No page owns the chrome, the page has no toolbar, or it draws a
  /// non-native bar of its own: nothing to show.
  ///
  /// [titleOnly] selects Duo presentation. UIKit renders its title and
  /// navigation actions together, including the system vertical bar.
  factory TopToolbarContent.of(ToolbarEntry? entry, {bool titleOnly = false}) {
    final appBar = entry?.appBar;
    if (entry == null || appBar == null || !appBar.useNativeToolbar) {
      return const TopToolbarContent();
    }
    return TopToolbarContent(
      title: appBar.title,
      scrollController:
          (!titleOnly || defaultTargetPlatform == TargetPlatform.iOS) &&
              entry.titleOverlay == null
          ? appBar.scrollController
          : null,
      pageScrollController: appBar.scrollController,
      largeTitle: appBar.largeTitle,
      titleOverlay: entry.titleOverlay,
      customLeading: titleOnly ? null : appBar.leading,
      impliesBack:
          (!titleOnly || defaultTargetPlatform == TargetPlatform.iOS) &&
          entry.impliesBackButton,
      actions: titleOnly && defaultTargetPlatform != TargetPlatform.iOS
          ? const <AdaptiveAppBarAction>[]
          : appBar.actions ?? const <AdaptiveAppBarAction>[],
      tint: appBar.tintColor,
      navigationBarColor: appBar.navigationBarColor,
      navigator: entry.navigator,
    );
  }

  final String? title;
  final bool largeTitle;
  final AdaptiveNavigationScrollController? scrollController;

  /// The page's scroll controller whether or not a native bar follows it.
  /// The iPhone Duo title band shows its backdrop once this scrolls.
  final AdaptiveNavigationScrollController? pageScrollController;

  /// A Flutter-drawn title (custom widget, or title with subtitle). The
  /// native title is left empty while one is shown.
  final Widget? titleOverlay;
  final Widget? customLeading;
  final bool impliesBack;
  final List<AdaptiveAppBarAction> actions;
  final Color? tint;
  final Color? navigationBarColor;
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
/// On iOS these layers contain channel anchors, while UIKit owns the real
/// navigation items, their content controllers and managed route transitions.
/// Managed route ownership changes immediately so the incoming native item is
/// ready before UIKit starts its animation. Non-iOS fallback chrome and
/// unmanaged Flutter routes retain the blending supplied by [ToolbarBlend].
class HostedTopToolbar extends StatefulWidget {
  const HostedTopToolbar({
    super.key,
    required this.blend,
    this.titleOnly = false,
  });

  final ToolbarBlend blend;

  /// True on iPhone Duo: use a native full-window navigation controller.
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
    // Folding or unfolding an iPhone Duo switches between the title-only
    // and the full toolbar. Layers cached in one mode are keyed and built
    // for that mode, and would otherwise resurface under another page's key.
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
        child: _build(context, child),
      ),
    );
  }

  Widget _build(BuildContext context, Widget? _) {
    if (titleOnly && defaultTargetPlatform != TargetPlatform.iOS) {
      return DuoTitleBand.builder(
        builder: (context, _) => _buildChrome(context),
      );
    }
    return _buildChrome(context);
  }

  Widget _buildChrome(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
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
          (defaultTargetPlatform != TargetPlatform.iOS ||
              blend.registry.byId(key.$1) == null),
    );
    final upperOwns = blend.upperOwns;
    final hasScrollLinkedBar =
        upper.scrollController != null || lower.scrollController != null;
    final upperOpacity = blend.upperOpacity;
    final lowerOpacity = blend.lowerOpacity;

    final upperBack = upper.impliesBack && upper.customLeading == null;
    final lowerBack = lower.impliesBack && lower.customLeading == null;
    final Animation<double>? backOpacity = switch ((upperBack, lowerBack)) {
      (true, true) => kAlwaysCompleteAnimation,
      (true, false) => upperOpacity,
      (false, true) => lowerOpacity,
      (false, false) => null,
    };

    // The bar's backdrop belongs to the chrome, not to a page: it only fades
    // when the toolbar as a whole comes or goes.
    final Animation<double> backdropOpacity = switch ((
      upper.isEmpty,
      lower.isEmpty,
    )) {
      (false, false) => kAlwaysCompleteAnimation,
      (false, true) =>
        blend.isBlending && lowerEntry != null
            ? upperOpacity
            : kAlwaysCompleteAnimation,
      (true, false) => lowerOpacity,
      (true, true) => kAlwaysDismissedAnimation,
    };

    final controllers = [
      upper.scrollController,
      lower.scrollController,
    ].nonNulls.toList();
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final controller in controllers) ...[
          controller.navigationBarBottom,
        ],
      ]),
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: titleOnly
              ? defaultTargetPlatform == TargetPlatform.iOS
                    ? MediaQuery.sizeOf(context).height
                    : DuoTitleBand.of(context).contentTop
              : hasScrollLinkedBar
              ? controllers
                    .map(
                      (c) =>
                          c.navigationBarBottom.value ??
                          MediaQuery.sizeOf(context).height,
                    )
                    .reduce((a, b) => a > b ? a : b)
              : kHostedToolbarHeight + topInset,
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
                  FadeTransition(
                    key: const ValueKey<String>('adaptive_toolbar_backdrop'),
                    opacity: backdropOpacity,
                    child: titleOnly
                        ? const SizedBox.shrink()
                        : hasScrollLinkedBar
                        ? const SizedBox.shrink()
                        : defaultTargetPlatform == TargetPlatform.iOS
                        ? const SizedBox.shrink()
                        : const _Backdrop(),
                  ),
                  for (final page in _pages.entries)
                    _layer(
                      key: ValueKey(page.key),
                      content: page.value,
                      opacity: page.key == upperKey
                          ? upperOpacity
                          : page.key == lowerKey
                          ? lowerOpacity
                          : kAlwaysDismissedAnimation,
                      interactive:
                          page.key == (upperOwns ? upperKey : lowerKey),
                    ),
                  if (backOpacity != null &&
                      !titleOnly &&
                      defaultTargetPlatform != TargetPlatform.iOS)
                    Positioned(
                      key: const ValueKey<String>('adaptive_toolbar_back'),
                      left: 16 + (_isWindowed(context) ? 62 : 0),
                      top: topInset,
                      child: FadeTransition(
                        key: const ValueKey<String>(
                          'adaptive_toolbar_back_fade',
                        ),
                        opacity: backOpacity,
                        alwaysIncludeSemantics: true,
                        child: ExcludeSemantics(
                          // Fading out with the page that is leaving.
                          excluding: !(upperOwns ? upperBack : lowerBack),
                          child: _BackButton(
                            navigator: (upperOwns ? upper : lower).navigator,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One page’s native bar, including its native back action on iOS.
  /// The non-iOS fallback draws a shared back button above these layers.
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
          child: titleOnly && defaultTargetPlatform != TargetPlatform.iOS
              ? DuoToolbarTitle(
                  title: content.title,
                  titleWidget: content.titleOverlay,
                  large: content.largeTitle,
                )
              : defaultTargetPlatform == TargetPlatform.iOS
              ? Align(
                  alignment: Alignment.topCenter,
                  child: IOS26NativeToolbar(
                    // A native navigation controller must never be retargeted
                    // to a different scroll view while UIKit is collapsing it.
                    key: ValueKey(content.scrollController),
                    scrollController: content.scrollController,
                    // Behind a sheet or dialog the native bar stays on
                    // screen, dimmed and inert, as UIKit leaves it.
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
                    showsGradient: false,
                    onActionTap: (index) {
                      if (index >= 0 && index < content.actions.length) {
                        content.actions[index].onPressed();
                      }
                    },
                  ),
                )
              : _FallbackBar(content: content),
        ),
      ),
    );
  }

  /// Whether the app runs in a window smaller than the display (iPadOS),
  /// where the system's window controls take the bar's leading corner.
  static bool _isWindowed(BuildContext context) {
    final display = View.of(context).display.size;
    final viewport =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return (display.longestSide - viewport.longestSide).abs() > 1 ||
        (display.shortestSide - viewport.shortestSide).abs() > 1;
  }
}

/// The soft gradient that keeps the bar readable over scrolling content.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return IgnorePointer(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            // Runs on below the bar for a smooth fade into the content.
            height:
                MediaQuery.viewPaddingOf(context).top +
                kHostedToolbarHeight +
                30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 0.7, 1.0],
                colors: [
                  base.withValues(alpha: 0.85),
                  base.withValues(alpha: 0.6),
                  base.withValues(alpha: 0.2),
                  base.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back for the page that owns the chrome, performed on that page's own
/// navigator so nested navigators (tabs, shell routes) pop the right stack.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.navigator});

  final NavigatorState? navigator;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kHostedToolbarHeight,
      width: kHostedToolbarHeight,
      child: AdaptiveButton.sfSymbol(
        onPressed: () => navigator?.maybePop(),
        sfSymbol: const SFSymbol('chevron.left', size: 20),
        size: AdaptiveButtonSize.large,
        useSmoothRectangleBorder: false,
      ),
    );
  }
}

/// Stand-in for the native bar where there is no UIKit (widget tests).
class _FallbackBar extends StatelessWidget {
  const _FallbackBar({required this.content});

  final TopToolbarContent content;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: kHostedToolbarHeight,
        child: Row(
          children: [
            if (content.customLeading != null) content.customLeading!,
            Expanded(
              child: Center(
                child:
                    content.titleOverlay ??
                    (content.title != null ? Text(content.title!) : null),
              ),
            ),
            for (final action in content.actions)
              Builder(
                builder: (context) => CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      action.press(context, navigator: content.navigator),
                  child: action.icon != null
                      ? Icon(action.icon)
                      : Text(action.title ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
