import 'package:flutter/painting.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

import 'package:native_widgets_on_duo/features/investment/models/asset.dart';

/// Reads the chosen option ids of a choices control.
List<String> chosenIds(Map<String, Object> values, String id) =>
    (values[id] as List<String>?) ?? const [];

/// The first chosen id of a single-choice control, as the matching enum.
T chosenEnum<T extends Enum>(
  Map<String, Object> values,
  String id,
  List<T> all,
) {
  final ids = chosenIds(values, id);
  return all.firstWhere(
    (e) => ids.isNotEmpty && e.name == ids.first,
    orElse: () => all.first,
  );
}

/// Every chosen id of a multiple-choice control, as the matching enums.
Set<T> chosenEnums<T extends Enum>(
  Map<String, Object> values,
  String id,
  List<T> all,
) {
  final ids = chosenIds(values, id).toSet();
  return {
    for (final e in all)
      if (ids.contains(e.name)) e,
  };
}

/// One option per asset, drawn as a coloured disc.
List<AdaptiveFilterOption> assetSwatches(List<Asset> assets) => [
  for (final a in assets)
    AdaptiveFilterOption(a.symbol, a.symbol, tint: Color(a.color)),
];
