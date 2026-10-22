import '../../core/theme/adaptive_theme.dart';
import '../../core/adaptive_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../devices/duo/system_vertical_bar.dart';
import '../../devices/duo/duo_layout.dart';
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
    @visibleForTesting this.debugVerticalBarEdge,
  });

  /// The navigator (or whatever the app's `builder` receives).
  final Widget child;

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

  @override
  void initState() {
    super.initState();
    _blend = ToolbarBlend(registry: _registry, vsync: this);
    if (widget.debugVerticalBarEdge == null &&
        AdaptiveCapabilities.systemVerticalBarEdge) {
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
    _blend.dispose();
    _registry.dispose();
    super.dispose();
  }

  /// The app's bar colour where it asks for the Duo strip to be filled.
  Color? _stripColor(BuildContext context) {
    final bar = AdaptiveTheme.of(context).barStyle;
    return bar.fillsDuoStrip ? bar.color : null;
  }

  @override
  Widget build(BuildContext context) {
    // The fixed chrome only exists where pages use the native iOS 26
    // toolbar; elsewhere pages keep their own Cupertino / Material bars.
    final hostsToolbar = AdaptiveStyle.of(context) == AdaptiveStyle.native;
    final edge =
        widget.debugVerticalBarEdge ??
        _edge?.value ??
        SystemVerticalBarEdge.unknown;
    // Resolved once: the bar, the title and the pages all read this decision.
    final pose = hostsToolbar
        ? DuoLayout.resolvePose(MediaQuery.viewPaddingOf(context), edge)
        : null;

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
              // Always present, so the toolbar after it keeps its position in
              // the element tree as the pose changes.
              Positioned.fill(
                child: _BarStrip(pose: pose, color: _stripColor(context)),
              ),
              if (hostsToolbar)
                HostedTopToolbar(blend: _blend, titleOnly: pose != null),
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

/// Fills the strip the system reserves for the iPhone Duo vertical bar with
/// the app's bar colour, so the bar reads as one band down that edge. Draws
/// nothing without a pose or a colour, and never takes a touch.
class _BarStrip extends StatelessWidget {
  const _BarStrip({required this.pose, required this.color});

  final DuoPose? pose;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pose = this.pose;
    final color = this.color;
    if (pose == null || color == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: pose.onLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: SizedBox(
          width: pose.stripWidth,
          height: double.infinity,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
