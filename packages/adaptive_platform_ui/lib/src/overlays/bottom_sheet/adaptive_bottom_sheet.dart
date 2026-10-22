import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/adaptive_style.dart';
import '../../native/sheet_platform_view_guard.dart';

/// A modal sheet that rests at a fraction of the screen height, like a
/// UIKit sheet at its medium detent.
///
/// The sheet is a Flutter route, so native controls (segmented controls,
/// switches, sliders) render inside it as platform views. Pushing it takes
/// the covered page off the top of its navigator: a native tab bar hides and
/// hosted toolbar controls dim and go inert until the sheet is dismissed.
///
/// On iOS the sheet floats inset from the screen edges with continuous
/// corners and a grabber, as iOS 26 draws a sheet at its medium detent. On
/// other platforms it is a Material modal bottom sheet with a drag handle.
///
/// Give [show] an `expandedHeightFactor` and the sheet gains a second, taller
/// detent: dragging the grabber up (or tapping it) expands the sheet, and
/// dragging it down collapses it, then dismisses it.
class AdaptiveBottomSheet {
  AdaptiveBottomSheet._();

  /// Shows [builder]'s content in a sheet [heightFactor] of the screen tall.
  ///
  /// Content taller than the sheet should scroll. The sheet rises above the
  /// keyboard while a text field in it has focus. A sheet can present
  /// another sheet from its own context: on iOS the lower sheet dims itself
  /// and the screen behind is not darkened a second time. Returns the value
  /// passed to [Navigator.pop], or null when the sheet is dragged down or
  /// the barrier is tapped.
  ///
  /// With [expandedHeightFactor] above [heightFactor] the sheet can rest at
  /// either height.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double heightFactor = 0.5,
    double? expandedHeightFactor,
    Color? backgroundColor,
    bool isDismissible = true,
  }) {
    assert(heightFactor > 0 && heightFactor <= 1);
    assert(
      expandedHeightFactor == null ||
          (expandedHeightFactor >= heightFactor && expandedHeightFactor <= 1),
    );
    switch (AdaptiveStyle.of(context)) {
      case AdaptiveStyle.material:
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: expandedHeightFactor == null,
          enableDrag: expandedHeightFactor == null,
          isDismissible: isDismissible,
          backgroundColor: backgroundColor,
          builder: (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: expandedHeightFactor == null
                ? FractionallySizedBox(
                    heightFactor: heightFactor,
                    child: Builder(builder: builder),
                  )
                : _DetentFrame(
                    heightFactor: heightFactor,
                    expandedHeightFactor: expandedHeightFactor,
                    grabberColor: Theme.of(context).colorScheme.outlineVariant,
                    builder: builder,
                  ),
          ),
        );
      case AdaptiveStyle.native:
        // Over another sheet, a second full-screen scrim would be split around
        // native controls by Flutter's platform view compositing. The lower
        // sheet dims itself instead, as UIKit dims a sheet behind a sheet.
        final nested = ModalRoute.of(context) is PopupRoute;
        return showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          isDismissible: isDismissible,
          backgroundColor: const Color(0x00000000),
          elevation: 0,
          barrierColor: nested ? const Color(0x00000000) : _scrim,
          builder: (context) => _IOSSheet(
            heightFactor: heightFactor,
            expandedHeightFactor: expandedHeightFactor,
            backgroundColor: backgroundColor,
            builder: builder,
          ),
        );
    }
  }
}

const Color _scrim = Color(0x33000000);

class _IOSSheet extends StatelessWidget {
  const _IOSSheet({
    required this.heightFactor,
    required this.expandedHeightFactor,
    required this.backgroundColor,
    required this.builder,
  });

  final double heightFactor;
  final double? expandedHeightFactor;
  final Color? backgroundColor;
  final WidgetBuilder builder;

  /// Gap between the floating sheet and the screen edges.
  static const double _inset = 8;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The sheet rides on top of the keyboard while a field in it has focus.
    final bottom =
        media.viewInsets.bottom + (media.viewPadding.bottom > 0 ? _inset : 0.0);
    final fill =
        backgroundColor ??
        CupertinoColors.systemBackground.resolveFrom(context);
    final grabber = CupertinoColors.tertiaryLabel.resolveFrom(context);
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);

    return Padding(
      padding: EdgeInsets.fromLTRB(_inset, 0, _inset, bottom),
      child: _DetentFrame(
        heightFactor: heightFactor,
        expandedHeightFactor: expandedHeightFactor ?? heightFactor,
        grabberColor: grabber,
        wrap: (child) => SheetSurface(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            // Covered by another sheet, only the fill darkens: a layer drawn
            // over the sheet's native controls would be split around them by
            // Flutter's platform view compositing.
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                end: covered ? Color.alphaBlend(_scrim, fill) : fill,
              ),
              duration: const Duration(milliseconds: 220),
              builder: (context, color, child) =>
                  ColoredBox(color: color ?? fill, child: child),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ),
        ),
        builder: builder,
      ),
    );
  }
}

/// A sheet body that rests at [heightFactor] or [expandedHeightFactor] of the
/// screen, with a grabber that drags between the two.
class _DetentFrame extends StatefulWidget {
  const _DetentFrame({
    required this.heightFactor,
    required this.expandedHeightFactor,
    required this.grabberColor,
    required this.builder,
    this.wrap,
  });

  final double heightFactor;
  final double expandedHeightFactor;
  final Color grabberColor;
  final WidgetBuilder builder;

  /// Draws the sheet surface around the grabber and content.
  final Widget Function(Widget child)? wrap;

  @override
  State<_DetentFrame> createState() => _DetentFrameState();
}

class _DetentFrameState extends State<_DetentFrame> {
  static const double _flingVelocity = 300;
  static const double _dragThreshold = 24;

  bool _expanded = false;
  double _drag = 0;

  bool get _resizable => widget.expandedHeightFactor > widget.heightFactor;

  void _settle(double velocity) {
    final up = velocity < -_flingVelocity || _drag < -_dragThreshold;
    final down = velocity > _flingVelocity || _drag > _dragThreshold;
    _drag = 0;
    if (up && !_expanded) {
      setState(() => _expanded = true);
    } else if (down) {
      if (_expanded) {
        setState(() => _expanded = false);
      } else {
        Navigator.maybePop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget grabber = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Container(
        width: 36,
        height: 5,
        decoration: ShapeDecoration(
          color: widget.grabberColor,
          shape: const StadiumBorder(),
        ),
      ),
    );
    if (_resizable) {
      grabber = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        onVerticalDragUpdate: (d) => _drag += d.delta.dy,
        onVerticalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
        onVerticalDragCancel: () => _drag = 0,
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: grabber,
            ),
          ),
        ),
      );
    }
    final body = Column(
      children: [
        grabber,
        Expanded(child: Builder(builder: widget.builder)),
      ],
    );
    return AnimatedFractionallySizedBox(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      widthFactor: 1,
      heightFactor: _expanded
          ? widget.expandedHeightFactor
          : widget.heightFactor,
      child: widget.wrap == null ? body : widget.wrap!(body),
    );
  }
}
