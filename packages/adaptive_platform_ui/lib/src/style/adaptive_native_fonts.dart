import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../platform/platform_info.dart';

/// One font family for the package's native iOS components.
///
/// On iOS the family must be installed on the device: a built-in family
/// (`UIFont.familyNames`, see [availableFamilies]) or a font bundled with
/// the app and registered with iOS. Setting it restyles live:
///
/// * segmented control titles, button titles, text fields and the glass
///   capsule's labels and badges;
/// * navigation bar titles (inline and large) and bar button titles;
/// * tab bar labels and search fields.
///
/// System menus, context menus, action sheets, alerts and date pickers have
/// no public font API and keep the system font. Text that Flutter draws is
/// not changed; listen to [family] to use the same family in your theme.
abstract final class AdaptiveNativeFonts {
  static const _channel = MethodChannel('adaptive_platform_ui/native_fonts');

  /// The family in use, or null for the system font.
  static final ValueNotifier<String?> family = ValueNotifier<String?>(null);

  /// Uses [name] for native components, or the system font when null.
  /// On iOS a family the system does not have is ignored natively.
  ///
  /// [family] changes once the native components have restyled, so
  /// listeners can measure them in the new font.
  static Future<void> setFamily(String? name) async {
    if (PlatformInfo.isIOS) {
      try {
        await _channel.invokeMethod<void>('setFamily', {'family': name});
      } on MissingPluginException {
        // Not running with the plugin (tests, other platforms).
      }
    }
    family.value = name;
  }

  /// Font families installed on the device. Empty off iOS.
  static Future<List<String>> availableFamilies() async {
    if (!PlatformInfo.isIOS) return const [];
    try {
      final names = await _channel.invokeListMethod<String>(
        'availableFamilies',
      );
      return names ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
