import Flutter
import UIKit

final class NativeNavigationHost {
    static var installed: NativeNavigationHost?
    static var installing = false
    static var pending: [(NativeNavigationHost) -> Void] = []
    static var routeChannel: FlutterMethodChannel?
    static var drawerChannel: FlutterMethodChannel?
    weak var page: NativeNavigationPage?
    let flutter: FlutterViewController
    var content: NativeNavigationContent
    let navigation: NativeNavigationController
    var tabs: UITabBarController?
    weak var externalNavigation: UINavigationController?
    weak var regularNavigation: UINavigationController?
    weak var outgoingPage: NativeNavigationPage?
    weak var pendingBackPage: NativeNavigationPage?
    /// A replacement anchor for the route being revealed by a pop. Rotating
    /// Duo rebuilds a covered page's anchor, so its original page is gone.
    weak var poppingTargetPage: NativeNavigationPage?
    weak var dismissingSearch: UISearchController?
    weak var geometrySearch: UISearchController?
    weak var geometryContent: NativeNavigationContent?
    var geometryStartInset: CGFloat = 0
    var geometryStartOrigin: CGFloat?
    var geometryOriginContext: String?
    var searchPresentationTransition = false
    var keyboardTransition = false
    var keyboardObservers: [NSObjectProtocol] = []
    var contentPages: [ObjectIdentifier: NativePageState] = [:]
    var pageStates: [ObjectIdentifier: NativePageState] = [:]
    var externalOrigins: [String: CGFloat] = [:]
    var originContext: String?
    var originGeometryKey: String?
    var externalOffset: CGFloat = 0
    weak var window: UIWindow?
    var restingInset: CGFloat?
    var scheduled = false
    var layingOut = false
    var waitingForNavigationTransition = false
    var deferredRestoredMeasurement = false
    var movingContent = false
    var movementGeneration = 0
    var managedRoutes: [NativeRouteState] = []
    weak var managedNavigation: NativeNavigationController?
    var pendingPush: PendingNativePush?
    var preparingPop = false
    var measuringRestoredPage = false
    var synchronizingNativeStack = false
    var pushCompletion: FlutterResult?
    var popCompletion: FlutterResult?
    var deferredTabSelection: (NativeNavigationContent, UINavigationController?, UINavigationController?)?
    var routePopPermissions: [String: Bool] = [:]
    var appliedTints: [ObjectIdentifier: UIColor?] = [:]
    var sharedAppearanceKeys: [ObjectIdentifier: String] = [:]
    var clearScrollEdgeAppearances: [ObjectIdentifier: (base: UINavigationBarAppearance, clear: UINavigationBarAppearance)] = [:]
    var defaultBarAppearances: [ObjectIdentifier: (UINavigationBarAppearance, UINavigationBarAppearance?,
                                                           UINavigationBarAppearance?, UINavigationBarAppearance?)] = [:]
    var rootContent: UIViewController { tabs ?? content }

    init(flutter: FlutterViewController, window: UIWindow) {
        self.flutter = flutter
        self.window = window
        content = NativeNavigationContent(flutter: flutter)
        navigation = NativeNavigationController(rootViewController: content)
        navigation.interactivePopGestureRecognizer?.isEnabled = false
        navigation.completedLayout = { [weak self] in self?.scheduleLayout() }
        navigation.requestedBack = { [weak self] in self?.page?.nativeNavigationBack() }
        navigation.completedNavigation = { [weak self] navigation, controller in
            self?.completedNativeNavigation(navigation, controller: controller)
        }
        content.becameVisible = { [weak self] in self?.restoreAppearance() }
        keyboardObservers = [
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, let search = self.content.navigationItem.searchController,
                      search.isActive, self.dismissingSearch !== search else { return }
                self.beginSearchGeometry(search, keyboard: true)
            },
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, let search = self.geometrySearch else { return }
                self.endSearchGeometry(search, keyboard: true)
            }
        ]
    }

    static func registerNavigation(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "adaptive_platform_ui/navigation", binaryMessenger: messenger)
        routeChannel = channel
        drawerChannel = FlutterMethodChannel(name: "adaptive_platform_ui/drawer", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            guard let host = installed else { result(false); return }
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "presentDrawer":
                guard host.drawer == nil, let window = host.window else { result(nil); return }
                let drawerContent = host.content
                let drawer = NativeDrawer(parameters: args) { [weak host] selection in
                    drawerContent.drawerStatusBarStyle = nil
                    drawerContent.setNeedsStatusBarAppearanceUpdate()
                    host?.drawer = nil
                    result(selection)
                }
                if window.safeAreaInsets.top > 0 {
                    drawerContent.drawerStatusBarStyle = drawer.statusBarStyle
                    drawerContent.setNeedsStatusBarAppearanceUpdate()
                }
                host.drawer = drawer
                drawer.present(in: window)
            case "setDrawerCover":
                guard let window = host.window else { result(nil); return }
                let cover: NativeDrawerCover
                if let existing = host.drawerCover {
                    cover = existing
                } else {
                    let background = UIColor(argb: args["background"] as? Int ?? 0xFFFFFFFF)
                    cover = NativeDrawerCover(background: background)
                    cover.frame = window.bounds
                    cover.tapped = { drawerChannel?.invokeMethod("tapped", arguments: nil) }
                    window.addSubview(cover)
                    // Every view that shares a container with Flutter's
                    // is a bar or its backdrop (the navigation bar, what
                    // sits behind the status bar, the tab bar). Walk up
                    // from Flutter's view and take each level's others.
                    var bars: [UIView] = []
                    var branch: UIView = host.flutter.view
                    while let parent = branch.superview, parent !== window {
                        bars += parent.subviews.filter { $0 !== branch && $0 !== cover }
                        branch = parent
                    }
                    // Platform views (the Duo's bar) sit inside Flutter's
                    // own view, above what Flutter draws.
                    let flutterView: UIView = host.flutter.view
                    bars += flutterView.subviews.filter {
                        let name = String(describing: type(of: $0))
                        return !name.contains("Overlay") && !name.contains("EdgeObserver")
                    }
                    cover.mask(bars)
                    host.drawerCover = cover
                    if window.safeAreaInsets.top > 0 {
                        host.content.drawerStatusBarStyle = cover.statusBarStyle
                        host.content.setNeedsStatusBarAppearanceUpdate()
                    }
                }
                cover.update(
                    x: CGFloat(args["x"] as? Double ?? 0),
                    width: CGFloat(args["width"] as? Double ?? 320))
                result(nil)
            case "clearDrawerCover":
                host.drawerCover?.restore()
                host.drawerCover?.removeFromSuperview()
                host.drawerCover = nil
                host.content.drawerStatusBarStyle = nil
                host.content.setNeedsStatusBarAppearanceUpdate()
                result(nil)
            case "dismissDrawer":
                host.drawer?.dismiss(selection: nil)
                result(nil)
            case "preparePush": host.prepareNativePush(args, result: result)
            case "preparePop": host.prepareNativePop(args); result(nil)
            case "syncStack": host.synchronizeNativeStack(args, result: result)
            case "routeShown": host.showNativeRoute(args, result: result)
            case "setPopEnabled":
                if let identifier = args["routeId"] as? String {
                    let enabled = args["enabled"] as? Bool ?? true
                    host.routePopPermissions[identifier] = enabled
                    host.managedRoutes.first(where: { $0.identifier == identifier })?.popEnabled = enabled
                    if identifier == host.managedRoutes.last?.identifier {
                        host.managedRoutes.last?.popEnabled = enabled
                        host.managedNavigation?.routePopEnabled = enabled
                        host.content.navigationItem.hidesBackButton = !enabled
                    }
                }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    static func connect(_ page: NativeNavigationPage, from anchor: UIView) {
        if let host = installed {
            if host.movingContent {
                DispatchQueue.main.async { [weak page, weak anchor] in
                    guard let page, let anchor, anchor.window != nil else { return }
                    connect(page, from: anchor)
                }
                return
            }
            host.activate(page)
            return
        }
        pending.append { [weak page] host in if let page { host.activate(page) } }
        install(from: anchor)
    }

    static func makeNavigationController(content: NativeNavigationContent,
                                         onLayout: (() -> Void)? = nil) -> UINavigationController {
        let controller = NativeNavigationController(rootViewController: content)
        controller.navigationBar.prefersLargeTitles = content.navigationItem.largeTitleDisplayMode != .never
        controller.hidesBarsOnSwipe = false
        controller.hidesBarsOnTap = false
        controller.hidesBarsWhenKeyboardAppears = false
        controller.interactivePopGestureRecognizer?.isEnabled = false
        controller.view.backgroundColor = .systemBackground
        controller.completedLayout = { installed?.scheduleLayout(); onLayout?() }
        controller.requestedBack = { installed?.page?.nativeNavigationBack() }
        return controller
    }

    static var ownsRouteTransition: Bool {
        guard let host = installed else { return false }
        return host.pendingPush != nil || host.managedRoutes.count > 1 || host.preparingPop
    }

    static func restingContentInset(for content: NativeNavigationContent) -> CGFloat? {
        guard let host = installed, host.content === content,
              host.originContext != nil, let inset = host.restingInset, inset > 0 else { return nil }
        return inset
    }

    static func trackExternalScroll(offset: CGFloat) {
        guard let host = installed, host.externalNavigation != nil else { return }
        host.externalOffset = offset
        host.layout()
    }

    static func install(from anchor: UIView) {
        guard !installing, let window = anchor.window else { return }
        var responder: UIResponder? = anchor
        var flutter: FlutterViewController?
        while let current = responder {
            if let candidate = current as? FlutterViewController { flutter = candidate; break }
            responder = current.next
        }
        guard let flutter, window.rootViewController === flutter else { return }
        installing = true
        DispatchQueue.main.async { [weak anchor, weak flutter, weak window] in
            defer { installing = false }
            guard let anchor, let flutter, let window, anchor.window != nil,
                  window.rootViewController === flutter else { return }
            // UIKit completes the original root disappearance. The package
            // content forwards a new appearance only after its own didAppear.
            let host = NativeNavigationHost(flutter: flutter, window: window)
            installed = host
            window.rootViewController = host.navigation
            host.navigation.view.backgroundColor = .systemBackground
            let operations = pending
            pending.removeAll()
            for operation in operations { operation(host) }
        }
    }

    static func update(_ page: NativeNavigationPage) {
        guard let host = installed, host.page === page, !host.movingContent else { return }
        host.configure(page)
        host.layout()
    }
    /// Puts a page's title view on the bar showing it right away, including
    /// mid-push, when `configure` is held back until the transition ends.
    static func setTitleView(_ page: NativeNavigationPage, _ view: UIView?) {
        guard let host = installed, host.page === page else { return }
        let destination = host.content
        destination.navigationItem.titleView = view
    }
    static func scroll(_ page: NativeNavigationPage) {
        guard let host = installed, host.page === page else { return }
        host.layout()
    }
    static func deactivate(_ page: NativeNavigationPage) {
        guard let host = installed else { return }
        if host.pendingPush != nil || host.preparingPop || host.managedRoutes.count > 1 {
            // Route anchors can deactivate before UIKit has completed its
            // transition. Their real navigation items remain on the stack.
            return
        }
        if host.pendingBackPage === page { host.pendingBackPage = nil }
        guard host.page === page else { return }
        host.page = nil
        host.coveredPage = nil
        host.applyCovered(animated: false)
        (host.regularNavigation ?? host.navigation).setNavigationBarHidden(true, animated: false)
    }

    /// A Flutter sheet or dialog covers the page: keep its bar on screen,
    /// with dimmed tint and no touches, as UIKit leaves a bar behind a sheet.
    static func setCovered(_ page: NativeNavigationPage, _ covered: Bool) {
        guard let host = installed else { return }
        // A page can report being uncovered after it stopped being current,
        // for example while its route is popped back into view; that must
        // still clear its flag.
        if !covered, host.coveredPage === page { host.coveredPage = nil }
        guard host.page === page else { return }
        if covered { host.coveredPage = page }
        host.applyCovered(animated: true)
    }

    /// The page that reported a Flutter sheet or dialog over it. Kept per
    /// page so a pushed page never inherits its predecessor's covering,
    /// which left the bar of a search page without touches.
    weak var coveredPage: NativeNavigationPage?
    /// Whether a Flutter sheet or dialog covers the current page.
    var covered: Bool { coveredPage != nil && coveredPage === page }
    var drawer: NativeDrawer?
    var drawerCover: NativeDrawerCover?

    /// UIKit resets a bar's tint adjustment when first responders change
    /// (a text field in the sheet taking focus), so this is reapplied on
    /// every layout pass, not only when the covered state changes.
    func applyCovered(animated: Bool) {
        let bar = (regularNavigation ?? navigation).navigationBar
        bar.isUserInteractionEnabled = !covered
        let mode: UIView.TintAdjustmentMode = covered ? .dimmed : .automatic
        guard bar.tintAdjustmentMode != mode else { return }
        if animated {
            UIView.animate(withDuration: 0.22) { bar.tintAdjustmentMode = mode }
        } else {
            bar.tintAdjustmentMode = mode
        }
    }

    func restoreAppearance() {
        let generation = movementGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.movementGeneration,
                  self.flutter.parent === self.content, self.flutter.view.window != nil,
                  self.content.hasCompletedAppearance else { return }
            self.content.completeFlutterAppearance()
            self.flutter.view.setNeedsLayout()
            self.layout()
        }
    }

    func activate(_ next: NativeNavigationPage) {
        if let pendingPush {
            if next !== managedRoutes.last?.page {
                pendingPush.incomingPage = next
                page = next
                if let completion = pendingPush.shownCompletion {
                    pendingPush.shownCompletion = nil
                    let identifier = pendingPush.identifier
                    DispatchQueue.main.async { [weak self, weak pendingPush] in
                        guard let self, let pendingPush, self.pendingPush === pendingPush else {
                            completion(false)
                            return
                        }
                        self.showNativeRoute(["routeId": identifier], result: completion)
                    }
                }
            }
            return
        }
        if preparingPop {
            // Do not rewrite the outgoing native item as Dart reveals the
            // target underneath its retained content image.
            if next !== managedRoutes.last?.page { poppingTargetPage = next }
            return
        }
        // An outgoing anchor can reconnect before Flutter consumes the native
        // search selection. It must not reclaim the selected search controller.
        if outgoingPage === next, page !== next,
           contentPages[ObjectIdentifier(content)]?.page !== next { return }
        if externalNavigation != nil {
            if next.nativeNeedsBack { pendingBackPage = next }
            return
        }
        let changed = page !== next
        page = next
        remember(next)
        if changed { originContext = nil }
        configure(next)
        layout()
    }

    func remember(_ next: NativeNavigationPage) {
        let identifier = ObjectIdentifier(next)
        let state: NativePageState
        if let existing = pageStates[identifier], existing.page === next { state = existing }
        else { state = NativePageState(next); pageStates[identifier] = state }
        contentPages[ObjectIdentifier(content)] = state
    }

    func configure(_ page: NativeNavigationPage) {
        guard pendingPush == nil, !preparingPop else { return }
        guard externalNavigation == nil else { return }
        let navigation = regularNavigation ?? self.navigation
        guard (navigation as? NativeNavigationController)?.transitioningBetweenRoutes != true else { return }
        let source = page.nativeNavigationItem
        let destinationController: UIViewController = tabs == nil ? rootContent : content
        // The platform anchor may arrive after routeShown. Once it supplies
        // a native bar, cancellation must restore that bar on this controller.
        (destinationController as? NativeNavigationContent)?.hidesNativeNavigationBar = false
        let destination = destinationController.navigationItem
        let changesSearchOwner = destination.searchController !== source.searchController
        if changesSearchOwner, let previousSearch = destination.searchController,
           previousSearch.isActive || previousSearch.isBeingPresented || previousSearch.isBeingDismissed || dismissingSearch === previousSearch {
            dismissSearchForHandoff(previousSearch)
            return
        }
        if tabs != nil, !self.navigation.isNavigationBarHidden {
            self.navigation.setNavigationBarHidden(true, animated: false)
        }
        // Flutter republishes a page on every rebuild. Write only what changed:
        // reassigning identical bar state (traits, tint, search placement,
        // visibility) makes UIKit rebuild the bar and restart the search
        // field's glass, which a native app never does.
        let style: UIUserInterfaceStyle = page.nativeDark ? .dark : .light
        // A controller override would feed the app's previous brightness back
        // into Flutter and prevent ThemeMode.system from seeing an OS change.
        assign(navigation, \.overrideUserInterfaceStyle, .unspecified)
        assign(navigation.navigationBar, \.overrideUserInterfaceStyle, style)
        assign(navigation.toolbar, \.overrideUserInterfaceStyle, style)
        assign(navigation.view, \.backgroundColor, UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style)))
        content.setNativeBackground(style: style)
        let tintKey = ObjectIdentifier(navigation)
        if appliedTints[tintKey] != .some(page.nativeTint) {
            navigation.view.tintColor = page.nativeTint
            appliedTints[tintKey] = page.nativeTint
        }
        // This is the navigation controller's capability, not the current
        // page's title mode. Keep it enabled throughout a native route stack;
        // each real navigation item chooses .always, .inline or .never. In
        // particular Search's .inline large title must survive a compact
        // detail push so UIKit can morph it during interactive Back.
        assign(navigation.navigationBar, \.prefersLargeTitles,
               managedNavigation === navigation || page.nativeLargeTitle)
        assign(destinationController, \.definesPresentationContext, true)
        if changesSearchOwner {
            destination.searchController?.isActive = false
            destination.searchController = source.searchController
        }
        assign(destination, \.hidesSearchBarWhenScrolling, source.hidesSearchBarWhenScrolling)
        if #available(iOS 16.0, *) {
            assign(destination, \.preferredSearchBarPlacement, source.preferredSearchBarPlacement)
        }
        if #available(iOS 26.0, *) {
            assign(destination, \.searchBarPlacementAllowsToolbarIntegration,
                   source.searchBarPlacementAllowsToolbarIntegration)
        }
        let largeTitleInContent: Bool
        if #available(iOS 26.0, *) { largeTitleInContent = page.nativeLargeTitle } else { largeTitleInContent = false }
        applySharedAppearance(source, to: navigation)
        let largeTitleColor = largeTitleInContent ? source.standardAppearance?.backgroundColor : nil
        (destinationController as? NativeNavigationContent)?.setLargeTitleColor(largeTitleColor)
        assign(destination, \.standardAppearance, nil)
        // Only this page's item stays clear at the scroll edge, so the shared
        // opaque bar returns as soon as another page takes over.
        assign(destination, \.scrollEdgeAppearance,
               largeTitleColor == nil ? nil : clearScrollEdgeAppearance(for: navigation.navigationBar))
        assign(destination, \.compactAppearance, nil)
        assign(destination, \.compactScrollEdgeAppearance, nil)
        assign(destination, \.title, source.title)
        assign(destination, \.titleView, source.titleView)
        assign(destination, \.leftBarButtonItems, source.leftBarButtonItems)
        assign(destination, \.rightBarButtonItems, source.rightBarButtonItems)
        assign(destination, \.hidesBackButton, managedRoutes.last?.content === destinationController
            ? !(managedRoutes.last?.popEnabled ?? true) : false)
        assign(destination, \.largeTitleDisplayMode, page.nativeLargeTitle ? .always : .never)
        if #available(iOS 27.0, *) {
            let current = destination.navigationBarMinimization.minimizationBehavior
            if page.nativeVerticalNavigation, current != .never {
                destination.navigationBarMinimization.minimizationBehavior = .never
            } else if !page.nativeVerticalNavigation, current != .automatic {
                destination.navigationBarMinimization.minimizationBehavior = .automatic
            }
        }
        if managedRoutes.count > 1, managedRoutes.last?.content === destinationController {
            // A real native controller stack supplies Back and its gesture.
        } else if page.nativeNeedsBack {
            if navigation.viewControllers.count == 1 {
                let previous = UIViewController()
                previous.navigationItem.backButtonDisplayMode = .minimal
                navigation.setViewControllers([previous, destinationController], animated: false)
            }
        } else if navigation.viewControllers.count > 1 {
            navigation.setViewControllers([destinationController], animated: false)
        }
        // Once search is attached, UIKit owns hiding/restoring the bar during
        // presentation. Reasserting visibility in its callbacks interrupts it.
        if navigation.isNavigationBarHidden, source.searchController == nil || changesSearchOwner {
            navigation.setNavigationBarHidden(false, animated: false)
        }
    }

    /// Applies a page's bar appearance to the navigation bar itself. When it
    /// lives on each navigation item, UIKit cross-fades the bar background
    /// between identical items on every push and pop; on Duo that exposes the
    /// page behind the vertical bar's status glass, which flashes light.
    /// The shared bar's appearance without its background, for a page whose
    /// content draws the bar colour behind an iOS 26+ large title. Cached
    /// so republishing the page never hands UIKit a new instance.
    func clearScrollEdgeAppearance(for bar: UINavigationBar) -> UINavigationBarAppearance {
        let key = ObjectIdentifier(bar)
        if let cached = clearScrollEdgeAppearances[key], cached.base === bar.standardAppearance {
            return cached.clear
        }
        let clear = bar.standardAppearance.copy()
        clear.configureWithTransparentBackground()
        clearScrollEdgeAppearances[key] = (bar.standardAppearance, clear)
        return clear
    }

    func applySharedAppearance(_ source: UINavigationItem, to navigation: UINavigationController) {
        let bar = navigation.navigationBar
        let barKey = ObjectIdentifier(bar)
        let key = source.standardAppearance.map {
            "\($0.backgroundColor?.description ?? "-")|\(($0.titleTextAttributes[.foregroundColor] as? UIColor)?.description ?? "-")|\($0.shadowImage != nil)|\(($0.titleTextAttributes[NativeBarAppearance.titleFontKey] as? UIFont)?.fontName ?? "-")|\(($0.titleTextAttributes[NativeBarAppearance.titleFontKey] as? UIFont)?.pointSize ?? 0)"
        } ?? ""
        guard sharedAppearanceKeys[barKey] != key else { return }
        if defaultBarAppearances[barKey] == nil {
            defaultBarAppearances[barKey] = (bar.standardAppearance, bar.scrollEdgeAppearance,
                                             bar.compactAppearance, bar.compactScrollEdgeAppearance)
        }
        sharedAppearanceKeys[barKey] = key
        if let appearance = source.standardAppearance {
            let styled = AdaptiveNativeFonts.styled(appearance)
            bar.standardAppearance = styled
            bar.scrollEdgeAppearance = styled
            bar.compactAppearance = styled
            bar.compactScrollEdgeAppearance = styled
            (navigation as? NativeNavigationController)?.sharedBarColor = appearance.backgroundColor
        } else if let defaults = defaultBarAppearances[barKey] {
            bar.standardAppearance = defaults.0
            bar.scrollEdgeAppearance = defaults.1
            bar.compactAppearance = defaults.2
            bar.compactScrollEdgeAppearance = defaults.3
            (navigation as? NativeNavigationController)?.sharedBarColor = nil
        }
    }

}
