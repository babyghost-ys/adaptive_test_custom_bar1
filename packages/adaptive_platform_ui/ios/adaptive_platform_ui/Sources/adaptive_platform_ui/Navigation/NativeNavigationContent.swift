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
    /// The bar colour behind an iOS 26+ large title. UIKit draws that title
    /// inside the content scroll view, under the navigation bar, so an opaque
    /// bar would hide it; the bar stays clear at the scroll edge instead and
    /// this band carries its colour behind the title.
    var largeTitleColor: UIColor? { didSet { setNeedsLayout() } }
    private let largeTitleBackdrop: UIView = {
        let backdrop = UIView()
        backdrop.isUserInteractionEnabled = false
        backdrop.accessibilityElementsHidden = true
        return backdrop
    }()
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
        layoutLargeTitleBackdrop()
    }
    private func layoutLargeTitleBackdrop() {
        guard let color = largeTitleColor,
              let title = subviews.first(where: {
                  $0 !== viewport && $0 !== largeTitleBackdrop
                      && NSStringFromClass(type(of: $0)).contains("LargeTitle")
              }) else {
            largeTitleBackdrop.removeFromSuperview()
            return
        }
        largeTitleBackdrop.backgroundColor = color
        largeTitleBackdrop.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                          height: max(0, title.frame.maxY - bounds.minY))
        if let backdropIndex = subviews.firstIndex(of: largeTitleBackdrop),
           let titleIndex = subviews.firstIndex(of: title), backdropIndex < titleIndex { return }
        insertSubview(largeTitleBackdrop, belowSubview: title)
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
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        // Before UIKit lays the turn out, so no overlay follows the bounds.
        if let flutter { FlutterTurnPinning.pinOverlays(in: flutter.view) }
        super.viewWillTransition(to: size, with: coordinator)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finishSearchTransitionGlass()
        if forwardingDisappearance { flutter?.endAppearanceTransition(); forwardingDisappearance = false }
    }
    /// With [early], Flutter appears before this page's own appearance has
    /// completed: during a tab switch, which shows the page in place at once
    /// but only completes its appearance when the switch's transition ends.
    func completeFlutterAppearance(early: Bool = false) {
        guard hasCompletedAppearance || early, !flutterAppeared, !forwardingDisappearance,
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
        // While the screen turns, UIKit animates this view's bounds but
        // Flutter keeps drawing the old size until half way through the turn.
        // Keep that frame unscaled at the top left, where UIKit's picture of
        // the old screen shows it, instead of stretching it to the moving
        // bounds; the band the view grows by shows the page colour.
        controller.view.contentMode = .topLeft
        controller.view.backgroundColor = backingScroll.backgroundColor
        FlutterTurnPinning.pinOverlays(in: controller.view)
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
    func setLargeTitleColor(_ color: UIColor?) {
        if backingScroll.largeTitleColor != color { backingScroll.largeTitleColor = color }
    }
    func setNativeBackground(style: UIUserInterfaceStyle) {
        // Resolve the exposed native background without overriding traits on
        // the scroll view that contains Flutter's appearance observer.
        backingScroll.backgroundColor = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
        flutter?.view.backgroundColor = backingScroll.backgroundColor
    }
}

/// Keeps every Flutter-drawn layer of a Flutter view still while the view's
/// bounds animate through a turn. The view's own layer is pinned with
/// `contentMode`; this pins the overlay views Flutter's compositor adds for
/// pixels drawn over a native control (a segmented control on a page, say),
/// which the engine creates with flexible autoresizing, so they would
/// stretch with the bounds and part from UIKit's picture of the old screen.
/// The compositor sets their frames on every frame it draws, so they need
/// no autoresizing.
enum FlutterTurnPinning {
    static func pinOverlays(in view: UIView) {
        for subview in view.subviews
        where NSStringFromClass(type(of: subview)).contains("FlutterOverlayView") {
            subview.autoresizingMask = []
            subview.contentMode = .topLeft
            pinOverlays(in: subview)
        }
    }
}
