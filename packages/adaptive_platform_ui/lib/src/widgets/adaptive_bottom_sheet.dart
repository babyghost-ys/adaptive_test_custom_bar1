import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import 'sheet_platform_view_guard.dart';

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
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double heightFactor = 0.5,
    Color? backgroundColor,
    bool isDismissible = true,
  }) {
    assert(heightFactor > 0 && heightFactor <= 1);
    if (!PlatformInfo.isIOS) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        isDismissible: isDismissible,
        backgroundColor: backgroundColor,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: heightFactor,
            child: Builder(builder: builder),
          ),
        ),
      );
    }

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
        backgroundColor: backgroundColor,
        builder: builder,
      ),
    );
  }
}

const Color _scrim = Color(0x33000000);

class _IOSSheet extends StatelessWidget {
  const _IOSSheet({
    required this.heightFactor,
    required this.backgroundColor,
    required this.builder,
  });

  final double heightFactor;
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
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        child: SheetSurface(
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
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: ShapeDecoration(
                          color: grabber,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    Expanded(child: Builder(builder: builder)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
