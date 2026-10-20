import 'package:flutter/widgets.dart';
import 'adaptive_navigation_scroll_controller.dart';

/// A list whose safe-area spacing scrolls with its content.
///
/// Use under AdaptiveScaffold's overlaid native navigation bar. Unlike wrapping
/// ListView in SafeArea, the viewport covers the full page, so content can pass
/// behind the glass bar instead of clipping at its lower edge. The scaffold's
/// MediaQuery includes the measured native navigation and tab-bar insets.
/// No extra bottom spacer is needed to scroll the last item above the tab bar.
class AdaptiveListView extends StatelessWidget {
  const AdaptiveListView({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    final navigation = controller;
    if (navigation is AdaptiveNavigationScrollController) {
      return ValueListenableBuilder<double?>(
        valueListenable: navigation.contentTopInset,
        builder: (context, bottom, _) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: bottom ?? mq.padding.top),
            ),
            child: _buildList(context, navigation),
          );
        },
      );
    }
    return _buildList(context, null);
  }

  Widget _buildList(
    BuildContext context,
    AdaptiveNavigationScrollController? navigation,
  ) {
    final list = CustomScrollView(
      controller: controller,
      // Keep the platform's short-list bounce when an explicit navigation
      // controller disables Flutter's implicit primary-scroll physics.
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: keyboardDismissBehavior,
      slivers: [
        SliverSafeArea(
          sliver: SliverPadding(
            padding: padding,
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ),
      ],
    );
    return list;
  }
}
