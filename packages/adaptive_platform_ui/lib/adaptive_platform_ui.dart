/// Adaptive widgets that render the running platform's own controls.
///
/// - iOS: the running release's UIKit controls and bars, Liquid Glass on
///   iOS 26 and later, including the iPhone Duo vertical bar.
/// - Android and elsewhere: Material widgets.
///
/// ```dart
/// AdaptiveApp(
///   theme: AdaptiveThemeData(primaryColor: Colors.teal),
///   home: AdaptiveScaffold(
///     appBar: AdaptiveAppBar(title: 'Inbox', largeTitle: true),
///     body: ListView(children: messages),
///   ),
/// )
/// ```
library;

// Platform utilities
export 'src/core/platform_info.dart';
export 'src/core/adaptive_style.dart';

// Animation utilities
export 'src/core/animation.dart';

// Styles
export 'src/core/theme/adaptive_theme.dart';
export 'src/style/sf_symbol.dart';
export 'src/style/adaptive_icon.dart';

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
export 'src/navigation/drawer/adaptive_drawer.dart';
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

export 'src/overlays/action_sheet/adaptive_action_sheet.dart';
export 'src/overlays/bottom_sheet/adaptive_bottom_sheet.dart';
export 'src/overlays/filter_sheet/adaptive_filter_sheet.dart';
export 'src/controls/pickers/adaptive_inline_date_picker.dart';
export 'src/style/adaptive_native_fonts.dart';

export 'src/navigation/search/adaptive_navigation_search_bar.dart';
