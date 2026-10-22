import Flutter
import UIKit

extension NativeNavigationHost {
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

    func installTabs(_ controller: UITabBarController, content next: NativeNavigationContent,
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

    func selectContent(_ next: NativeNavigationContent, searchNavigation: UINavigationController?,
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
}
