import 'package:flutter/widgets.dart';

/// Connects a Flutter scroll view to a native navigation bar.
/// Use one controller per page/tab, and dispose it with that page.
class AdaptiveNavigationScrollController extends ScrollController {
  AdaptiveNavigationScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// UIKit's automatic content inset at the page's resting position.
  final ValueNotifier<double?> contentTopInset = ValueNotifier<double?>(null);

  /// Current native bar boundary, including large-title expansion and bounce.
  final ValueNotifier<double?> navigationBarBottom = ValueNotifier<double?>(
    null,
  );

  /// Retained for source compatibility. Content now paints across the full
  /// viewport; UIKit owns its navigation background and scroll-edge effect.
  @Deprecated(
    'UIKit owns the scroll edge; do not clip content at a bar midpoint.',
  )
  final ValueNotifier<double?> compactUnderlapTop = ValueNotifier<double?>(
    null,
  );

  bool _disposed = false;

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    // PageStorage restores a position during layout without a scroll event.
    // Tell a retained native bar about that restored position after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && positions.contains(position)) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    contentTopInset.dispose();
    navigationBarBottom.dispose();
    compactUnderlapTop.dispose();
    super.dispose();
  }
}

/// Kept for source compatibility. AdaptiveListView now applies the complete
/// native content inset, so a separate large-title spacer is unnecessary.
@Deprecated(
  'AdaptiveListView applies the native navigation inset automatically.',
)
class AdaptiveLargeTitleSpacer extends StatelessWidget {
  const AdaptiveLargeTitleSpacer({super.key, required this.controller});
  final AdaptiveNavigationScrollController controller;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
