import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// Flutter's iOS compositor gives every native view an overlay that covers
// all Flutter drawing intersecting it, and cuts that whole rectangle out of
// the layers below for everything drawn later. A native control on a page
// behind an open sheet therefore claims a rectangle the size of the sheet's
// scrim and background, and every later sheet label that does not itself
// touch a native view disappears from it.
//
// A native view hidden behind a sheet cannot be seen anyway, so it is left
// out of the frame while any part of it is behind one. Views inside the
// sheet, and views that are still visible, keep rendering natively.

// A LinkedHashSet: iteration follows the order the sheets opened in.
final Set<_RenderSheetSurface> _openSheets = <_RenderSheetSurface>{};
final Set<_RenderPlatformViewGuard> _guards = <_RenderPlatformViewGuard>{};
bool _repaintScheduled = false;

/// Repaints every guard after the current frame, so they see where the
/// sheets ended up.
void _scheduleGuardRepaint() {
  if (_repaintScheduled) return;
  _repaintScheduled = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _repaintScheduled = false;
    for (final guard in _guards) {
      if (guard.attached) guard.markNeedsPaint();
    }
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// Marks the area of an open sheet. Used by `AdaptiveBottomSheet`.
class SheetSurface extends SingleChildRenderObjectWidget {
  const SheetSurface({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSheetSurface();
}

class _RenderSheetSurface extends RenderProxyBox {
  Rect? _lastRect;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _openSheets.add(this);
    _scheduleGuardRepaint();
  }

  @override
  void detach() {
    _openSheets.remove(this);
    _scheduleGuardRepaint();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // The sheet slides in and is dragged by its route's layout, which moves
    // it without repainting the page behind; tell the guards it moved.
    final rect = _globalRect(this);
    if (rect != _lastRect) {
      _lastRect = rect;
      _scheduleGuardRepaint();
    }
  }
}

/// Leaves [child], a native platform view, out of the frame while an open
/// sheet that does not contain it covers any part of it.
class PlatformViewSheetGuard extends SingleChildRenderObjectWidget {
  const PlatformViewSheetGuard({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlatformViewGuard();
}

class _RenderPlatformViewGuard extends RenderProxyBox {
  bool _hidden = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _guards.add(this);
  }

  @override
  void detach() {
    _guards.remove(this);
    super.detach();
  }

  /// The sheet this view is inside, if any.
  _RenderSheetSurface? _ownSheet() {
    for (RenderObject? node = parent; node != null; node = node.parent) {
      if (node is _RenderSheetSurface) return node;
    }
    return null;
  }

  bool _coveredBySheet() {
    if (_openSheets.isEmpty || !hasSize) return false;
    final mine = _globalRect(this);
    // Sheets open in stacking order; only those above this view's own
    // sheet (or above the page, for a view on no sheet) can cover it.
    final own = _ownSheet();
    var above = own == null;
    for (final sheet in _openSheets) {
      if (!above) {
        above = identical(sheet, own);
        continue;
      }
      if (!sheet.attached || !sheet.hasSize) continue;
      if (_globalRect(sheet).overlaps(mine)) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _hidden = _coveredBySheet();
    if (!_hidden) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_hidden && super.hitTest(result, position: position);
}
