import 'package:flutter/cupertino.dart';
import '../app_bar/adaptive_app_bar_action.dart';
import 'adaptive_scaffold.dart';
import '../tab_bar/ios26_native_tab_bar.dart';
import 'native_bottom_bar_layout.dart';
import '../app_bar/ios26_native_toolbar.dart';

/// Legacy Native iOS 26 scaffold with UITabBar (platform view based)
/// This is the same as IOS26Scaffold but kept as a separate class for reference
/// For app-level native search tab bar, use IOS26NativeSearchTabBar directly
class IOS26ScaffoldLegacy extends StatefulWidget {
  const IOS26ScaffoldLegacy({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.title,
    this.actions,
    this.leading,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.enableBlur = true,
    this.enableToolbarGradient = true,
    this.tabBarHidden = false,
    required this.children,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String? title;
  final List<AdaptiveAppBarAction>? actions;
  final Widget? leading;
  final TabBarMinimizeBehavior minimizeBehavior;
  final bool enableBlur;

  /// @deprecated No longer used. iOS 26+ uses native scroll edge effects.
  /// This parameter is kept for backwards compatibility but has no effect.
  final bool enableToolbarGradient;
  final bool tabBarHidden;
  final List<Widget> children;

  @override
  State<IOS26ScaffoldLegacy> createState() => _IOS26ScaffoldLegacyState();
}

class _IOS26ScaffoldLegacyState extends State<IOS26ScaffoldLegacy> {
  @override
  Widget build(BuildContext context) {
    // Auto back button logic
    String? leadingText;
    VoidCallback? leadingCallback;

    if (widget.leading == null &&
        widget.destinations.isEmpty &&
        Navigator.of(context).canPop()) {
      leadingText = ''; // Empty string = native chevron
      leadingCallback = () => Navigator.of(context).pop();
    }

    // Wrap everything in Material to ensure proper layer ordering during transitions
    return CupertinoPageScaffold(
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => false,
        child: Stack(
          children: [
            NativeBottomBarLayout(
              barVisible: !widget.tabBarHidden,
              body: IndexedStack(
                index: widget.selectedIndex,
                sizing: StackFit.expand,
                children: widget.children,
              ),
              bottomBar: widget.destinations.isEmpty
                  ? null
                  : IOS26NativeTabBar(
                      destinations: widget.destinations,
                      selectedIndex: widget.selectedIndex,
                      onTap: widget.onDestinationSelected,
                      tint: CupertinoTheme.of(context).primaryColor,
                      minimizeBehavior: TabBarMinimizeBehavior.never,
                      hidden: widget.tabBarHidden,
                    ),
            ),
            // Top toolbar - iOS 26 Liquid Glass style
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IOS26NativeToolbar(
                title: widget.title,
                leadingText: leadingText,
                actions: widget.actions,
                onLeadingTap: leadingCallback,
                onActionTap: (index) {
                  // Call the appropriate action callback
                  if (widget.actions != null &&
                      index >= 0 &&
                      index < widget.actions!.length) {
                    widget.actions![index].onPressed();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
