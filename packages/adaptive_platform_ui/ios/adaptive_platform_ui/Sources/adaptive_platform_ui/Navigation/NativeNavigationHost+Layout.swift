import Flutter
import UIKit

extension NativeNavigationHost {
    func scheduleLayout() {
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
    func deferForNavigationTransition(_ navigation: UINavigationController) -> Bool {
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

    func synchronizeFlutterSafeArea(_ window: UIWindow) {
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
    func transitionLayout(_ window: UIWindow) {
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

    func layout() {
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
        // A tab switch shows the new page in place straight away, but on
        // iOS 26 UIKit only completes its appearance when the switch's
        // transition ends, about 0.6s later. Measure it as soon as it is in
        // the window instead, so the page is not held back until then.
        let switchingTabs = tabs?.transitionCoordinator != nil && content.view.window != nil
        guard content.hasCompletedAppearance || switchingTabs else { return }
        // Until Flutter has appeared here it keeps showing its last frame,
        // which is the tab being left.
        if switchingTabs { content.completeFlutterAppearance(early: true) }
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
