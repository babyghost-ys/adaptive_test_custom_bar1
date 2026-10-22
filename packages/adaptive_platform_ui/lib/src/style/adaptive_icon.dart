import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// An icon for every platform: an SF Symbol for the native iOS controls and
/// a Material icon, image or widget for Flutter-drawn ones.
///
/// ```dart
/// AdaptiveIcon(sfSymbol: 'house', icon: Icons.home_outlined)
/// ```
///
/// Native iOS controls use [sfSymbol], or [image] when there is no symbol.
/// Flutter-drawn controls use [widget], then [image], then [icon]; without
/// any of them they draw a neutral placeholder.
@immutable
class AdaptiveIcon {
  const AdaptiveIcon({this.sfSymbol, this.icon, this.image, this.widget})
    : assert(
        sfSymbol != null || icon != null || image != null || widget != null,
        'AdaptiveIcon needs at least one of sfSymbol, icon, image or widget',
      );

  /// SF Symbol name, such as `house.fill`.
  final String? sfSymbol;

  /// Material icon for Android and other Flutter-drawn controls.
  final IconData? icon;

  /// A picture, such as an `AssetImage`, `FileImage` or `NetworkImage`.
  final ImageProvider? image;

  /// A widget drawn as is on Flutter-drawn controls.
  final Widget? widget;

  /// [icon], or the closest Cupertino glyph for [sfSymbol] on Flutter-drawn
  /// iOS controls, or a neutral circle.
  IconData get iconData => icon ?? _cupertinoGlyphs[sfSymbol] ?? Icons.circle;

  /// A Flutter widget for this icon, tinted with [color] where it can be.
  Widget build({Color? color, double? size}) {
    if (widget != null) return widget!;
    if (image != null) {
      return ImageIcon(image, color: color, size: size);
    }
    return Icon(iconData, color: color, size: size);
  }

  static const _cupertinoGlyphs = <String, IconData>{
    'house': CupertinoIcons.house,
    'house.fill': CupertinoIcons.house_fill,
    'magnifyingglass': CupertinoIcons.search,
    'heart': CupertinoIcons.heart,
    'heart.fill': CupertinoIcons.heart_fill,
    'person': CupertinoIcons.person,
    'person.fill': CupertinoIcons.person_fill,
    'gear': CupertinoIcons.settings,
    'star': CupertinoIcons.star,
    'star.fill': CupertinoIcons.star_fill,
    'bell': CupertinoIcons.bell,
    'bell.fill': CupertinoIcons.bell_fill,
    'bag': CupertinoIcons.bag,
    'bag.fill': CupertinoIcons.bag_fill,
    'bookmark': CupertinoIcons.bookmark,
    'bookmark.fill': CupertinoIcons.bookmark_fill,
    'info.circle': CupertinoIcons.info_circle,
    'info.circle.fill': CupertinoIcons.info_circle_fill,
    'plus.circle': CupertinoIcons.add_circled,
    'plus': CupertinoIcons.add,
    'checkmark.circle': CupertinoIcons.checkmark_circle,
    'ellipsis.circle': CupertinoIcons.ellipsis_circle,
  };

  @override
  bool operator ==(Object other) =>
      other is AdaptiveIcon &&
      other.sfSymbol == sfSymbol &&
      other.icon == icon &&
      other.image == image &&
      other.widget == widget;

  @override
  int get hashCode => Object.hash(sfSymbol, icon, image, widget);
}
