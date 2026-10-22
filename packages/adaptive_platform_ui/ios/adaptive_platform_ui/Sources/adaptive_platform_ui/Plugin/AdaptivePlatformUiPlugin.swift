import Flutter
import UIKit

/// Main plugin class for Adaptive Platform UI
/// Registers platform views and handles plugin lifecycle
public class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeNavigationHost.registerNavigation(messenger: registrar.messenger())
        AdaptiveNativeFonts.register(messenger: registrar.messenger())
        // The search tab view covers the whole screen, and Flutter only routes
        // touches on the tab bar and search field to it. With the default
        // (eager) policy, every other touch left the view's gesture-blocking
        // recognizer waiting on Flutter's gesture arena, which never answers
        // for touches it did not route. UIKit's own outside-tap recognizers
        // then never fire: anchored action sheets and toolbar menus could not
        // be dismissed by tapping elsewhere. Hit testing already decides which
        // touches reach this view, so no arena-based blocking is needed.
        // Requires Flutter 3.47 or later.
        registrar.register(SearchTabFactory(messenger: registrar.messenger()),
                           withId: "adaptive_platform_ui/search_tabs",
                           gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
        registrar.register(NavigationSearchFactory(messenger: registrar.messenger()),
                           withId: "adaptive_platform_ui/navigation_search")
        registrar.register(NativeTextFieldViewFactory(messenger: registrar.messenger()),
                           withId: "adaptive_platform_ui/text_field")
        let actionSheets = AnchoredActionSheet(hostProvider: { registrar.viewController })
        let actionSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/action_sheet", binaryMessenger: registrar.messenger())
        actionSheetChannel.setMethodCallHandler { call, result in
            actionSheets.handle(call, result: result)
        }

        let filterSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/filter_sheet", binaryMessenger: registrar.messenger())
        let filterSheets = NativeFilterSheet(
            channel: filterSheetChannel, hostProvider: { registrar.viewController })
        filterSheetChannel.setMethodCallHandler { call, result in
            filterSheets.handle(call, result: result)
        }

        let widgetSheetChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/widget_sheet", binaryMessenger: registrar.messenger())
        let widgetSheets = NativeWidgetSheet(
            channel: widgetSheetChannel, hostProvider: { registrar.viewController })
        widgetSheetChannel.setMethodCallHandler { call, result in
            widgetSheets.handle(call, result: result)
        }


        // Register iOS 26 Button platform view factory
        let ios26ButtonFactory = iOS26ButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ButtonFactory,
            withId: "adaptive_platform_ui/ios26_button"
        )

        // Register iOS 26 Switch platform view factory
        let ios26SwitchFactory = iOS26SwitchViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SwitchFactory,
            withId: "adaptive_platform_ui/ios26_switch"
        )

        registrar.register(
            iOS26DatePickerViewFactory(messenger: registrar.messenger()),
            withId: "adaptive_platform_ui/ios26_date_picker"
        )

        // Register iOS 26 Slider platform view factory
        let ios26SliderFactory = iOS26SliderViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SliderFactory,
            withId: "adaptive_platform_ui/ios26_slider"
        )

        // Register iOS 26 SegmentedControl platform view factory
        let ios26SegmentedControlFactory = iOS26SegmentedControlViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26SegmentedControlFactory,
            withId: "adaptive_platform_ui/ios26_segmented_control"
        )

        // Register iOS 26 AlertDialog platform view factory
        let ios26AlertDialogFactory = iOS26AlertDialogViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26AlertDialogFactory,
            withId: "adaptive_platform_ui/ios26_alert_dialog"
        )

        // Register iOS 26 PopupMenuButton platform view factory
        let ios26PopupMenuButtonFactory = iOS26PopupMenuButtonViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26PopupMenuButtonFactory,
            withId: "adaptive_platform_ui/ios26_popup_menu_button"
        )

        // Register iOS 26 ContextMenu platform view factory
        let ios26ContextMenuFactory = iOS26ContextMenuViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ContextMenuFactory,
            withId: "adaptive_platform_ui/ios26_context_menu"
        )

        // Register iOS 26 TabBar platform view factory
        let ios26TabBarFactory = iOS26TabBarViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26TabBarFactory,
            withId: "adaptive_platform_ui/ios26_tab_bar"
        )

        // Register iOS 26 Toolbar platform view factory
        let ios26ToolbarFactory = iOS26ToolbarFactory(messenger: registrar.messenger())
        registrar.register(
            ios26ToolbarFactory,
            withId: "adaptive_platform_ui/ios26_toolbar"
        )

        // Register iOS 26 Blur View platform view factory
        let ios26BlurViewFactory = iOS26BlurViewFactory(messenger: registrar.messenger())
        registrar.register(
            ios26BlurViewFactory,
            withId: "adaptive_platform_ui/ios26_blur_view"
        )

        // iPhone Duo: where the system puts its vertical bar (iOS 27.1)
        let verticalBarEdgeChannel = FlutterEventChannel(
            name: "adaptive_platform_ui/vertical_bar_edge",
            binaryMessenger: registrar.messenger()
        )
        verticalBarEdgeChannel.setStreamHandler(VerticalBarEdgeStreamHandler(registrar: registrar))

        // iPhone Duo: where UIKit lays out a navigation title in this window
        let titleBand = DuoTitleBand(registrar: registrar)
        let titleBandChannel = FlutterMethodChannel(
            name: "adaptive_platform_ui/duo_title_band",
            binaryMessenger: registrar.messenger()
        )
        titleBandChannel.setMethodCallHandler { call, result in
            titleBand.handle(call, result: result)
        }
    }
}
