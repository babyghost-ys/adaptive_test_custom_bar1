import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lays out the native bottom bar before the body, then supplies its occupied
/// height through MediaQuery. Content can paint behind the glass while safe-area
/// aware scroll views can bring their last item fully above it.
///
/// Passing the measurement in layout constraints (as Scaffold does for an
/// extended body) keeps the bar and content inset in the same layout pass.
class NativeBottomBarLayout extends StatelessWidget {
  const NativeBottomBarLayout({
    super.key,
    required this.body,
    this.bottomBar,
    this.barVisible = true,
  });

  final Widget body;
  final Widget? bottomBar;
  final bool barVisible;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _BottomBarLayoutDelegate(barVisible: barVisible),
    children: [
      LayoutId(
        id: _Slot.body,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final metrics = MediaQuery.of(context);
            final barHeight = (constraints as _BodyConstraints).barHeight;
            return MediaQuery(
              data: metrics.copyWith(
                // The bar is bottom-aligned and already includes any safe
                // area in its size. Adding the two would count it twice.
                padding: metrics.padding.copyWith(
                  bottom: math.max(metrics.padding.bottom, barHeight),
                ),
              ),
              child: body,
            );
          },
        ),
      ),
      if (bottomBar != null) LayoutId(id: _Slot.bar, child: bottomBar!),
    ],
  );
}

enum _Slot { body, bar }

class _BodyConstraints extends BoxConstraints {
  _BodyConstraints(Size size, this.barHeight)
    : super.tightFor(width: size.width, height: size.height);

  final double barHeight;

  @override
  bool operator ==(Object other) =>
      other is _BodyConstraints &&
      super == other &&
      barHeight == other.barHeight;

  @override
  int get hashCode => Object.hash(super.hashCode, barHeight);
}

class _BottomBarLayoutDelegate extends MultiChildLayoutDelegate {
  _BottomBarLayoutDelegate({required this.barVisible});

  final bool barVisible;

  @override
  void performLayout(Size size) {
    var barHeight = 0.0;
    if (hasChild(_Slot.bar)) {
      final barSize = layoutChild(
        _Slot.bar,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
      );
      positionChild(_Slot.bar, Offset(0, size.height - barSize.height));
      if (barVisible) barHeight = barSize.height;
    }
    layoutChild(_Slot.body, _BodyConstraints(size, barHeight));
    positionChild(_Slot.body, Offset.zero);
  }

  @override
  bool shouldRelayout(_BottomBarLayoutDelegate oldDelegate) =>
      barVisible != oldDelegate.barVisible;
}
