import Flutter
import UIKit

final class NativeNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private let navigationSafeAreaBackground: UIView = {
        let background = UIView()
        background.isUserInteractionEnabled = false
        background.accessibilityElementsHidden = true
        return background
    }()
    private let stripShadowMask = CAShapeLayer()
    private weak var maskedShadow: UIView?

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
        layoutStripShadowMask()
        completedLayout?()
    }
    /// Keeps the bar's shadow off the iPhone Duo vertical bar strip, so the
    /// bar runs straight into the strip below it. UIKit draws the shadow the
    /// full width of the bar; this masks out only the part over the strip and
    /// leaves the bar, its controls and the status cluster untouched.
    private func layoutStripShadowMask() {
        navigationBar.layoutIfNeeded()
        let shadow = Self.shadowView(in: navigationBar)
        if maskedShadow !== shadow {
            maskedShadow?.layer.mask = nil
            maskedShadow = shadow
        }
        guard let shadow, let strip = verticalBarStrip() else {
            shadow?.layer.mask = nil
            return
        }
        let cut = shadow.convert(strip, from: view).intersection(shadow.bounds)
        guard !cut.isEmpty else {
            shadow.layer.mask = nil
            return
        }
        let path = UIBezierPath(rect: shadow.bounds)
        path.append(UIBezierPath(rect: cut))
        stripShadowMask.fillRule = .evenOdd
        stripShadowMask.frame = shadow.bounds
        stripShadowMask.path = path.cgPath
        shadow.layer.mask = stripShadowMask
    }
    /// The strip the window keeps for the vertical bar, full height, in this
    /// view's coordinates, or nil where bars stay horizontal. Matches the
    /// Dart side: the safe-area inset where the system reserves one, the
    /// bar's own width in the leading Split View pane where it does not.
    private func verticalBarStrip() -> CGRect? {
        let edge = VerticalBarEdgeStreamHandler.edge(of: view)
        guard edge == "left" || edge == "right" else { return nil }
        let insets = view.safeAreaInsets
        let left = edge == "left"
        let inset = left ? insets.left : insets.right
        let width = inset > 0 ? inset : 84
        return CGRect(x: left ? view.bounds.minX : view.bounds.maxX - width,
                      y: view.bounds.minY, width: width, height: view.bounds.height)
    }
    /// The view UIKit draws the bar's shadow image in, found by the image the
    /// package hands it rather than by private class names.
    private static func shadowView(in view: UIView) -> UIImageView? {
        for child in view.subviews {
            if let image = child as? UIImageView,
               image.image === NativeBarAppearance.shadowImage { return image }
            if let found = shadowView(in: child) { return found }
        }
        return nil
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
    /// On Duo's vertical bar, the outgoing page's leading control morphs into
    /// the incoming page's (menu into Back). Leaving the outgoing bar, it
    /// frees its room there, so controls the bar had folded into its "more"
    /// menu briefly fit and spring out on their own as the page leaves. Only
    /// the morphing control stays; the rest go with the page.
    private static func hideItemsLeftBehindByMorph(on controller: UIViewController?) {
        guard #available(iOS 26.0, *), let item = controller?.navigationItem else { return }
        let items = (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        guard items.contains(where: { $0.identifier == iOS26ToolbarPlatformView.leadingIdentifier }) else { return }
        for barItem in items where barItem.identifier != iOS26ToolbarPlatformView.leadingIdentifier {
            barItem.isHidden = true
        }
    }

    /// Shows or hides every bar control of [controller]'s page.
    private static func setBarItems(of controller: UIViewController?, hidden: Bool) {
        guard #available(iOS 16.0, *), let item = controller?.navigationItem else { return }
        for barItem in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) where barItem.isHidden != hidden {
            barItem.isHidden = hidden
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
        Self.setBarItems(of: viewController, hidden: false)
        if let coordinator = transitionCoordinator {
            let source = coordinator.viewController(forKey: .from) as? NativeNavigationContent
            let sourceHidesBar = source?.transitionHeaderHeight ?? 0 > 0
            let from = coordinator.viewController(forKey: .from)
            Self.hideItemsLeftBehindByMorph(on: from)
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard context.isCancelled else { return }
                Self.setBarItems(of: from, hidden: false)
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
