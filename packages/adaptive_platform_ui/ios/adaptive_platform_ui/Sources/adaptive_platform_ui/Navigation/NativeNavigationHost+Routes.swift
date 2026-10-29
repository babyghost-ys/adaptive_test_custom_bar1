import Flutter
import UIKit

extension NativeNavigationHost {
    func prepareNativePush(_ args: [String: Any], result: @escaping FlutterResult) {
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

    func finishNativePushPreparation(_ pending: PendingNativePush) {
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

    func waitForNativeTransition(_ navigation: UINavigationController,
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

    func prepareNativePop(_ args: [String: Any]) {
        guard !preparingPop, managedRoutes.count > 1,
              args["routeId"] as? String == managedRoutes.last?.identifier else { return }
        content.retainRenderedContent()
        preparingPop = true
    }

    func synchronizeNativeStack(_ args: [String: Any], result: @escaping FlutterResult) {
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

    func showNativeRoute(_ args: [String: Any], result: @escaping FlutterResult) {
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
            if let replacement = poppingTargetPage, page == nil || page === replacement {
                page = replacement
                managedRoutes.last?.page = replacement
                remember(replacement)
            }
            poppingTargetPage = nil
            if let page { configure(page) }
            restoreAppearance()
            layout()
            result(true)
            if managedRoutes.count == 1, let selection = selectionAfterReturnToRoot {
                selectionAfterReturnToRoot = nil
                DispatchQueue.main.async(execute: selection)
            }
            return
        }
        result(false)
    }

    func completedNativeNavigation(_ navigation: UINavigationController, controller: UIViewController) {
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
                // A title view arrives from Dart after the push began.
                if let page { configure(page) }
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
    var verticalTabs: Bool {
        tabs != nil && managedRoutes.first?.page?.nativeVerticalNavigation == true
    }

    /// Hides Duo's vertical tab bar for pushed routes and shows it for the
    /// root, without UIKit's hidesBottomBarWhenPushed morph.
    func updateTabBar(for controller: UIViewController, in navigation: UINavigationController) {
        guard #available(iOS 18.0, *), let tabs else { return }
        guard verticalTabs else {
            // A posture change can leave the regular layout in charge mid-stack,
            // with the bar still hidden by a push made in the vertical layout.
            guard tabs.isTabBarHidden,
                  managedRoutes.count <= 1 || controller === managedRoutes.first?.content else { return }
            tabs.setTabBarHidden(false, animated: false)
            navigation.transitionCoordinator?.animate(alongsideTransition: nil) { [weak tabs] context in
                guard context.isCancelled else { return }
                tabs?.setTabBarHidden(true, animated: false)
            }
            return
        }
        let hidden = controller !== managedRoutes.first?.content && (managedRoutes.last?.backButtonVisible ?? true)
        guard tabs.isTabBarHidden != hidden else { return }
        tabs.setTabBarHidden(hidden, animated: true)
        navigation.transitionCoordinator?.animate(alongsideTransition: nil) { [weak tabs] context in
            guard context.isCancelled else { return }
            tabs?.setTabBarHidden(!hidden, animated: true)
        }
    }
}
