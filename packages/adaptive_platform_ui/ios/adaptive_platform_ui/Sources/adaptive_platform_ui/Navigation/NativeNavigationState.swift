import Flutter
import UIKit

final class NativePageState {
    weak var page: NativeNavigationPage?
    var origins: [String: CGFloat] = [:]
    init(_ page: NativeNavigationPage) { self.page = page }
}

final class NativeRouteState {
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

final class PendingNativePush {
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
func assign<Root: AnyObject, Value: Equatable>(
    _ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>, _ value: Value) {
    if root[keyPath: keyPath] != value { root[keyPath: keyPath] = value }
}
