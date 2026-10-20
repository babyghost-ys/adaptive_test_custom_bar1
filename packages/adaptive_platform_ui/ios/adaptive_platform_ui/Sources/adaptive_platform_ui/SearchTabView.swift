import Flutter
import UIKit

final class SearchTabFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        SearchTabView(frame: frame, id: viewId, args: args, messenger: messenger)
    }
}

/// The platform view publishes state only. UIKit's real tab hierarchy is above
/// Flutter, so native controls receive their touches directly from UIKit.
private final class SearchTabsContainer: UIView {
    var changed: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); changed?() }
    override func didMoveToWindow() { super.didMoveToWindow(); changed?() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); changed?() }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class SearchTabsController: UITabBarController {
    var layoutChanged: (() -> Void)?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        selectedViewController?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layoutChanged?() }
}

/// UIKit owns the tab, navigation and search controllers. The selected page's
/// native scroll view contains Flutter itself, including the pixels filtered
/// by the system's scroll-edge effects.
final class SearchTabView: NSObject, FlutterPlatformView, UITabBarControllerDelegate,
    UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {
    private let container: SearchTabsContainer
    private let tabs = SearchTabsController()
    private let searchPage = NativeNavigationContent()
    private let search = UISearchController(searchResultsController: nil)
    private lazy var searchNavigation = NativeNavigationHost.makeNavigationController(
        content: searchPage, onLayout: { [weak self] in self?.scheduleReport() })
    private let channel: FlutterMethodChannel
    private var configurations: [[String: Any]] = []
    private var pages: [NativeNavigationContent] = []
    private var navigations: [UINavigationController] = []
    private var searchIndex = -1
    private var lastNotifiedIndex = -1
    private var previousContentIndex = 0
    private let headerExtension = UIView()
    private var headerHeight: CGFloat = 0
    private var headerColor: UIColor?
    private var hidden = false
    private var disposed = false
    private var layingOut = false
    private var reportScheduled = false
    private var lastLayout: NSDictionary?
    private var keyboardObserver: NSObjectProtocol?
    private var scrollOffset: CGFloat = 0
    private var query = ""
    private var synchronizingQuery = false
    private var preservingQueryDuringDismissal = false
    private var dismissingForNavigation = false
    private var holdsScrollAtRest = false
    private var restingContentInset: CGFloat?
    private var initialConfiguration: [String: Any] = [:]
    private var configuredForWindow = false
    private var hostAttached = false
    private var hostedIndex: Int?
    private var hostedSearchVisible = false
    private var usesToolbarSearch = false
    private var toolbarSearchVisible = false
    private var usesVerticalSearchTitle = false
    private var scrollView: UIScrollView { searchPage.scroll }

    init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        container = SearchTabsContainer(frame: frame)
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/search_tabs_\(id)", binaryMessenger: messenger)
        super.init()
        initialConfiguration = args as? [String: Any] ?? [:]
        let initialItems = initialConfiguration["items"] as? [[String: Any]] ?? []
        let initialTitle = initialItems.first { $0["isSearch"] as? Bool == true }?["title"] as? String ?? ""
        container.backgroundColor = .clear
        tabs.view.backgroundColor = .systemBackground
        tabs.delegate = self
        if #available(iOS 26.0, *) { tabs.tabBarMinimizeBehavior = .never }
        // Configure the item's native title/search policy before creating or
        // loading its navigation controller. UIKit reads this initial state
        // when it first establishes the large-title scroll relationship.
        searchPage.title = initialTitle
        searchPage.navigationItem.title = initialTitle
        searchPage.navigationItem.largeTitleDisplayMode = .always
        if #available(iOS 26.0, *) { searchPage.navigationItem.largeTitleDisplayMode = .inline }
        searchPage.navigationItem.searchController = search
        searchPage.navigationItem.hidesSearchBarWhenScrolling = false
        if #available(iOS 27.0, *) {
            searchPage.navigationItem.navigationBarMinimization.minimizationBehavior = .never
        }
        if #available(iOS 26.0, *) {
            searchPage.navigationItem.largeTitle = initialTitle
            searchPage.navigationItem.searchBarPlacementAllowsToolbarIntegration = true
        }
        search.obscuresBackgroundDuringPresentation = false
        search.hidesNavigationBarDuringPresentation = false
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.delegate = self
        search.searchBar.autocapitalizationType = .none
        search.searchBar.autocorrectionType = .no
        search.searchBar.placeholder = initialConfiguration["placeholder"] as? String ?? "Search"
        searchPage.nativeMetricsChanged = { [weak self] inset, _ in
            guard let self, !self.disposed, !self.hidden,
                  self.tabs.selectedIndex == self.searchIndex,
                  inset.isFinite, inset > 0 else { return }
            self.restingContentInset = inset
            self.scheduleReport()
        }
        searchNavigation.navigationBar.prefersLargeTitles = true
        container.changed = { [weak self] in self?.attachAndLayout() }
        tabs.layoutChanged = { [weak self] in self?.scheduleReport() }
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleReport() }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, !self.disposed else { result(nil); return }
            switch call.method {
            case "configure": self.configure(call.arguments as? [String: Any] ?? [:]); result(nil)
            case "dispose": self.detach(); result(nil)
            case "presented": result(nil)
            case "setScrollOffset":
                if let offset = call.arguments as? Double, offset.isFinite {
                    self.scrollOffset = CGFloat(offset)
                    self.applyScrollOffset()
                }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    private func configure(_ args: [String: Any]) {
        guard configuredForWindow else { initialConfiguration = args; return }
        let items = args["items"] as? [[String: Any]] ?? []
        if !(items as NSArray).isEqual(to: configurations) {
            configurations = items
            searchIndex = items.firstIndex { $0["isSearch"] as? Bool == true } ?? -1
            pages = items.indices.map { $0 == searchIndex ? searchPage : NativeNavigationContent() }
            navigations = pages.enumerated().map { index, page in
                index == searchIndex ? searchNavigation : NativeNavigationHost.makeNavigationController(
                    content: page, onLayout: { [weak self] in self?.scheduleReport() })
            }
            if #available(iOS 26.0, *) {
                tabs.tabs = items.enumerated().map { index, item in
                    let title = item["title"] as? String ?? ""
                    let tab: UITab
                    if index == searchIndex {
                        if usesToolbarSearch {
                            tab = UITab(title: title, image: UIImage(systemName: "magnifyingglass"),
                                        identifier: "native_toolbar_search") { [weak self] _ in
                                self?.searchNavigation ?? UIViewController()
                            }
                        } else {
                            let nativeSearch = UISearchTab { [weak self] _ in
                                self?.searchNavigation ?? UIViewController()
                            }
                            nativeSearch.automaticallyActivatesSearch = true
                            tab = nativeSearch
                        }
                        tab.title = title
                        searchPage.title = title
                        searchPage.navigationItem.title = title
                        searchPage.navigationItem.largeTitle = title
                    } else {
                        let navigation = navigations[index]
                        tab = UITab(title: title,
                                    image: UIImage(systemName: item["symbol"] as? String ?? "circle"),
                                    identifier: "tab_\(index)") { _ in navigation }
                        if #available(iOS 26.1, *), let symbol = item["selectedSymbol"] as? String {
                            tab.selectedImage = UIImage(systemName: symbol)
                        }
                    }
                    tab.badgeValue = item["badge"] as? String
                    return tab
                }
            } else {
                tabs.viewControllers = items.enumerated().map { index, item in
                    let title = item["title"] as? String ?? ""
                    let controller: UIViewController
                    if index == searchIndex {
                        searchPage.title = title
                        searchPage.navigationItem.title = title
                        controller = searchNavigation
                    } else {
                        controller = navigations[index]
                    }
                    let image = UIImage(systemName: item["symbol"] as? String ?? "circle")
                    let selected = (item["selectedSymbol"] as? String).flatMap { UIImage(systemName: $0) }
                    controller.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: selected)
                    controller.tabBarItem.tag = index
                    controller.tabBarItem.badgeValue = item["badge"] as? String
                    return controller
                }
            }
            hostedIndex = nil
        }
        let style: UIUserInterfaceStyle = args["isDark"] as? Bool == true ? .dark : .light
        // Keep the controllers above Flutter on the real system traits. Only
        // native chrome uses the app's selected (possibly explicit) theme.
        container.overrideUserInterfaceStyle = .unspecified
        tabs.overrideUserInterfaceStyle = .unspecified
        tabs.tabBar.overrideUserInterfaceStyle = style
        tabs.view.backgroundColor = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
        for (index, navigation) in navigations.enumerated() {
            navigation.overrideUserInterfaceStyle = .unspecified
            navigation.navigationBar.overrideUserInterfaceStyle = style
            navigation.toolbar.overrideUserInterfaceStyle = style
            navigation.view.backgroundColor = UIColor.systemBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: style))
            if pages.indices.contains(index) { pages[index].setNativeBackground(style: style) }
        }
        search.overrideUserInterfaceStyle = .unspecified
        search.searchBar.overrideUserInterfaceStyle = style
        search.searchBar.keyboardAppearance = style == .dark ? .dark : .light
        search.searchBar.placeholder = args["placeholder"] as? String ?? "Search"
        if let value = args["tint"] as? NSNumber {
            let argb = value.int64Value
            tabs.view.tintColor = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                                         green: CGFloat((argb >> 8) & 255) / 255,
                                         blue: CGFloat(argb & 255) / 255,
                                         alpha: CGFloat((argb >> 24) & 255) / 255)
        }
        headerHeight = CGFloat((args["headerHeight"] as? NSNumber)?.doubleValue ?? 0)
        headerColor = (args["headerColor"] as? NSNumber).map { value in
            let argb = value.int64Value
            return UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                           green: CGFloat((argb >> 8) & 255) / 255,
                           blue: CGFloat(argb & 255) / 255,
                           alpha: CGFloat((argb >> 24) & 255) / 255)
        }
        let wasHidden = hidden
        hidden = args["hidden"] as? Bool ?? false
        setTabBarHidden(hidden || (usesToolbarSearch && search.isActive))
        if hidden {
            if !wasHidden, search.isActive || search.isBeingPresented || search.isBeingDismissed {
                dismissingForNavigation = true
            }
            preservingQueryDuringDismissal = !query.isEmpty
            search.isActive = false
        }
        if let index = args["selectedIndex"] as? Int, pages.indices.contains(index), tabs.selectedIndex != index {
            if index == searchIndex { prepareSearchPresentation() }
            else { search.isActive = false }
            if #available(iOS 26.0, *) { tabs.selectedTab = tabs.tabs[index] }
            else { tabs.selectedIndex = index }
        }
        if wasHidden && !hidden && tabs.selectedIndex == searchIndex { holdsScrollAtRest = false }
        attachAndLayout()
    }

    private func setTabBarHidden(_ value: Bool) {
        // A managed push uses hidesBottomBarWhenPushed, so UIKit animates its
        // own tab bar together with the navigation transition.
        if NativeNavigationHost.ownsRouteTransition { return }
        if #available(iOS 18.0, *) { tabs.setTabBarHidden(value, animated: false) }
        else { tabs.tabBar.isHidden = value }
    }

    private func attachAndLayout() {
        guard !disposed, !layingOut, container.window != nil,
              container.bounds.width > 0, container.bounds.height > 0 else { return }
        layingOut = true
        defer { layingOut = false }
        if !configuredForWindow {
            let edge = VerticalBarEdgeStreamHandler.edge(of: container)
            usesToolbarSearch = edge == "left" || edge == "right"
            if #available(iOS 26.0, *), usesToolbarSearch {
                if #available(iOS 27.0, *) { tabs.prominentTabIdentifier = "native_toolbar_search" }
                searchPage.toolbarItems = [searchPage.navigationItem.searchBarPlacementBarButtonItem]
                searchNavigation.setToolbarHidden(false, animated: false)
            }
            configuredForWindow = true
            configure(initialConfiguration)
            initialConfiguration = [:]
        }
        updateSearchTitleMode()
        selectHostedContent()
        scheduleReport()
    }

    private func selectHostedContent() {
        let index = tabs.selectedIndex
        guard pages.indices.contains(index) else { return }
        let searchVisible = index == searchIndex && !hidden
        if searchVisible && (!hostAttached || hostedIndex != index || !hostedSearchVisible) {
            restoreSearchNavigation()
        }
        if !hostAttached {
            hostAttached = true
            hostedIndex = index
            hostedSearchVisible = searchVisible
            NativeNavigationHost.attachTabs(tabs: tabs, content: pages[index],
                                            searchNavigation: searchVisible ? searchNavigation : nil,
                                            tabNavigation: navigations[index],
                                            from: container)
        } else if hostedIndex != index || hostedSearchVisible != searchVisible {
            hostedIndex = index
            hostedSearchVisible = searchVisible
            NativeNavigationHost.selectTab(content: pages[index],
                                           searchNavigation: searchVisible ? searchNavigation : nil,
                                           tabNavigation: navigations[index])
        }
        if searchVisible { applyScrollOffset() }
    }

    /// A pushed Flutter route temporarily uses this tab's real native stack.
    /// Returning to Search restores its original native navigation item and
    /// lets UISearchController resume ownership of the system search field.
    private func restoreSearchNavigation() {
        let title = configurations.indices.contains(searchIndex)
            ? configurations[searchIndex]["title"] as? String ?? "" : ""
        let item = searchPage.navigationItem
        searchPage.title = title
        item.title = title
        restoreQuery()
        item.searchController = search
        item.leftBarButtonItems = nil
        item.rightBarButtonItems = nil
        item.hidesBackButton = false
        item.largeTitleDisplayMode = .always
        if #available(iOS 26.0, *) { item.largeTitleDisplayMode = .inline }
        item.hidesSearchBarWhenScrolling = false
        if #available(iOS 27.0, *) {
            item.navigationBarMinimization.minimizationBehavior = .never
        }
        if #available(iOS 26.0, *) { item.largeTitle = title }
        searchNavigation.navigationBar.prefersLargeTitles = true
        if !NativeNavigationHost.ownsRouteTransition &&
            (searchNavigation.viewControllers.count != 1 || searchNavigation.viewControllers.first !== searchPage) {
            searchNavigation.setViewControllers([searchPage], animated: false)
        }
        searchNavigation.setNavigationBarHidden(false, animated: false)
        restingContentInset = nil
    }

    private func updateToolbarSearchPresentation() {
        guard usesToolbarSearch else { return }
        let visible = !hidden && tabs.selectedIndex == searchIndex
        if visible && !toolbarSearchVisible {
            prepareSearchPresentation()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.disposed, !self.hidden, self.tabs.selectedIndex == self.searchIndex else { return }
                self.searchNavigation.view.layoutIfNeeded()
                self.search.isActive = true
            }
        }
        toolbarSearchVisible = visible
    }

    private func updateSearchTitleMode() {
        let edge = VerticalBarEdgeStreamHandler.edge(of: container)
        let vertical = edge == "left" || edge == "right"
        guard vertical != usesVerticalSearchTitle else { return }
        usesVerticalSearchTitle = vertical
        if #available(iOS 27.0, *) {
            searchPage.navigationItem.navigationBarMinimization.minimizationBehavior = .never
        }
    }

    private func syncScrollInset() {
        guard searchPage.hasCompletedAppearance, scrollView.window != nil,
              !scrollView.bounds.isEmpty,
              let inset = NativeNavigationHost.restingContentInset(for: searchPage),
              inset.isFinite, inset > 0 else { return }
        restingContentInset = inset
    }

    private func applyScrollOffset() {
        guard !hidden, tabs.selectedIndex == searchIndex else { return }
        NativeNavigationHost.trackExternalScroll(offset: holdsScrollAtRest ? 0 : scrollOffset)
    }

    private func scheduleReport() {
        guard !disposed, !reportScheduled else { return }
        reportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportScheduled = false
            self.reportLayout()
        }
    }

    private func reportLayout() {
        guard !disposed, let window = container.window, !container.bounds.isEmpty else { return }
        updateToolbarSearchPresentation()
        var bottom: CGFloat = 0
        var top: CGFloat?
        func visibleFrame(_ view: UIView) -> CGRect? {
            guard view.window === window, !view.isHidden, view.alpha > 0, !view.bounds.isEmpty else { return nil }
            let rect = view.convert(view.bounds, to: window).intersection(window.bounds)
            return rect.isNull || rect.isEmpty ? nil : rect
        }
        if !hidden {
            let edge = VerticalBarEdgeStreamHandler.edge(of: container)
            let sideBar = edge == "left" || edge == "right"
            if let rect = visibleFrame(tabs.tabBar), !sideBar { bottom = window.bounds.maxY - rect.minY }
            if tabs.selectedIndex == searchIndex {
                syncScrollInset()
                top = restingContentInset
                if #available(iOS 26.0, *), let rect = visibleFrame(search.searchBar.searchTextField) {
                    bottom = max(bottom, window.bounds.maxY - rect.minY)
                }
                if let rect = visibleFrame(searchNavigation.toolbar) { bottom = max(bottom, window.bounds.maxY - rect.minY) }
                if #unavailable(iOS 26.0), search.isActive {
                    let keyboard = tabs.view.keyboardLayoutGuide.layoutFrame
                    let rect = tabs.view.convert(keyboard, to: window)
                    bottom = max(bottom, window.bounds.maxY - rect.minY)
                }
            }
        }
        // UIKit can already shrink the hosted Flutter surface beside Duo's
        // control rail. Only report the safe area still inside that surface.
        let flutterView = pages.indices.contains(tabs.selectedIndex)
            ? pages[tabs.selectedIndex].flutter?.view : nil
        let frame = flutterView.map { $0.convert($0.bounds, to: window) } ?? window.bounds
        let safeFrame = window.bounds.inset(by: window.safeAreaInsets)
        // Extend only the custom header background into the native side lane.
        // No controls are recreated and this view never receives touches.
        let edge = VerticalBarEdgeStreamHandler.edge(of: container)
        if headerHeight > 0, let headerColor, edge == "left" || edge == "right" {
            let contentLeft = max(frame.minX, safeFrame.minX)
            let contentRight = min(frame.maxX, safeFrame.maxX)
            let x = edge == "right" ? contentRight : window.bounds.minX
            let width = edge == "right" ? window.bounds.maxX - x : contentLeft - x
            headerExtension.isUserInteractionEnabled = false
            headerExtension.accessibilityElementsHidden = true
            headerExtension.backgroundColor = headerColor
            headerExtension.frame = CGRect(x: x, y: safeFrame.minY, width: max(0, width), height: headerHeight)
            if headerExtension.superview !== window { window.addSubview(headerExtension) }
        } else {
            headerExtension.removeFromSuperview()
        }
        let result: [String: Any] = [
            "safeLeft": Double(max(0, safeFrame.minX - frame.minX)),
            "safeRight": Double(max(0, frame.maxX - safeFrame.maxX)),
            "safeTop": Double(max(0, safeFrame.minY - frame.minY)),
            "bottom": Double(bottom), "top": top.map { Double($0) } as Any? ?? NSNull(),
            "synchronousSearchChrome": true, "regions": []
        ]
        let value = result as NSDictionary
        if lastLayout != value { lastLayout = value; channel.invokeMethod("layout", arguments: result) }
        notifySelection()
    }

    private func notifySelection() {
        let index = tabs.selectedIndex
        guard pages.indices.contains(index), index != lastNotifiedIndex else { return }
        selectHostedContent()
        lastNotifiedIndex = index
        if index != searchIndex { previousContentIndex = index }
        channel.invokeMethod("selected", arguments: index)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if let target = tabs.tabs.firstIndex(where: { $0 === tab }), target == searchIndex { prepareSearchPresentation() }
        return true
    }
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        selectHostedContent()
        notifySelection()
        scheduleReport()
    }
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        selectHostedContent()
        notifySelection()
        scheduleReport()
    }

    func updateSearchResults(for searchController: UISearchController) {
        guard !disposed, !synchronizingQuery, !hidden,
              !preservingQueryDuringDismissal else { return }
        acceptQuery(searchController.searchBar.text ?? "")
    }
    private func acceptQuery(_ text: String) {
        guard text != query else { return }
        query = text
        channel.invokeMethod("changed", arguments: text)
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !disposed, !synchronizingQuery, !hidden else { return }
        // UIKit identifies actual edits, including its clear button, through
        // this delegate even before an inactive search becomes presented.
        preservingQueryDuringDismissal = false
        acceptQuery(searchText)
    }
    private func restoreQuery() {
        guard search.searchBar.text != query else { return }
        synchronizingQuery = true
        search.searchBar.text = query
        synchronizingQuery = false
    }
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        restoreQuery()
        return true
    }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        dismissingForNavigation = false
        preservingQueryDuringDismissal = false
        guard !query.isEmpty else { return }
        query = ""
        channel.invokeMethod("changed", arguments: query)
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        channel.invokeMethod("submitted", arguments: searchBar.text ?? "")
    }
    func willPresentSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchWillPresent(searchController)
        preservingQueryDuringDismissal = false
        restoreQuery()
        if usesToolbarSearch { setTabBarHidden(true) }
        scheduleReport()
    }
    func didPresentSearchController(_ searchController: UISearchController) {
        NativeNavigationHost.searchDidPresent(searchController)
        if usesToolbarSearch { searchController.searchBar.becomeFirstResponder() }
        holdsScrollAtRest = false
        applyScrollOffset()
        scheduleReport()
    }
    private func prepareSearchPresentation() {
        guard #available(iOS 26.0, *), !search.isActive else { return }
        holdsScrollAtRest = !usesToolbarSearch
        applyScrollOffset()
    }
    func willDismissSearchController(_ searchController: UISearchController) {
        dismissingForNavigation = dismissingForNavigation || hidden || NativeNavigationHost.isSearchNavigationHandoff(searchController)
        NativeNavigationHost.searchWillDismiss(searchController)
        preservingQueryDuringDismissal = !query.isEmpty
        scheduleReport()
    }
    func didDismissSearchController(_ searchController: UISearchController) {
        let navigationHandoff = dismissingForNavigation
        dismissingForNavigation = false
        preservingQueryDuringDismissal = false
        restoreQuery()
        if usesToolbarSearch {
            setTabBarHidden(hidden)
            if !navigationHandoff && !hidden && tabs.selectedIndex == searchIndex {
                tabs.selectedIndex = previousContentIndex
                toolbarSearchVisible = false
                selectHostedContent()
                notifySelection()
            }
        }
        holdsScrollAtRest = false
        applyScrollOffset()
        scheduleReport()
        NativeNavigationHost.searchDidDismiss(searchController)
    }

    private func detach() {
        guard !disposed else { return }
        disposed = true
        headerExtension.removeFromSuperview()
        search.delegate = nil
        search.searchResultsUpdater = nil
        search.searchBar.delegate = nil
        search.isActive = false
        setTabBarHidden(true)
        tabs.delegate = nil
        NativeNavigationHost.detachTabs(tabs)
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
    }
    deinit { detach(); channel.setMethodCallHandler(nil) }
}
