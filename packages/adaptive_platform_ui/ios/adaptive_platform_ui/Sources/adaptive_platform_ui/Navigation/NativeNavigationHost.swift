import Flutter
import UIKit

protocol NativeNavigationPage: AnyObject {
    var nativeNavigationItem: UINavigationItem { get }
    var nativeLargeTitle: Bool { get }
    var nativeVerticalNavigation: Bool { get }
    var nativeNeedsBack: Bool { get }
    var nativeScrollOffset: CGFloat { get }
    var nativeDark: Bool { get }
    var nativeTint: UIColor? { get }
    func nativeNavigationLayout(contentInset: CGFloat, barBottom: CGFloat)
    func nativeNavigationBack()
}

private final class NativeFlutterScrollView: UIScrollView {
    let viewport = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(viewport)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if contentSize == .zero, !bounds.isEmpty {
            let initialSize = CGSize(width: bounds.width, height: bounds.height * 2)
            contentSize = initialSize
        }
        // Flutter draws its own list offset. Its actual surface stays stationary
        // within the native scroll viewport, where UIKit can filter real pixels.
        viewport.frame = bounds
        viewport.subviews.first?.frame = viewport.bounds
    }
}

/// A real native content scroll view used by regular tabs and the search tab.
/// Only the selected instance contains the application's single Flutter surface.
final class NativeNavigationContent: UIViewController {
    private let backingScroll = NativeFlutterScrollView(frame: .zero)
    var scroll: UIScrollView { backingScroll }
    private(set) var flutter: FlutterViewController?
    var becameVisible: (() -> Void)?
    var nativeMetricsChanged: ((CGFloat, CGFloat) -> Void)?
    private(set) var hasCompletedAppearance = false
    private var flutterAppeared = false
    private var forwardingAppearance = false
    private var forwardingDisappearance = false
    private var retainedContent: UIView?
    private var searchTransitionGlass: UIVisualEffectView?

    // During an iOS 26+ push UIKit portals the search text, but installs the
    // field's glass only when it restores the live search bar. Carry a native
    // glass material with the incoming content until that handoff completes.
    // The UISearchController and navigation bar remain entirely UIKit-owned.
    func prepareSearchTransitionGlass() {
        guard #available(iOS 26.0, *), searchTransitionGlass == nil,
              let search = navigationItem.searchController, !search.isActive else { return }
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glass.cornerConfiguration = .capsule()
        glass.isUserInteractionEnabled = false
        glass.accessibilityElementsHidden = true
        glass.overrideUserInterfaceStyle = search.searchBar.overrideUserInterfaceStyle
        backingScroll.viewport.addSubview(glass)
        searchTransitionGlass = glass
    }
    func layoutSearchTransitionGlass() {
        guard let glass = searchTransitionGlass, let field = navigationItem.searchController?.searchBar.searchTextField,
              !field.bounds.isEmpty, field.window != nil else { return }
        backingScroll.layoutIfNeeded()
        glass.frame = field.convert(field.bounds, to: backingScroll.viewport)
    }
    func finishSearchTransitionGlass() {
        // Let UIKit restore the live field in this transaction before removing
        // the temporary material. No duration guess or delayed timer is used.
        DispatchQueue.main.async { [weak self] in
            self?.searchTransitionGlass?.removeFromSuperview()
            self?.searchTransitionGlass = nil
        }
    }
    var coordinatesManagedTransition = false
    var transitionHeaderColor: UIColor?
    var transitionPageColor: UIColor?
    var transitionHeaderHeight: CGFloat = 0 {
        didSet {
            if #available(iOS 26.0, *) {
                // A solid custom header already separates content from the
                // status area; native scroll-edge shading washes out its red.
                backingScroll.topEdgeEffect.isHidden = transitionHeaderHeight > 0
            }
        }
    }
    var hidesNativeNavigationBar = false
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
    var drawerStatusBarStyle: UIStatusBarStyle?
    /// Flutter's style when it last left this page. A revealed page has no
    /// Flutter child until its pop completes; without this the status bar
    /// falls back to the default style for the whole transition.
    private var retainedStatusBarStyle: UIStatusBarStyle?
    override var childForStatusBarStyle: UIViewController? {
        drawerStatusBarStyle == nil && flutter != nil ? flutter : nil
    }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        drawerStatusBarStyle ?? retainedStatusBarStyle ?? super.preferredStatusBarStyle
    }
    override var childForStatusBarHidden: UIViewController? { flutter }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        flutter?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        flutter?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }

    init(flutter: FlutterViewController? = nil) {
        self.flutter = flutter
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = backingScroll
        backingScroll.backgroundColor = .systemBackground
        backingScroll.panGestureRecognizer.isEnabled = false
        // The native scroll view observes Flutter's position; it must not
        // delay or cancel the real Flutter view's gesture stream.
        backingScroll.delaysContentTouches = false
        backingScroll.canCancelContentTouches = false
        backingScroll.showsVerticalScrollIndicator = false
        backingScroll.showsHorizontalScrollIndicator = false
        backingScroll.scrollsToTop = false
        backingScroll.alwaysBounceVertical = true
        backingScroll.contentInsetAdjustmentBehavior = .automatic
        setContentScrollView(backingScroll, for: .all)
        definesPresentationContext = true
        if let flutter { attachFlutter(flutter) }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (navigationController as? NativeNavigationController)?.usesManagedRoutes == true {
            navigationController?.setNavigationBarHidden(hidesNativeNavigationBar, animated: animated)
        }
        // UIKit reverses a cancelled disappearance through will/didAppear.
        // Reverse the pending child transition before ending it; completing
        // the disappearance here would tear down Flutter's render surface.
        if forwardingDisappearance {
            flutter?.beginAppearanceTransition(true, animated: animated)
            forwardingDisappearance = false
            forwardingAppearance = true
        }
        if coordinatesManagedTransition, !flutterAppeared, !forwardingAppearance,
           let flutter {
            flutter.beginAppearanceTransition(true, animated: animated)
            forwardingAppearance = true
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if forwardingAppearance {
            flutter?.endAppearanceTransition()
            forwardingAppearance = false
            flutterAppeared = true
        }
        hasCompletedAppearance = true
        becameVisible?()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hasCompletedAppearance = false
        if forwardingAppearance {
            flutter?.beginAppearanceTransition(false, animated: animated)
            forwardingAppearance = false
            forwardingDisappearance = true
            flutterAppeared = false
        }
        if flutterAppeared, let flutter {
            flutter.beginAppearanceTransition(false, animated: animated)
            forwardingDisappearance = true
            flutterAppeared = false
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finishSearchTransitionGlass()
        if forwardingDisappearance { flutter?.endAppearanceTransition(); forwardingDisappearance = false }
    }
    func completeFlutterAppearance() {
        guard hasCompletedAppearance, !flutterAppeared, !forwardingDisappearance,
              let flutter, flutter.view.window != nil else { return }
        flutter.beginAppearanceTransition(true, animated: false)
        flutter.endAppearanceTransition()
        flutterAppeared = true
    }
    func attachFlutter(_ controller: FlutterViewController) {
        loadViewIfNeeded()
        flutter = controller
        if controller.parent !== self {
            addChild(controller)
            backingScroll.viewport.addSubview(controller.view)
            controller.view.frame = backingScroll.viewport.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.didMove(toParent: self)
        }
        setNeedsStatusBarAppearanceUpdate()
        backingScroll.setNeedsLayout()
        backingScroll.layoutIfNeeded()
    }
    func detachFlutter() {
        guard let controller = flutter, controller.parent === self else { flutter = nil; return }
        retainedStatusBarStyle = controller.preferredStatusBarStyle
        if forwardingAppearance { controller.endAppearanceTransition(); forwardingAppearance = false; flutterAppeared = true }
        if forwardingDisappearance { controller.endAppearanceTransition(); forwardingDisappearance = false }
        if flutterAppeared {
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
            flutterAppeared = false
        }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        flutter = nil
    }
    /// Retain only page pixels. UIKit continues to own and animate its bars.
    func retainRenderedContent() {
        guard retainedContent == nil, let flutter,
              let snapshot = flutter.view.snapshotView(afterScreenUpdates: false) else { return }
        snapshot.frame = backingScroll.viewport.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Until Dart has restored this page, its retained image must not send
        // touches through to the outgoing route still on the Flutter surface.
        snapshot.isUserInteractionEnabled = true
        snapshot.accessibilityElementsHidden = true
        backingScroll.viewport.addSubview(snapshot)
        retainedContent = snapshot
    }
    func revealRenderedContent() {
        retainedContent?.removeFromSuperview()
        retainedContent = nil
    }
    func keepRetainedContentInFront() {
        if let retainedContent { backingScroll.viewport.bringSubviewToFront(retainedContent) }
    }
    func setNativeBackground(style: UIUserInterfaceStyle) {
        // Resolve the exposed native background without overriding traits on
        // the scroll view that contains Flutter's appearance observer.
        backingScroll.backgroundColor = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
    }
}

private final class NativeNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private let navigationSafeAreaBackground: UIView = {
        let background = UIView()
        background.isUserInteractionEnabled = false
        background.accessibilityElementsHidden = true
        return background
    }()

    var completedLayout: (() -> Void)?
    /// Background of the appearance applied to the bar itself, shared by
    /// every page in the stack rather than carried by each navigation item.
    var sharedBarColor: UIColor? { didSet { view.setNeedsLayout() } }
    private let transitionHeaderBackdrop = UIView()
    private weak var backdropContent: NativeNavigationContent?
    private weak var backdropContainer: UIView?
    var requestedBack: (() -> Void)?
    var willShowRoute: ((UIViewController) -> Void)?
    var completedNavigation: ((UINavigationController, UIViewController) -> Void)?
    private(set) var transitioningBetweenRoutes = false
    var usesManagedRoutes = false {
        didSet { updatePopGestures() }
    }
    var routePopEnabled = true { didSet { updatePopGestures() } }
    private func updatePopGestures() {
        let enabled = usesManagedRoutes && routePopEnabled
        interactivePopGestureRecognizer?.isEnabled = enabled
        if enabled { interactivePopGestureRecognizer?.delegate = self }
        if #available(iOS 26.0, *) {
            interactiveContentPopGestureRecognizer?.isEnabled = enabled
            if enabled { interactiveContentPopGestureRecognizer?.delegate = self }
        }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard usesManagedRoutes, routePopEnabled, viewControllers.count > 1,
              !transitioningBetweenRoutes, transitionCoordinator == nil else { return false }
        return true
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        updatePopGestures()
    }
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        topViewController?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }
    override func popViewController(animated: Bool) -> UIViewController? {
        if !usesManagedRoutes, viewControllers.count > 1, let requestedBack { requestedBack(); return nil }
        return super.popViewController(animated: animated)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTransitionBackdrop()
        layoutNavigationSafeAreaBackground()
        completedLayout?()
    }
    private func layoutNavigationSafeAreaBackground() {
        // The vertical navigation layout can leave a safe-area strip above
        // UIKit's opaque bar background. Continue only its colour to the edge;
        // UIKit retains full ownership of bar height, title and side controls.
        guard !isNavigationBarHidden,
              let color = topViewController?.navigationItem.standardAppearance?.backgroundColor
                ?? sharedBarColor,
              navigationBar.frame.minY > view.bounds.minY else {
            navigationSafeAreaBackground.removeFromSuperview()
            return
        }
        navigationSafeAreaBackground.backgroundColor = color
        navigationSafeAreaBackground.frame = CGRect(
            x: view.bounds.minX, y: view.bounds.minY,
            width: view.bounds.width,
            height: navigationBar.frame.minY - view.bounds.minY)
        view.insertSubview(navigationSafeAreaBackground, belowSubview: navigationBar)
    }
    private func layoutTransitionBackdrop() {
        guard let content = backdropContent,
              let color = content.transitionHeaderColor,
              content.transitionHeaderHeight > 0 else {
            transitionHeaderBackdrop.removeFromSuperview()
            return
        }
        let container = backdropContainer ?? view!
        container.backgroundColor = content.transitionPageColor ?? .systemBackground
        transitionHeaderBackdrop.backgroundColor = color
        transitionHeaderBackdrop.isUserInteractionEnabled = false
        transitionHeaderBackdrop.accessibilityElementsHidden = true
        let headerFrame = CGRect(x: 0, y: 0, width: view.bounds.width,
                                 height: view.safeAreaInsets.top + content.transitionHeaderHeight)
        transitionHeaderBackdrop.frame = view.convert(headerFrame, to: container)
        if transitionHeaderBackdrop.superview !== container {
            container.insertSubview(transitionHeaderBackdrop, at: 0)
        }
    }
    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        guard usesManagedRoutes else { return }
        transitioningBetweenRoutes = true
        willShowRoute?(viewController)
        let hidesBar = (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar ?? false
        // UIKit rounds its transition cards. The surface exposed behind a
        // custom-header root must use that page's colors, not system white.
        backdropContent = hidesBar ? viewController as? NativeNavigationContent : nil
        backdropContainer = transitionCoordinator?.containerView
        layoutTransitionBackdrop()
        // The root owns a Flutter header. Finish the native bar handoff now:
        // Duo's detached title otherwise outlives the interactive content slide.
        // Keep Flutter rebuilds from restoring the outgoing bar mid-transition.
        setNavigationBarHidden(hidesBar, animated: hidesBar ? false : animated)
        if let coordinator = transitionCoordinator {
            let source = coordinator.viewController(forKey: .from) as? NativeNavigationContent
            let sourceHidesBar = source?.transitionHeaderHeight ?? 0 > 0
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard context.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.transitioningBetweenRoutes = false
                    self.backdropContent = sourceHidesBar ? source : nil
                    self.layoutTransitionBackdrop()
                    self.setNavigationBarHidden(sourceHidesBar, animated: false)
                }
            }
        }
    }
    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        if usesManagedRoutes {
            backdropContent = (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar == true
                ? viewController as? NativeNavigationContent : nil
            layoutTransitionBackdrop()
            setNavigationBarHidden(
                (viewController as? NativeNavigationContent)?.hidesNativeNavigationBar ?? false,
                animated: false)
        }
        // didShow can precede UIKit's interactive-transition cleanup. Moving
        // the shared Flutter surface here can carry its temporary rounded mask
        // into the restored page. Keep the retained destination visible until
        // the coordinator finishes, then transfer the live surface next turn.
        let finish: () -> Void = { [weak self, weak viewController] in
            DispatchQueue.main.async { [weak self, weak viewController] in
                guard let self, let viewController,
                      self.topViewController === viewController else { return }
                self.transitioningBetweenRoutes = false
                self.completedNavigation?(self, viewController)
            }
        }
        if let coordinator = transitionCoordinator,
           coordinator.animate(alongsideTransition: nil, completion: { _ in finish() }) {
            return
        }
        finish()
    }
}

private final class NativePageState {
    weak var page: NativeNavigationPage?
    var origins: [String: CGFloat] = [:]
    init(_ page: NativeNavigationPage) { self.page = page }
}

private final class NativeRouteState {
    let identifier: String
    let content: NativeNavigationContent
    weak var page: NativeNavigationPage?
    var popEnabled = true
    init(identifier: String, content: NativeNavigationContent, page: NativeNavigationPage?) {
        self.identifier = identifier
        self.content = content
        self.page = page
    }
}

private final class PendingNativePush {
    let identifier: String
    let parentIdentifier: String
    weak var incomingPage: NativeNavigationPage?
    var shownCompletion: FlutterResult?
    var preparationCompletion: FlutterResult?
    weak var sourceSearch: UISearchController?
    var waitingForTransition = false
    init(identifier: String, parentIdentifier: String) {
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
    }
}

/// Native chrome is outside Flutter. The selected page's UIScrollView contains
/// Flutter itself; no empty mirrored view, custom blur or gradient supplies its
/// scroll-edge appearance.
/// Writes a UIKit property only when its value differs. Many UIKit setters
/// invalidate layout or restart effects even for an identical value.
private func assign<Root: AnyObject, Value: Equatable>(
    _ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>, _ value: Value) {
    if root[keyPath: keyPath] != value { root[keyPath: keyPath] = value }
}

final class NativeNavigationHost {
    private static var installed: NativeNavigationHost?
    private static var installing = false
    private static var pending: [(NativeNavigationHost) -> Void] = []
    private static var routeChannel: FlutterMethodChannel?
    private weak var page: NativeNavigationPage?
    private let flutter: FlutterViewController
    private var content: NativeNavigationContent
    private let navigation: NativeNavigationController
    private var tabs: UITabBarController?
    private weak var externalNavigation: UINavigationController?
    private weak var regularNavigation: UINavigationController?
    private weak var outgoingPage: NativeNavigationPage?
    private weak var pendingBackPage: NativeNavigationPage?
    private weak var dismissingSearch: UISearchController?
    private weak var geometrySearch: UISearchController?
    private weak var geometryContent: NativeNavigationContent?
    private var geometryStartInset: CGFloat = 0
    private var geometryStartOrigin: CGFloat?
    private var geometryOriginContext: String?
    private var searchPresentationTransition = false
    private var keyboardTransition = false
    private var keyboardObservers: [NSObjectProtocol] = []
    private var contentPages: [ObjectIdentifier: NativePageState] = [:]
    private var pageStates: [ObjectIdentifier: NativePageState] = [:]
    private var externalOrigins: [String: CGFloat] = [:]
    private var originContext: String?
    private var originGeometryKey: String?
    private var externalOffset: CGFloat = 0
    private weak var window: UIWindow?
    private var restingInset: CGFloat?
    private var scheduled = false
    private var layingOut = false
    private var waitingForNavigationTransition = false
    private var deferredRestoredMeasurement = false
    private var movingContent = false
    private var movementGeneration = 0
    private var managedRoutes: [NativeRouteState] = []
    private weak var managedNavigation: NativeNavigationController?
    private var pendingPush: PendingNativePush?
    private var preparingPop = false
    private var measuringRestoredPage = false
    private var synchronizingNativeStack = false
    private var pushCompletion: FlutterResult?
    private var popCompletion: FlutterResult?
    private var deferredTabSelection: (NativeNavigationContent, UINavigationController?, UINavigationController?)?
    private var routePopPermissions: [String: Bool] = [:]
    private var appliedTints: [ObjectIdentifier: UIColor?] = [:]
    private var sharedAppearanceKeys: [ObjectIdentifier: String] = [:]
    private var defaultBarAppearances: [ObjectIdentifier: (UINavigationBarAppearance, UINavigationBarAppearance?,
                                                           UINavigationBarAppearance?, UINavigationBarAppearance?)] = [:]
    private var rootContent: UIViewController { tabs ?? content }

    private init(flutter: FlutterViewController, window: UIWindow) {
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

    private func prepareNativePush(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let identifier = args["routeId"] as? String,
              let parent = args["parentRouteId"] as? String,
              pendingPush == nil, pushCompletion == nil, popCompletion == nil,
              let navigation = (externalNavigation ?? regularNavigation ?? self.navigation) as? NativeNavigationController else { result(false); return }
        if managedRoutes.count <= 1 {
            // Preserve the root's actual chrome policy before UIKit takes
            // ownership of pushes. Interactive back must hide a native bar
            // alongside the gesture when returning to a custom Flutter header,
            // rather than waiting for Dart to reveal the root after didShow.
            content.hidesNativeNavigationBar = content.transitionHeaderHeight > 0 ||
                page == nil || navigation.isNavigationBarHidden
            managedRoutes = [NativeRouteState(identifier: parent, content: content, page: page)]
            managedNavigation = navigation
            navigation.usesManagedRoutes = true
            navigation.completedNavigation = { [weak self] navigation, controller in
                self?.completedNativeNavigation(navigation, controller: controller)
            }
            navigation.willShowRoute = { [weak self, weak navigation] controller in
                guard let navigation else { return }
                self?.updateTabBar(for: controller, in: navigation)
            }
        }
        guard managedNavigation === navigation, managedRoutes.last?.identifier == parent else { result(false); return }
        managedRoutes.last?.page = page
        content.retainRenderedContent()
        let pending = PendingNativePush(identifier: identifier, parentIdentifier: parent)
        pendingPush = pending
        pending.preparationCompletion = result
        finishNativePushPreparation(pending)
    }

    private func finishNativePushPreparation(_ pending: PendingNativePush) {
        guard pendingPush === pending, let navigation = managedNavigation else { return }
        if let search = content.navigationItem.searchController,
           search.isActive || search.isBeingPresented || search.isBeingDismissed ||
            search.presentingViewController != nil || dismissingSearch === search {
            pending.sourceSearch = search
            dismissSearchForHandoff(search)
            return
        }
        if waitForNativeTransition(navigation, pending: pending, retry: { [weak self, weak pending] in
            guard let pending else { return }
            self?.finishNativePushPreparation(pending)
        }) { return }
        // UIKit refuses stack mutations during a presentation transition.
        // Reset any legacy placeholder only after Search has fully dismissed.
        if managedRoutes.count == 1,
           navigation.viewControllers.count != 1 || navigation.viewControllers.first !== content {
            navigation.setViewControllers([content], animated: false)
        }
        restoreAppearance()
        let completion = pending.preparationCompletion
        pending.preparationCompletion = nil
        DispatchQueue.main.async { completion?(true) }
    }

    private func waitForNativeTransition(_ navigation: UINavigationController,
                                         pending: PendingNativePush,
                                         retry: @escaping () -> Void) -> Bool {
        guard let transition = navigation.transitionCoordinator ??
                navigation.presentedViewController?.transitionCoordinator else { return false }
        guard !pending.waitingForTransition else { return true }
        pending.waitingForTransition = true
        let registered = transition.animate(alongsideTransition: nil) { [weak pending] _ in
            DispatchQueue.main.async {
                pending?.waitingForTransition = false
                retry()
            }
        }
        if !registered {
            DispatchQueue.main.async { [weak pending] in
                pending?.waitingForTransition = false
                retry()
            }
        }
        return true
    }

    private func prepareNativePop(_ args: [String: Any]) {
        guard !preparingPop, managedRoutes.count > 1,
              args["routeId"] as? String == managedRoutes.last?.identifier else { return }
        content.retainRenderedContent()
        preparingPop = true
    }

    private func synchronizeNativeStack(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let identifiers = args["routeIds"] as? [String], let target = identifiers.last else {
            result(false); return
        }
        if let pending = pendingPush, !identifiers.contains(pending.identifier) {
            // A route can be popped before its first two Flutter frames.
            // Cancel preparation instead of permanently retaining its cover.
            pending.shownCompletion?(false)
            pending.shownCompletion = nil
            pending.preparationCompletion?(false)
            pending.preparationCompletion = nil
            pendingPush = nil
            page = managedRoutes.last?.page
            pendingBackPage = nil
        }
        guard
              let index = managedRoutes.firstIndex(where: { $0.identifier == target }),
              let navigation = managedNavigation else { result(false); return }
        guard index < managedRoutes.count - 1 else { result(true); return }
        guard popCompletion == nil, pushCompletion == nil, navigation.transitionCoordinator == nil else {
            result(FlutterError(code: "navigation_busy", message: "A native navigation transition is still active.", details: nil))
            return
        }
        synchronizingNativeStack = true
        preparingPop = true
        popCompletion = result
        navigation.popToViewController(managedRoutes[index].content, animated: true)
    }

    private func showNativeRoute(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let identifier = args["routeId"] as? String else { result(false); return }
        if let pending = pendingPush, pending.identifier == identifier,
           let navigation = managedNavigation {
            if waitForNativeTransition(navigation, pending: pending, retry: { [weak self] in
                self?.showNativeRoute(args, result: result)
            }) { return }
            // Platform-view ownership reaches UIKit asynchronously. The old
            // page must never supply the destination title or navigation item.
            let incomingPage = pending.incomingPage
            guard incomingPage != nil || args["expectsNativePage"] as? Bool == false else {
                pending.shownCompletion = result
                return
            }
            let previous = content
            let next = NativeNavigationContent()
            next.coordinatesManagedTransition = true
            next.hidesNativeNavigationBar = incomingPage == nil
            next.loadViewIfNeeded()
            next.view.frame = previous.view.frame
            previous.detachFlutter()
            previous.becameVisible = nil
            content = next
            next.attachFlutter(flutter)
            next.becameVisible = { [weak self] in self?.restoreAppearance() }
            page = incomingPage
            pendingPush = nil
            deferredTabSelection = nil
            externalNavigation = nil
            pendingBackPage = nil
            outgoingPage = nil
            originContext = nil
            restingInset = nil
            movementGeneration += 1
            let state = NativeRouteState(identifier: identifier, content: next, page: incomingPage)
            state.popEnabled = routePopPermissions[identifier] ?? true
            managedRoutes.append(state)
            navigation.routePopEnabled = state.popEnabled
            // On Duo, UIKit hides the vertical tab bar by morphing its glass
            // into the leading bar controls, which flashes at the top of the
            // bar. Fade it with the push instead; see updateTabBar(for:).
            next.hidesBottomBarWhenPushed = !verticalTabs
            if let incomingPage { remember(incomingPage); configure(incomingPage) }
            next.prepareSearchTransitionGlass()
            pushCompletion = result
            navigation.pushViewController(next, animated: true)
            scheduleLayout()
            return
        }
        if managedRoutes.last?.identifier == identifier {
            content.revealRenderedContent()
            preparingPop = false
            if managedRoutes.count == 1 { managedNavigation?.usesManagedRoutes = false }
            if managedRoutes.count == 1, let selection = deferredTabSelection {
                deferredTabSelection = nil
                selectContent(selection.0, searchNavigation: selection.1, tabNavigation: selection.2)
            } else { deferredTabSelection = nil }
            if let page { configure(page) }
            restoreAppearance()
            layout()
            result(true)
            return
        }
        result(false)
    }

    private func completedNativeNavigation(_ navigation: UINavigationController, controller: UIViewController) {
        guard navigation === managedNavigation,
              let index = managedRoutes.firstIndex(where: { $0.content === controller }) else { return }
        if index == managedRoutes.count - 1 {
            if let completion = pushCompletion {
                pushCompletion = nil
                content.finishSearchTransitionGlass()
                // UIKit can report the outgoing expanded-title inset while
                // animating. It is not the destination's resting geometry.
                originContext = nil
                restingInset = nil
                if let page { pageStates[ObjectIdentifier(page)]?.origins.removeAll() }
                restoreAppearance()
                layout()
                completion(true)
            } else if let page {
                // A cancelled interactive pop keeps this route. Restore its
                // native item after UIKit finishes reversing bar visibility.
                configure(page)
                layout()
            }
            return
        }
        let poppedIdentifier = managedRoutes.last!.identifier
        let target = managedRoutes[index]
        // Moving the single Flutter surface reconnects its still-outgoing
        // anchors. Hold their ownership until Dart renders the target route.
        preparingPop = true
        movingContent = true
        content.detachFlutter()
        content.becameVisible = nil
        content = target.content
        content.attachFlutter(flutter)
        content.keepRetainedContentInFront()
        content.becameVisible = { [weak self] in self?.restoreAppearance() }
        page = target.page
        managedNavigation?.routePopEnabled = target.popEnabled
        managedRoutes.removeSubrange((index + 1)..<managedRoutes.count)
        originContext = nil
        restingInset = nil
        movementGeneration += 1
        movingContent = false
        if let page { remember(page) }
        // Measure the revealed controller before Dart renders its page again.
        // Keep outgoing anchors locked until routeShown, but publish the real
        // target inset while its retained content still covers the surface.
        measuringRestoredPage = true
        layout()
        measuringRestoredPage = false
        restoreAppearance()
        let completion = popCompletion
        popCompletion = nil
        let wasSynchronizing = synchronizingNativeStack
        synchronizingNativeStack = false
        if wasSynchronizing { completion?(true) }
        else {
            Self.routeChannel?.invokeMethod("didPop", arguments: [
                "routeId": poppedIdentifier, "targetRouteId": target.identifier
            ])
        }
    }

    /// Whether the root page lays its tabs out in Duo's vertical bar.
    private var verticalTabs: Bool {
        tabs != nil && managedRoutes.first?.page?.nativeVerticalNavigation == true
    }

    /// Hides Duo's vertical tab bar for pushed routes and shows it for the
    /// root, without UIKit's hidesBottomBarWhenPushed morph.
    private func updateTabBar(for controller: UIViewController, in navigation: UINavigationController) {
        guard #available(iOS 18.0, *), let tabs else { return }
        guard verticalTabs else {
            // A posture change can leave the regular layout in charge mid-stack.
            if tabs.isTabBarHidden, managedRoutes.count <= 1 { tabs.setTabBarHidden(false, animated: false) }
            return
        }
        let hidden = controller !== managedRoutes.first?.content
        guard tabs.isTabBarHidden != hidden else { return }
        tabs.setTabBarHidden(hidden, animated: true)
        navigation.transitionCoordinator?.animate(alongsideTransition: nil) { [weak tabs] context in
            guard context.isCancelled else { return }
            tabs?.setTabBarHidden(!hidden, animated: true)
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

    /// Install the real UITabBarController above Flutter, retaining UIKit's
    /// native tab/search placement. Platform views become channel anchors.
    static func attachTabs(tabs: UITabBarController, content: NativeNavigationContent,
                           searchNavigation: UINavigationController?, tabNavigation: UINavigationController? = nil,
                           from anchor: UIView) {
        if let host = installed {
            if host.movingContent {
                DispatchQueue.main.async { [weak tabs, weak content, weak anchor, weak searchNavigation, weak tabNavigation] in
                    guard let tabs, let content, let anchor else { return }
                    attachTabs(tabs: tabs, content: content, searchNavigation: searchNavigation,
                               tabNavigation: tabNavigation, from: anchor)
                }
                return
            }
            host.installTabs(tabs, content: content, searchNavigation: searchNavigation, tabNavigation: tabNavigation)
            return
        }
        pending.append { host in host.installTabs(tabs, content: content, searchNavigation: searchNavigation, tabNavigation: tabNavigation) }
        install(from: anchor)
    }

    static func selectTab(content: NativeNavigationContent, searchNavigation: UINavigationController?,
                          tabNavigation: UINavigationController? = nil) {
        guard let host = installed else { return }
        if host.movingContent {
            DispatchQueue.main.async { [weak content, weak searchNavigation, weak tabNavigation] in
                guard let content else { return }
                selectTab(content: content, searchNavigation: searchNavigation, tabNavigation: tabNavigation)
            }
            return
        }
        host.selectContent(content, searchNavigation: searchNavigation, tabNavigation: tabNavigation)
    }

    static func detachTabs(_ tabs: UITabBarController) {
        guard let host = installed, host.tabs === tabs else { return }
        if host.movingContent {
            DispatchQueue.main.async { [weak tabs] in if let tabs { detachTabs(tabs) } }
            return
        }
        host.movingContent = true
        host.content.detachFlutter()
        host.content.becameVisible = nil
        host.tabs = nil
        host.externalNavigation = nil
        host.regularNavigation = nil
        host.outgoingPage = nil
        let content = NativeNavigationContent()
        host.content = content
        content.attachFlutter(host.flutter)
        content.becameVisible = { [weak host] in host?.restoreAppearance() }
        host.restingInset = nil
        host.originContext = nil
        host.movementGeneration += 1
        host.navigation.setViewControllers([content], animated: false)
        host.window?.rootViewController = host.navigation
        host.movingContent = false
        if let page = host.page { host.configure(page) }
        else { host.navigation.setNavigationBarHidden(true, animated: false) }
        host.restoreAppearance()
        host.layout()
    }

    static func trackExternalScroll(offset: CGFloat) {
        guard let host = installed, host.externalNavigation != nil else { return }
        host.externalOffset = offset
        host.layout()
    }

    private static func install(from anchor: UIView) {
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
        host.covered = false
        host.applyCovered(animated: false)
        (host.regularNavigation ?? host.navigation).setNavigationBarHidden(true, animated: false)
    }

    /// A Flutter sheet or dialog covers the page: keep its bar on screen,
    /// with dimmed tint and no touches, as UIKit leaves a bar behind a sheet.
    static func setCovered(_ page: NativeNavigationPage, _ covered: Bool) {
        guard let host = installed, host.page === page else { return }
        host.covered = covered
        host.applyCovered(animated: true)
    }

    /// Whether a Flutter sheet or dialog covers the current page.
    private var covered = false
    private var drawer: NativeDrawer?

    /// UIKit resets a bar's tint adjustment when first responders change
    /// (a text field in the sheet taking focus), so this is reapplied on
    /// every layout pass, not only when the covered state changes.
    private func applyCovered(animated: Bool) {
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

    static func searchWillDismiss(_ search: UISearchController) {
        installed?.dismissingSearch = search
        installed?.cancelSearchGeometry(search)
    }

    static func searchWillPresent(_ search: UISearchController) {
        guard let host = installed else { return }
        if host.dismissingSearch === search,
           host.content.navigationItem.searchController === search,
           host.externalNavigation != nil || host.page?.nativeNavigationItem.searchController === search {
            // A return/focus starts a new native presentation. Completion from
            // the previous dismissal must not cancel this newer owner/phase.
            host.dismissingSearch = nil
        }
        host.beginSearchGeometry(search, keyboard: false)
    }

    static func searchDidPresent(_ search: UISearchController) {
        installed?.endSearchGeometry(search, keyboard: false)
    }

    static func isSearchNavigationHandoff(_ search: UISearchController) -> Bool {
        guard let host = installed else { return false }
        return host.pendingPush != nil || host.pendingBackPage != nil ||
            (host.externalNavigation == nil && host.page != nil &&
             host.page?.nativeNavigationItem.searchController !== search)
    }

    private func beginSearchGeometry(_ search: UISearchController, keyboard: Bool) {
        guard content.navigationItem.searchController === search,
              dismissingSearch !== search else { return }
        if geometrySearch !== search {
            geometrySearch = search
            geometryContent = content
            geometryStartInset = content.scroll.adjustedContentInset.top
            geometryStartOrigin = restingInset
            geometryOriginContext = originContext
            searchPresentationTransition = false
            keyboardTransition = false
        }
        if keyboard { keyboardTransition = true }
        else { searchPresentationTransition = true }
    }

    private func cancelSearchGeometry(_ search: UISearchController) {
        guard geometrySearch === search else { return }
        geometrySearch = nil
        geometryContent = nil
        searchPresentationTransition = false
        keyboardTransition = false
    }

    private func endSearchGeometry(_ search: UISearchController, keyboard: Bool) {
        guard geometrySearch === search else { return }
        if keyboard { keyboardTransition = false }
        else { searchPresentationTransition = false }
        guard !keyboardTransition, !searchPresentationTransition else { return }
        let ownsGeometry = geometryContent === content &&
            content.navigationItem.searchController === search &&
            geometryOriginContext == originContext && dismissingSearch !== search
        if ownsGeometry, let baseline = geometryStartOrigin, let context = originContext {
            let delta = content.scroll.adjustedContentInset.top - geometryStartInset
            let expandedOrigin = max(baseline, baseline + delta)
            restingInset = expandedOrigin
            if externalNavigation != nil { externalOrigins[context] = expandedOrigin }
            else if let page, let key = originGeometryKey {
                pageStates[ObjectIdentifier(page)]?.origins[key] = expandedOrigin
            }
        }
        geometrySearch = nil
        geometryContent = nil
        layout()
    }

    static func searchDidDismiss(_ search: UISearchController) {
        installed?.completeSearchDismissal(search)
    }

    private func completeSearchDismissal(_ search: UISearchController) {
        DispatchQueue.main.async { [weak self, weak search] in
            guard let self, let search, self.dismissingSearch === search else { return }
            self.cancelSearchGeometry(search)
            // A presentation may have completed after a rapid result tap.
            // Finish that native presentation before installing detail items.
            if search.presentingViewController != nil, !search.isBeingDismissed,
               !search.isActive {
                search.dismiss(animated: false) { [weak self, weak search] in
                    if let search { self?.completeSearchDismissal(search) }
                }
                return
            }
            self.dismissingSearch = nil
            if let pending = self.pendingPush, pending.sourceSearch === search {
                pending.sourceSearch = nil
                self.finishNativePushPreparation(pending)
            }
            if self.externalNavigation == nil, let page = self.page {
                self.configure(page)
            }
            self.layout()
        }
    }

    private func dismissSearchForHandoff(_ search: UISearchController) {
        dismissingSearch = search
        search.isActive = false
        if let transition = search.transitionCoordinator {
            let registered = transition.animate(alongsideTransition: nil) { [weak self, weak search] _ in
                if let search { self?.completeSearchDismissal(search) }
            }
            if registered { return }
        }
        if search.presentingViewController == nil,
           !search.isBeingPresented, !search.isBeingDismissed {
            // UIKit can cancel activation before it creates a presentation;
            // in that case there is no didDismiss delegate callback to await.
            completeSearchDismissal(search)
        } else if !search.isBeingDismissed {
            search.dismiss(animated: false) { [weak self, weak search] in
                if let search { self?.completeSearchDismissal(search) }
            }
        }
    }

    private func installTabs(_ controller: UITabBarController, content next: NativeNavigationContent,
                             searchNavigation: UINavigationController?, tabNavigation: UINavigationController?) {
        if tabs !== controller {
            // The first toolbar can arrive before the tab anchor. Transfer its
            // already measured page state into the initial native tab content.
            if let page, contentPages[ObjectIdentifier(next)] == nil,
               let state = pageStates[ObjectIdentifier(page)] {
                contentPages[ObjectIdentifier(next)] = state
            }
            movingContent = true
            content.detachFlutter()
            tabs = controller
            // Every tab now owns its own navigation controller. Keep the tab
            // controller as the window root, with no outer navigation owner
            // competing for the selected scroll view's automatic top inset.
            window?.rootViewController = controller
            movingContent = false
        }
        selectContent(next, searchNavigation: searchNavigation, tabNavigation: tabNavigation)
        if let page, searchNavigation == nil { configure(page) }
        layout()
    }

    private func selectContent(_ next: NativeNavigationContent, searchNavigation: UINavigationController?,
                               tabNavigation: UINavigationController?) {
        if pendingPush != nil || managedRoutes.count > 1 || preparingPop {
            // The tab bridge continues publishing its root while Flutter is
            // on a detail route. UIKit's top content controller owns it now.
            if searchNavigation == nil { externalNavigation = nil }
            deferredTabSelection = (next, searchNavigation, tabNavigation)
            return
        }
        movingContent = true
        let previousPage = page
        let previousExternal = externalNavigation
        let changedContent = content !== next || flutter.parent !== next
        if changedContent {
            outgoingPage = previousPage
            content.detachFlutter()
            content.becameVisible = nil
            content = next
            next.attachFlutter(flutter)
            next.becameVisible = { [weak self] in self?.restoreAppearance() }
            originContext = nil
            movementGeneration += 1
        }
        regularNavigation = tabNavigation
        externalNavigation = searchNavigation
        externalOffset = 0
        originContext = nil
        if searchNavigation != nil {
            pendingBackPage = nil
            outgoingPage = previousPage
            page = nil
        } else if previousExternal != nil, !changedContent {
            // Only the bridge's hidden transition can yield Search ownership.
            // An incoming detail anchor may already have arrived beforehand.
            page = pendingBackPage
            pendingBackPage = nil
            if let page { remember(page) }
        } else {
            pendingBackPage = nil
            // A scaffold may reuse one toolbar anchor across all regular tabs.
            // Keep it attached while Dart updates the selected title; a new
            // tab-specific anchor can still replace it when one is supplied.
            page = contentPages[ObjectIdentifier(next)]?.page
                ?? (previousExternal == nil && previousPage?.nativeNeedsBack == false ? previousPage : nil)
            if let page { remember(page) }
        }
        tabs?.setContentScrollView(next.scroll, for: .bottom)
        if tabs != nil { navigation.setNavigationBarHidden(true, animated: false) }
        if let searchNavigation {
            searchNavigation.setNavigationBarHidden(false, animated: false)
        } else if let page {
            configure(page)
        }
        movingContent = false
        window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        if #available(iOS 16.0, *) { window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        restoreAppearance()
        layout()
    }

    private func restoreAppearance() {
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

    private func activate(_ next: NativeNavigationPage) {
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

    private func remember(_ next: NativeNavigationPage) {
        let identifier = ObjectIdentifier(next)
        let state: NativePageState
        if let existing = pageStates[identifier], existing.page === next { state = existing }
        else { state = NativePageState(next); pageStates[identifier] = state }
        contentPages[ObjectIdentifier(content)] = state
    }

    private func configure(_ page: NativeNavigationPage) {
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
        applySharedAppearance(source, to: navigation)
        assign(destination, \.standardAppearance, nil)
        assign(destination, \.scrollEdgeAppearance, nil)
        assign(destination, \.compactAppearance, nil)
        assign(destination, \.compactScrollEdgeAppearance, nil)
        assign(destination, \.title, source.title)
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
    private func applySharedAppearance(_ source: UINavigationItem, to navigation: UINavigationController) {
        let bar = navigation.navigationBar
        let barKey = ObjectIdentifier(bar)
        let key = source.standardAppearance.map {
            "\($0.backgroundColor?.description ?? "-")|\(($0.titleTextAttributes[.foregroundColor] as? UIColor)?.description ?? "-")|\($0.shadowImage != nil)"
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

    private func scheduleLayout() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.layout()
        }
    }

    /// Defers measurement while UIKit animates a push or pop. Forcing layout or
    /// moving the tracked content scroll view mid-transition snaps the bar to
    /// its destination state instead of letting UIKit animate it.
    private func deferForNavigationTransition(_ navigation: UINavigationController) -> Bool {
        guard let transition = navigation.transitionCoordinator else { return false }
        if measuringRestoredPage { deferredRestoredMeasurement = true }
        if !waitingForNavigationTransition {
            waitingForNavigationTransition = true
            let registered = transition.animate(alongsideTransition: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.waitingForNavigationTransition = false
                    let measuring = self.deferredRestoredMeasurement && self.preparingPop
                    self.deferredRestoredMeasurement = false
                    self.measuringRestoredPage = measuring
                    self.layout()
                    self.measuringRestoredPage = false
                }
            }
            if !registered { waitingForNavigationTransition = false }
        }
        return true
    }

    private func synchronizeFlutterSafeArea(_ window: UIWindow) {
        let physical = window.rootViewController?.view.safeAreaInsets ?? .zero
        let current = flutter.view.safeAreaInsets
        let previous = flutter.additionalSafeAreaInsets
        let required = UIEdgeInsets(
            top: physical.top - max(0, current.top - previous.top),
            left: physical.left - max(0, current.left - previous.left),
            bottom: physical.bottom - max(0, current.bottom - previous.bottom),
            right: physical.right - max(0, current.right - previous.right))
        if flutter.additionalSafeAreaInsets != required {
            flutter.additionalSafeAreaInsets = required
            flutter.view.setNeedsLayout()
            flutter.view.layoutIfNeeded()
        }
    }

    /// Positions the incoming page while UIKit animates its push. UIKit gives
    /// the incoming controller its destination safe area at the start of the
    /// transition, so only that controller is read. The navigation bar is
    /// never laid out here: it must keep animating between its two items.
    private func transitionLayout(_ window: UIWindow) {
        layingOut = true
        defer { layingOut = false }
        content.view.layoutIfNeeded()
        let scroll = content.scroll
        let inset = scroll.adjustedContentInset.top
        guard inset > 0, scroll.window != nil, !scroll.bounds.isEmpty else {
            scheduleLayout()
            return
        }
        synchronizeFlutterSafeArea(window)
        let offsetValue = externalNavigation == nil ? (page?.nativeScrollOffset ?? 0) : externalOffset
        let size = window.bounds.size
        let contentSize = CGSize(width: size.width, height: size.height + max(size.height, offsetValue))
        if scroll.contentSize != contentSize { scroll.contentSize = contentSize }
        let offset = CGPoint(x: 0, y: offsetValue - inset)
        if scroll.contentOffset != offset { scroll.setContentOffset(offset, animated: false) }
        // The scroll view's bounds origin is its content offset; measure from
        // its frame so only the horizontal transition offset is ignored.
        let top = content.view.superview?.convert(content.view.frame.origin, to: window).y ?? 0
        let bottom = top + inset
        content.layoutSearchTransitionGlass()
        if externalNavigation == nil { page?.nativeNavigationLayout(contentInset: inset, barBottom: bottom) }
        content.nativeMetricsChanged?(inset, bottom)
    }

    private func layout() {
        applyCovered(animated: false)
        for navigation in [navigation, regularNavigation, externalNavigation].compactMap({ $0 }) {
            AdaptiveNativeFonts.ensureStyled(navigation.navigationBar)
        }
        if let tabBar = tabs?.tabBar { AdaptiveNativeFonts.ensureStyled(tabBar) }
        guard !layingOut, !movingContent, pendingPush == nil,
              !preparingPop || measuringRestoredPage, let window,
              page != nil || externalNavigation != nil || managedRoutes.count > 1,
              !(dismissingSearch != nil && externalNavigation == nil) else { return }
        let observedNavigation = externalNavigation ?? regularNavigation ?? navigation
        if deferForNavigationTransition(observedNavigation) {
            // A pushed page must render in its destination position from the
            // first animation frame; everything else waits for UIKit to finish.
            if pushCompletion != nil, !preparingPop, content.view.window != nil {
                transitionLayout(window)
            }
            return
        }
        guard content.hasCompletedAppearance else { return }
        layingOut = true
        defer { layingOut = false }
        let scroll = content.scroll
        let offsetValue = externalNavigation == nil ? (page?.nativeScrollOffset ?? 0) : externalOffset
        let size = window.bounds.size
        synchronizeFlutterSafeArea(window)
        let contentSize = CGSize(width: size.width, height: size.height + max(size.height, offsetValue))
        if scroll.contentSize != contentSize { scroll.contentSize = contentSize }
        window.rootViewController?.view.layoutIfNeeded()
        observedNavigation.view.layoutIfNeeded()
        // UIKit owns native search/keyboard geometry until its transition ends.
        // Preserve Flutter's logical offset and mirror it from the rebased origin.
        if let geometrySearch, content.navigationItem.searchController === geometrySearch,
           geometryContent === content,
           searchPresentationTransition || keyboardTransition { return }
        let traits = observedNavigation.traitCollection
        let geometryKey = "\(size.width)|\(size.height)|\(traits.displayScale)|\(traits.horizontalSizeClass.rawValue)|\(traits.verticalSizeClass.rawValue)|\(traits.preferredContentSizeCategory.rawValue)"
        let ownerKey = externalNavigation == nil ? page.map { String(describing: ObjectIdentifier($0)) } ?? "none" : "search-\(ObjectIdentifier(content))"
        let context = "\(ownerKey)|\(geometryKey)"
        if originContext != context {
            originContext = context
            originGeometryKey = geometryKey
            if externalNavigation != nil { restingInset = externalOrigins[context] }
            else if let page { restingInset = pageStates[ObjectIdentifier(page)]?.origins[geometryKey] }
            else { restingInset = nil }
        }
        if restingInset == nil || restingInset == 0 {
            for _ in 0..<2 {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
                observedNavigation.view.layoutIfNeeded()
            }
            if scroll.adjustedContentInset.top > 0 {
                restingInset = scroll.adjustedContentInset.top
                if externalNavigation != nil { externalOrigins[context] = restingInset }
                else if let page { pageStates[ObjectIdentifier(page)]?.origins[geometryKey] = restingInset }
            }
        }
        guard let inset = restingInset, inset > 0, scroll.window != nil, !scroll.bounds.isEmpty else {
            scheduleLayout()
            return
        }
        let offset = CGPoint(x: 0, y: offsetValue - inset)
        if scroll.contentOffset != offset { scroll.setContentOffset(offset, animated: false) }
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
        observedNavigation.view.layoutIfNeeded()
        let bar = observedNavigation.navigationBar
        let bottom = bar.convert(bar.bounds, to: window).maxY
        if externalNavigation == nil { page?.nativeNavigationLayout(contentInset: inset, barBottom: bottom) }
        content.nativeMetricsChanged?(inset, bottom)
    }
}
