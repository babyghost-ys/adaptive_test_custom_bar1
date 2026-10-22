import Flutter
import UIKit

extension NativeNavigationHost {
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

    func beginSearchGeometry(_ search: UISearchController, keyboard: Bool) {
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

    func cancelSearchGeometry(_ search: UISearchController) {
        guard geometrySearch === search else { return }
        geometrySearch = nil
        geometryContent = nil
        searchPresentationTransition = false
        keyboardTransition = false
    }

    func endSearchGeometry(_ search: UISearchController, keyboard: Bool) {
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

    func completeSearchDismissal(_ search: UISearchController) {
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

    func dismissSearchForHandoff(_ search: UISearchController) {
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
}
