import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../../core/adaptive_style.dart';

/// How a group of options is laid out in an [AdaptiveFilterSheet].
enum AdaptiveFilterLayout {
  /// A native segmented control. Single choice only.
  segmented,

  /// A grid of square-cornered blocks, an icon over a word.
  blocks,

  /// Tall full-width bands, one above another, the chosen one ticked.
  stack,

  /// Wrapping pill chips.
  chips,

  /// One horizontally scrolling line of pill chips.
  strip,

  /// Wrapping coloured discs labelled with the option title.
  swatches,
}

/// How tall a filter sheet rests.
enum AdaptiveFilterDetents {
  /// Half height, draggable to full height.
  halfAndFull,

  /// Full height only.
  full,

  /// A short sheet that fits a single control.
  short,
}

/// One choice in an [AdaptiveFilterChoices].
class AdaptiveFilterOption {
  const AdaptiveFilterOption(this.id, this.title, {this.sfSymbol, this.tint});
  final String id;
  final String title;
  final String? sfSymbol;

  /// Colour of the chosen state. Defaults to the sheet's tint.
  final Color? tint;
}

/// A control in an [AdaptiveFilterSheet]. Its value is keyed by [id] in the
/// sheet's values: a `List<String>` of chosen option ids for
/// [AdaptiveFilterChoices], a `double` for [AdaptiveFilterSlider].
sealed class AdaptiveFilterControl {
  const AdaptiveFilterControl(this.id, {this.sfSymbol});
  final String id;

  /// SF Symbol that names the control.
  final String? sfSymbol;

  Map<String, Object?> _encode();
}

class AdaptiveFilterChoices extends AdaptiveFilterControl {
  const AdaptiveFilterChoices(
    super.id,
    this.options, {
    super.sfSymbol,
    this.layout = AdaptiveFilterLayout.chips,
    this.multiple = false,
    this.columns = 3,
  });
  final List<AdaptiveFilterOption> options;
  final AdaptiveFilterLayout layout;
  final bool multiple;

  /// Columns of an [AdaptiveFilterLayout.blocks] grid.
  final int columns;

  @override
  Map<String, Object?> _encode() => {
    'type': 'choices',
    'id': id,
    'symbol': sfSymbol,
    'layout': layout.name,
    'multiple': multiple,
    'columns': columns,
    'options': [
      for (final o in options)
        {
          'id': o.id,
          'title': o.title,
          'symbol': o.sfSymbol,
          'tint': o.tint?.toARGB32(),
        },
    ],
  };
}

class AdaptiveFilterSlider extends AdaptiveFilterControl {
  const AdaptiveFilterSlider(
    super.id, {
    super.sfSymbol,
    required this.min,
    required this.max,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.anyLabel,
    this.anyAtMin = true,
  });
  final double min, max;

  /// Text around the number in the live readout.
  final String prefix, suffix;
  final int decimals;

  /// Readout shown instead of a number when the slider rests at its
  /// unrestricted end, [min] when [anyAtMin], otherwise [max].
  final String? anyLabel;
  final bool anyAtMin;

  @override
  Map<String, Object?> _encode() => {
    'type': 'slider',
    'id': id,
    'symbol': sfSymbol,
    'min': min,
    'max': max,
    'prefix': prefix,
    'suffix': suffix,
    'decimals': decimals,
    'anyLabel': anyLabel,
    'anyAtMin': anyAtMin,
  };
}

/// A real UIKit sheet (`UISheetPresentationController`) of filter controls.
///
/// It floats above the whole window, so it covers native navigation and tab
/// bars. The caller describes the controls; UIKit draws them, and the sheet
/// asks [count] after every change so its apply button shows how many
/// results the current choices give.
///
/// Only available where [AdaptiveStyle] is native.
class AdaptiveFilterSheet {
  AdaptiveFilterSheet._();
  static const _channel = MethodChannel('adaptive_platform_ui/filter_sheet');

  /// Whether a native filter sheet can be shown for [context].
  static bool isSupported(BuildContext context) =>
      AdaptiveStyle.of(context) == AdaptiveStyle.native;

  /// Shows the sheet and returns the chosen values, or null when it is
  /// dismissed without applying.
  ///
  /// [values] and [cleared] map each control id to its value: the current
  /// choice, and what the reset button restores.
  static Future<Map<String, Object>?> show({
    required BuildContext context,
    required List<AdaptiveFilterControl> controls,
    required Map<String, Object> values,
    required Map<String, Object> cleared,
    required int Function(Map<String, Object> values) count,
    String title = '',
    Color? tint,
    AdaptiveFilterDetents detents = AdaptiveFilterDetents.halfAndFull,
  }) async {
    if (!isSupported(context)) return null;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return null;
      return count(_decode(call.arguments));
    });
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('show', {
        'title': title,
        'tint': tint?.toARGB32(),
        'detents': detents.name,
        'controls': [for (final c in controls) c._encode()],
        'values': values,
        'cleared': cleared,
        'count': count(values),
      });
      return result == null ? null : _decode(result);
    } on PlatformException {
      return null;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  static Map<String, Object> _decode(Object? raw) => {
    for (final entry in (raw as Map).entries)
      entry.key as String: switch (entry.value) {
        final List<Object?> list => [for (final v in list) v as String],
        final num number => number.toDouble(),
        _ => entry.value!,
      },
  };
}
