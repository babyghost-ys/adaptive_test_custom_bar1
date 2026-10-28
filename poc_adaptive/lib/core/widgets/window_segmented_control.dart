import 'dart:io' show Platform;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Diagnostic: a real UIKit control hosted outside Flutter's platform views.
class WindowSegmentedControl extends StatefulWidget {
  const WindowSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;

  @override
  State<WindowSegmentedControl> createState() => _WindowSegmentedControlState();
}

class _WindowSegmentedControlState extends State<WindowSegmentedControl> {
  static const _channel = MethodChannel('sheet_poc/window_segment');
  static int _nextId = 0;
  final int _id = _nextId++;
  final GlobalKey _anchor = GlobalKey();
  List<Object?>? _lastGeometry;
  int _updateSerial = 0;

  bool get _useNative => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_useNative) {
      _channel.setMethodCallHandler(_handleNative);
      SchedulerBinding.instance.addPostFrameCallback(_afterFrame);
    }
  }

  Future<void> _handleNative(MethodCall call) async {
    final args = call.arguments;
    if (mounted &&
        call.method == 'changed' &&
        args is Map &&
        args['id'] == _id) {
      final index = args['index'];
      if (index is int && index >= 0 && index < widget.labels.length) {
        widget.onValueChanged(index);
      }
    }
  }

  void _afterFrame(Duration _) {
    if (!mounted) return;
    final object = _anchor.currentContext?.findRenderObject();
    if (object is RenderBox && object.attached && object.hasSize) {
      final bounds = MatrixUtils.transformRect(
        object.getTransformTo(null),
        Offset.zero & object.size,
      );
      var clip = Offset.zero & MediaQuery.sizeOf(context);
      RenderObject child = object;
      RenderObject? ancestor = child.parent;
      while (ancestor != null) {
        final parentClip = ancestor.describeApproximatePaintClip(child);
        if (parentClip != null) {
          clip = clip.intersect(
            MatrixUtils.transformRect(
              ancestor.getTransformTo(null),
              parentClip,
            ),
          );
        }
        child = ancestor;
        ancestor = ancestor.parent;
      }
      clip = clip.intersect(bounds);
      final route = ModalRoute.of(context);
      final visible =
          (route?.isCurrent ?? true) ||
          (route?.animation?.status == AnimationStatus.reverse &&
              route?.secondaryAnimation?.status == AnimationStatus.dismissed);
      final geometry = <Object?>[
        bounds.left,
        bounds.top,
        bounds.width,
        bounds.height,
        clip.left,
        clip.top,
        clip.width,
        clip.height,
        widget.selectedIndex,
        visible && !clip.isEmpty,
      ];
      if (!listEquals(_lastGeometry, geometry)) {
        final serial = ++_updateSerial;
        _channel
            .invokeMethod<bool>('update', {
              'id': _id,
              'labels': widget.labels,
              'index': widget.selectedIndex,
              'frame': [bounds.left, bounds.top, bounds.width, bounds.height],
              'clip': [clip.left, clip.top, clip.width, clip.height],
              'visible': visible && !clip.isEmpty,
            })
            .then((attached) {
              if (!mounted || serial != _updateSerial) return;
              if (attached == true) {
                _lastGeometry = geometry;
              } else {
                // The engine may not have attached its view to a window yet.
                Future<void>.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) SchedulerBinding.instance.ensureVisualUpdate();
                });
              }
            });
      }
    }
    // This callback follows frames already scheduled by route animations,
    // scrolling or rotation; it does not itself request continuous frames.
    SchedulerBinding.instance.addPostFrameCallback(_afterFrame);
  }

  @override
  void dispose() {
    if (_useNative) {
      _channel.invokeMethod<void>('remove', {'id': _id});
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNative) {
      return AdaptiveSegmentedControl(
        labels: widget.labels,
        selectedIndex: widget.selectedIndex,
        onValueChanged: widget.onValueChanged,
      );
    }
    return SizedBox(key: _anchor, height: 36, width: double.infinity);
  }
}
