import Flutter
import UIKit

final class NavigationSearchFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NavigationSearchView(frame: frame, id: viewId, args: args, messenger: messenger)
    }
}

private final class SearchContainer: UIView {
    var changed: (() -> Void)?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func didMoveToWindow() { super.didMoveToWindow(); changed?() }
}

/// State anchor for the window's real native navigation/search controller.
/// Its UISearchController is installed above the actual Flutter scroll content.
final class NavigationSearchView: NSObject, FlutterPlatformView, NativeNavigationPage, UISearchResultsUpdating, UISearchControllerDelegate {
    private let container: SearchContainer
    private let item = UINavigationItem()
    private let search = UISearchController(searchResultsController: nil)
    private let channel: FlutterMethodChannel
    private var active = true
    private var dark = false
    private var tint: UIColor?
    private var scrollOffset: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var lastBottom: CGFloat = 0
    private var lastActive = false
    private var scheduled = false

    var nativeNavigationItem: UINavigationItem { item }
    var nativeLargeTitle: Bool { false }
    var nativeVerticalNavigation: Bool { false }
    var nativeNeedsBack: Bool { true }
    var nativeScrollOffset: CGFloat { scrollOffset }
    var nativeDark: Bool { dark }
    var nativeTint: UIColor? { tint }

    init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        container = SearchContainer(frame: frame)
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/navigation_search_\(id)", binaryMessenger: messenger)
        super.init()
        search.obscuresBackgroundDuringPresentation = false
        search.hidesNavigationBarDuringPresentation = false
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.autocapitalizationType = .none
        search.searchBar.autocorrectionType = .no
        item.searchController = search
        item.hidesSearchBarWhenScrolling = false
        if #available(iOS 16.0, *) { item.preferredSearchBarPlacement = .stacked }
        if #available(iOS 26.0, *) { item.searchBarPlacementAllowsToolbarIntegration = false }
        configure(args as? [String: Any] ?? [:])
        container.changed = { [weak self] in self?.attach() }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case "measure":
                self.lastHeight = 0
                self.attach()
                self.scheduleReport()
                result(nil)
            case "dismiss":
                self.active = false
                self.search.isActive = false
                self.search.searchBar.resignFirstResponder()
                NativeNavigationHost.deactivate(self)
                result(nil)
            case "configure":
                self.configure(call.arguments as? [String: Any] ?? [:])
                result(nil)
            case "scroll":
                let args = call.arguments as? [String: Any] ?? [:]
                self.scrollOffset = CGFloat(args["offset"] as? Double ?? 0)
                NativeNavigationHost.scroll(self)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }
    private func attach() {
        guard active, container.window != nil else { return }
        NativeNavigationHost.connect(self, from: container)
    }
    private func configure(_ args: [String: Any]) {
        // Flutter sends this on every rebuild. Rewriting identical traits or
        // tint on the search bar makes UIKit redraw the field and restart its
        // glass, so only changed values are applied.
        let title = args["title"] as? String
        if item.title != title { item.title = title }
        let placeholder = args["placeholder"] as? String ?? "Search"
        if search.searchBar.placeholder != placeholder { search.searchBar.placeholder = placeholder }
        dark = args["isDark"] as? Bool == true
        active = args["active"] as? Bool ?? true
        if search.overrideUserInterfaceStyle != .unspecified { search.overrideUserInterfaceStyle = .unspecified }
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if search.searchBar.overrideUserInterfaceStyle != style { search.searchBar.overrideUserInterfaceStyle = style }
        let keyboard: UIKeyboardAppearance = dark ? .dark : .light
        if search.searchBar.keyboardAppearance != keyboard { search.searchBar.keyboardAppearance = keyboard }
        if let value = args["tint"] as? NSNumber {
            let color = Self.color(value.int64Value)
            if tint != color {
                tint = color
                search.searchBar.tintColor = color
            }
        }
        if active { attach(); NativeNavigationHost.update(self) }
        else { NativeNavigationHost.deactivate(self) }
    }
    private static func color(_ value: Int64) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: CGFloat((value >> 24) & 255) / 255)
    }
    func nativeNavigationLayout(contentInset: CGFloat, barBottom: CGFloat) { reportLayout(barBottom: barBottom) }
    func nativeNavigationBack() { back() }
    func willPresentSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchWillPresent(searchController)
        scheduleReport()
    }
    func didPresentSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchDidPresent(searchController)
        scheduleReport()
    }
    func willDismissSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchWillDismiss(searchController)
        scheduleReport()
    }
    func didDismissSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchDidDismiss(searchController)
        scheduleReport()
    }
    private func scheduleReport() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            NativeNavigationHost.scroll(self)
            self.reportLayout(barBottom: self.lastBottom)
        }
    }
    private func reportLayout(barBottom: CGFloat) {
        guard active, let window = container.window, search.searchBar.window === window,
              !search.searchBar.bounds.isEmpty else { return }
        let rect = search.searchBar.convert(search.searchBar.bounds, to: window)
        let bottom = search.isActive ? rect.maxY : max(barBottom, rect.maxY)
        let scale = window.screen.scale
        let height = ceil((bottom - (window.rootViewController?.view.safeAreaInsets.top ?? 0)) * scale) / scale
        guard height.isFinite, height > 0, bottom > 0 else { return }
        if abs(height - lastHeight) >= 1 / scale || lastActive != search.isActive || bottom != lastBottom {
            lastHeight = height
            lastBottom = bottom
            lastActive = search.isActive
            channel.invokeMethod("layout", arguments: [
                "height": Double(height), "active": search.isActive,
                "bottom": Double(bottom), "underlapTop": 0.0
            ])
        }
    }
    func updateSearchResults(for searchController: UISearchController) {
        channel.invokeMethod("changed", arguments: searchController.searchBar.text ?? "")
    }
    private func back() { channel.invokeMethod("back", arguments: nil) }
    deinit { NativeNavigationHost.deactivate(self) }
}
