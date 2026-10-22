/// A Flutter package that provides adaptive platform-specific widgets
///
/// This package automatically renders native-looking widgets based on the platform:
/// - iOS 26+: Modern iOS 26 native designs with latest visual styles
/// - iOS <26 (iOS 18 and below): Traditional Cupertino widgets
/// - Android: Material Design widgets
///
/// ## Features
///
/// - Automatic platform detection
/// - iOS version-specific widget rendering
/// - Native iOS 26 designs following Apple's Human Interface Guidelines
/// - Seamless fallback to appropriate widgets for older iOS versions
/// - Material Design for Android
///
/// ## Usage
///
/// ```dart
/// import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
///
/// AdaptiveButton(
///   onPressed: () {
///     print('Button pressed');
///   },
///   child: Text('Click Me'),
/// )
/// ```
library;

// Platform utilities
export 'src/core/platform_info.dart';

// Animation utilities
export 'src/core/animation.dart';

// Styles
export 'src/style/sf_symbol.dart';

// Widgets
export 'src/app/adaptive_app.dart';
export 'src/navigation/navigator/adaptive_navigator.dart'
    show AdaptiveNavigator, AdaptivePage;

// Fixed toolbar chrome (installed automatically by AdaptiveApp; exported so
// apps with their own MaterialApp/CupertinoApp can wrap their builder)
export 'src/navigation/chrome/adaptive_toolbar_host.dart';
export 'src/navigation/chrome/toolbar_registry.dart';
export 'src/navigation/app_bar/adaptive_app_bar.dart';
export 'src/navigation/tab_bar/adaptive_bottom_navigation_bar.dart';
export 'src/navigation/search/adaptive_tab_search.dart';
export 'src/controls/button/adaptive_button.dart';
export 'src/controls/switch/adaptive_switch.dart';
export 'src/controls/checkbox/adaptive_checkbox.dart';
export 'src/controls/radio/adaptive_radio.dart';
export 'src/content/card/adaptive_card.dart';
export 'src/content/badge/adaptive_badge.dart';
export 'src/overlays/tooltip/adaptive_tooltip.dart';
export 'src/controls/slider/adaptive_slider.dart';
export 'src/controls/segmented_control/adaptive_segmented_control.dart';
export 'src/overlays/alert_dialog/adaptive_alert_dialog.dart';
export 'src/overlays/popup_menu/adaptive_popup_menu_button.dart';
export 'src/overlays/context_menu/adaptive_context_menu.dart';
export 'src/navigation/scaffold/adaptive_scaffold.dart';
export 'src/navigation/app_bar/adaptive_app_bar_action.dart';
export 'src/overlays/snackbar/adaptive_snackbar.dart';
export 'src/controls/pickers/adaptive_date_picker.dart';
export 'src/controls/pickers/adaptive_time_picker.dart';
export 'src/content/list_tile/adaptive_list_tile.dart';
export 'src/controls/text_field/adaptive_text_field.dart';
export 'src/controls/text_field/adaptive_text_form_field.dart';
export 'src/navigation/tab_bar/adaptive_tab_view.dart';
export 'src/navigation/scaffold/adaptive_floating_action_button.dart';
export 'src/content/form_section/adaptive_form_section.dart';
export 'src/content/expansion_tile/adaptive_expansion_tile.dart';
export 'src/content/blur_view/adaptive_blur_view.dart';

// iOS 26 specific widgets (for advanced usage)
export 'src/controls/button/ios26_button.dart';
export 'src/controls/switch/ios26_switch.dart';
export 'src/controls/slider/ios26_slider.dart';
export 'src/controls/segmented_control/ios26_segmented_control.dart';
export 'src/overlays/alert_dialog/ios26_alert_dialog.dart';
export 'src/overlays/context_menu/ios26_context_menu.dart';
export 'src/navigation/search/ios26_native_search_tab_bar.dart';
export 'src/navigation/tab_bar/ios26_native_tab_bar.dart';
export 'src/navigation/scaffold/ios26_scaffold_legacy.dart';

export 'src/navigation/app_bar/adaptive_navigation_scroll_controller.dart';

export 'src/overlays/action_sheet/adaptive_action_sheet.dart';
export 'src/overlays/bottom_sheet/adaptive_bottom_sheet.dart';
export 'src/controls/pickers/adaptive_inline_date_picker.dart';
export 'src/style/adaptive_native_fonts.dart';

export 'src/navigation/search/adaptive_navigation_search_bar.dart';

export 'src/content/list_view/adaptive_list_view.dart';
