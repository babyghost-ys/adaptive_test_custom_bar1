import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../devices/duo/reserved_region.dart';

import '../../core/platform_info.dart';
import '../../devices/duo/system_vertical_bar.dart';
import '../../devices/duo/duo_vertical_bar.dart';
import '../../devices/duo/hosted_duo_bar.dart';
import 'hosted_top_toolbar.dart';
import 'toolbar_blend.dart';
import 'toolbar_chrome_scope.dart';
import 'toolbar_registry.dart';

/// Fixed toolbar chrome that lives above the navigator.
///
/// Install it once around the navigator (an app `builder` is the right
/// place; [AdaptiveApp] does this for you). It owns a [ToolbarRegistry] that
/// every [AdaptiveScaffold] below publishes its app bar to, and it draws one
/// persistent bar whose items change as routes come and go. Because the bar
/// is not part of any route it stays put during page transitions, exactly
/// like the system bars on iOS 26 and the vertical bar on the iPhone Duo
/// inner display.
///
/// Works with any router: it depends on nothing but the widget tree.
class AdaptiveToolbarHost extends StatefulWidget {
  const AdaptiveToolbarHost({
    super.key,
    required this.child,
    @visibleForTesting this.debugRegions,
    @visibleForTesting this.debugVerticalBarEdge,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

  /// Replaces the platform's reserved regions and the
  /// iOS 26 check, so the chrome can be exercised in widget tests anywhere.
  @visibleForTesting
  final List<ReservedRegion>? debugRegions;

  /// Replaces the system's vertical bar edge in widget tests, where the
  /// platform channel it comes from does not exist.
  @visibleForTesting
  final SystemVerticalBarEdge? debugVerticalBarEdge;

  @override
  State<AdaptiveToolbarHost> createState() => _AdaptiveToolbarHostState();
}

class _AdaptiveToolbarHostState extends State<AdaptiveToolbarHost>
    with TickerProviderStateMixin {
  final ToolbarRegistry _registry = ToolbarRegistry();
  late final ToolbarBlend _blend;

  /// The system's vertical bar edge; null wherever the chrome is never drawn
  /// and in tests, where no platform channel answers.
  ValueListenable<SystemVerticalBarEdge>? _edge;

  /// What the debug log last reported, to print only the changes.
  SystemVerticalBarEdge _loggedEdge = SystemVerticalBarEdge.unknown;
  DuoPose? _loggedPose;

  @override
  void initState() {
    super.initState();
    _blend = ToolbarBlend(registry: _registry, vsync: this);
    // Reserved regions supply camera clearance for the bar.
    if (widget.debugRegions == null && PlatformInfo.isIOS26OrHigher()) {
      SystemVerticalBar.regions.addListener(_onEdgeChanged);
      // The side the bar belongs on comes from the system, not from insets:
      // the leading Split View pane has none to read.
      _edge = SystemVerticalBar.edge..addListener(_onEdgeChanged);
    }
  }

  void _onEdgeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _edge?.removeListener(_onEdgeChanged);
    if (_edge != null) {
      SystemVerticalBar.regions.removeListener(_onEdgeChanged);
    }
    _blend.dispose();
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final regions = widget.debugRegions ?? SystemVerticalBar.currentRegions;
    // The fixed chrome only exists where pages use the native iOS 26
    // toolbar; elsewhere pages keep their own Cupertino / Material bars.
    final hostsToolbar = widget.debugRegions != null || PlatformInfo.isIOS;
    final edge =
        widget.debugVerticalBarEdge ??
        _edge?.value ??
        SystemVerticalBarEdge.unknown;
    // Resolved once: the bar, the title and the pages all read this decision.
    final pose = hostsToolbar
        ? DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), edge)
        : null;
    assert(() {
      // Pose bugs only reproduce on a Duo; this makes a report actionable.
      if (edge != _loggedEdge || pose != _loggedPose) {
        _loggedEdge = edge;
        _loggedPose = pose;
        debugPrint(
          'AdaptiveToolbarHost: Duo pose ${pose ?? 'none'} '
          '(edge: ${edge.name})',
        );
      }
      return true;
    }());

    return ToolbarRegistryScope(
      registry: _registry,
      child: ToolbarChromeScope(
        hostsToolbar: hostsToolbar,
        hostsDuoControls: pose != null,
        child: DuoPoseScope(
          pose: pose,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always the first child at a stable position, so toggling the
              // chrome never rebuilds the navigator from scratch. The
              // MediaQuery in it is always here too, even when it changes
              // nothing:
              // adding it only in some poses would move the navigator in the
              // element tree whenever the pose changes (moving between Split
              // View panes), and rebuild every route.
              _BarInset(pose: pose, child: widget.child),
              if (hostsToolbar)
                HostedTopToolbar(blend: _blend, titleOnly: pose != null),
              if (pose != null)
                // The bar sits on whichever edge the pose names: the right in
                // most poses, the left in the leading Split View pane.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: pose.onLeft ? 0 : null,
                  right: pose.onLeft ? null : 0,
                  width: pose.bandWidth,
                  child: HostedDuoBar(blend: _blend, regions: regions),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gives the pages the inset the system would have added for a vertical bar
/// it does not draw: in the leading Split View pane the system wants a bar
/// there but reserves no strip for it, since UIKit only insets for bars it
/// draws itself. Add that inset here, as UIKit does for a native app, so a
/// page's SafeArea and the scaffold's body inset keep clear of the bar.
///
/// Always builds a [MediaQuery], with the data unchanged when there is nothing
/// to add, and is a widget of its own so the host does not depend on the whole
/// [MediaQueryData] (every keyboard frame would rebuild the chrome).
class _BarInset extends StatelessWidget {
  const _BarInset({required this.pose, required this.child});

  final DuoPose? pose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pose = this.pose;
    return MediaQuery(
      data: pose == null || pose.reservedBySystem
          ? mq
          : mq.copyWith(
              padding: pose.addStrip(mq.padding),
              viewPadding: pose.addStrip(mq.viewPadding),
            ),
      child: child,
    );
  }
}
