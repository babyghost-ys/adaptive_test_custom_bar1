import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'adaptive_drawer.dart';

/// A [ChangeNotifier] others can ask to notify, for [DrawerCoverScope].
class DrawerCoverPulse extends ChangeNotifier {
  void ping() => notifyListeners();

  /// The panel's colour, when the drawer says what it is. An
  /// [AdaptiveDrawer.custom] anywhere in the drawer sets it as it builds.
  /// Null falls back to the theme's drawer colour.
  Color? panelColor;
}

/// Tells the drawer it is on a native page: its panel lies beneath the
/// native bars, so UIKit cuts them open where the panel is. The scaffold
/// puts it around whatever drawer it is given, wrapped in the app's own
/// widgets or not, together with a [DrawerCoverReporter] that follows the
/// panel.
class DrawerCoverScope extends InheritedWidget {
  const DrawerCoverScope({
    super.key,
    required this.pulse,
    required this.isOpen,
    required super.child,
  });

  /// Pinged whenever the drawer may have started to move.
  final DrawerCoverPulse pulse;

  /// Whether the drawer is open or opening, as its owner last heard.
  final bool Function() isOpen;

  static DrawerCoverScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DrawerCoverScope>();

  @override
  bool updateShouldNotify(DrawerCoverScope oldWidget) =>
      pulse != oldWidget.pulse;
}

/// Follows its own left edge, which is the drawer panel's, frame by frame
/// while it moves, and has UIKit cut the bars open there.
///
/// It wraps the drawer itself, so it is laid out at the panel's size.
class DrawerCoverReporter extends StatefulWidget {
  const DrawerCoverReporter({
    super.key,
    required this.pulse,
    required this.isOpen,
    required this.child,
  });

  /// Pinged whenever the drawer may have started to move.
  final DrawerCoverPulse pulse;

  /// Whether the drawer is open or opening, as its owner last heard.
  final bool Function() isOpen;
  final Widget child;

  @override
  State<DrawerCoverReporter> createState() => _DrawerCoverReporterState();
}

class _DrawerCoverReporterState extends State<DrawerCoverReporter> {
  static const _settledFrames = 8;

  bool _looping = false;
  bool _covering = false;
  double? _lastX;
  double? _lastWidth;
  int _stable = 0;

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_start);
    // The panel is only built once it starts to open, after the callback.
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A rotation can change the panel's width without moving its edge.
    MediaQuery.sizeOf(context);
    _start();
  }

  @override
  void didUpdateWidget(DrawerCoverReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) {
      oldWidget.pulse.removeListener(_start);
      widget.pulse.addListener(_start);
    }
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_start);
    if (_covering) AdaptiveDrawer.clearCover();
    super.dispose();
  }

  void _start() {
    _stable = 0;
    if (_looping) return;
    _looping = true;
    _next();
  }

  void _next() {
    WidgetsBinding.instance.addPostFrameCallback(_tick);
    SchedulerBinding.instance.scheduleFrame();
  }

  void _tick(Duration _) {
    final box = mounted ? context.findRenderObject() : null;
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      _looping = false;
      return;
    }
    final x = box.localToGlobal(Offset.zero).dx;
    final width = box.size.width;
    final open = widget.isOpen();
    // Closing from a tap that also pushes a page: once the push covers this
    // page its animations pause, so the panel may never get out of sight.
    final covered = ModalRoute.isCurrentOf(context) == false;
    if ((x <= -width + 0.5 || covered) && !open) {
      if (_covering) AdaptiveDrawer.clearCover();
      _covering = false;
      _lastX = null;
      _lastWidth = null;
      _looping = false;
      return;
    }
    if (x != _lastX || width != _lastWidth) {
      _lastX = x;
      _lastWidth = width;
      _stable = 0;
      _covering = true;
      AdaptiveDrawer.reportCover(
        x: x,
        width: width,
        color:
            widget.pulse.panelColor ??
            AdaptiveDrawer.defaultBackground(Theme.of(context)),
      );
    } else {
      _stable++;
    }
    if (_stable >= _settledFrames && open) {
      _looping = false;
      return;
    }
    _next();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
