import Flutter
import UIKit
import ObjectiveC.runtime

/// Streams where UIKit places its vertical bar for this window
/// (`UITraitCollection.verticalBarEdge`, iOS 27.1) to Dart, as a physical
/// side plus active camera/status occlusions in Flutter-view coordinates.
/// The edge is "left", "right", "none", or "unsupported" before iOS 27.1.
///
/// Read through KVC so the plugin still builds against SDKs older than 27.1.
final class VerticalBarEdgeStreamHandler: NSObject, FlutterStreamHandler {
    private let registrar: FlutterPluginRegistrar
    private var sink: FlutterEventSink?
    private var observer: EdgeObserverView?
    private var lastSent: NSDictionary?
    /// Bumped on every listen/cancel so retry closures from an earlier
    /// subscription stop instead of racing the current one.
    private var generation = 0
    private var regionRefresh: Timer?

    deinit { regionRefresh?.invalidate() }

    private static let quickAttempts = 20
    private static let quickInterval: TimeInterval = 0.05
    private static let slowInterval: TimeInterval = 0.5

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        regionRefresh?.invalidate()
        regionRefresh = nil
        generation += 1
        observer?.removeFromSuperview()
        observer = nil
        lastSent = nil
        sink = events
        attach(attempt: 0, generation: generation)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        regionRefresh?.invalidate()
        regionRefresh = nil
        generation += 1
        observer?.removeFromSuperview()
        observer = nil
        sink = nil
        lastSent = nil
        return nil
    }

    /// The Flutter view can still be outside a window when Dart starts
    /// listening (scene-based apps), so retry. After the quick attempts run
    /// out, report "unsupported" once so Dart can fall back, but keep polling
    /// slowly in case the view joins a window later.
    private func attach(attempt: Int, generation: Int) {
        guard generation == self.generation, sink != nil, observer == nil else { return }
        guard let host = registrar.viewController?.view, host.window != nil else {
            if attempt == Self.quickAttempts {
                send("unsupported")
            }
            let delay = attempt < Self.quickAttempts ? Self.quickInterval : Self.slowInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attach(attempt: attempt + 1, generation: generation)
            }
            return
        }
        let view = EdgeObserverView(frame: host.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onChange = { [weak self] v in self?.send(Self.edge(of: v), view: v) }
        host.insertSubview(view, at: 0)
        observer = view
        send(Self.edge(of: view), view: view)
        // Occlusion activity can change without a size or trait change. Query
        // the current view again rather than retaining regions from an old pose.
        regionRefresh = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self, weak view] _ in
            guard let self, let view else { return }
            self.send(Self.edge(of: view), view: view)
        }
    }

    private func send(_ edge: String, view: UIView? = nil) {
        let payload: NSDictionary = [
            "edge": edge,
            "regions": view.map(Self.occlusions) ?? []
        ]
        guard lastSent == nil || !payload.isEqual(lastSent!) else { return }
        lastSent = payload
        sink?(payload)
    }

    /// Query only active occlusions in this view's coordinates. Runtime lookup
    /// lets this package continue compiling with SDKs predating this UIKit API.
    /// No hinge sensors, posture tracking, or device-size guesses are needed.
    private static func occlusions(in view: UIView) -> [[String: Double]] {
        let query = NSSelectorFromString("reservedRegionsOfKind:options:")
        let factory = NSSelectorFromString("occlusionRegionKind")
        guard view.responds(to: query),
              let kindClass = NSClassFromString("UIViewReservedRegionKind"),
              let method = class_getClassMethod(kindClass, factory)
        else { return [] }
        typealias MakeKind = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        let makeKind = unsafeBitCast(method_getImplementation(method), to: MakeKind.self)
        let kind = makeKind(kindClass, factory).takeUnretainedValue()
        typealias Query = @convention(c) (AnyObject, Selector, AnyObject, UInt) -> Unmanaged<AnyObject>
        let read = unsafeBitCast(view.method(for: query), to: Query.self)
        guard let regions = read(view, query, kind, 0).takeUnretainedValue() as? [NSObject]
        else { return [] }
        return regions.compactMap { region in
            guard region.responds(to: NSSelectorFromString("frame")),
                  let frame = (region.value(forKey: "frame") as? NSValue)?.cgRectValue,
                  !frame.isNull, !frame.isInfinite, !frame.isEmpty
            else { return nil }
            if region.responds(to: NSSelectorFromString("isActive")),
               let active = region.value(forKey: "active") as? NSNumber,
               !active.boolValue { return nil }
            return ["x": Double(frame.minX), "y": Double(frame.minY),
                    "width": Double(frame.width), "height": Double(frame.height)]
        }
    }

    static func edge(of view: UIView) -> String {
        let key = "verticalBarEdge"
        let traits = view.traitCollection
        guard traits.responds(to: NSSelectorFromString(key)),
            let raw = (traits.value(forKey: key) as? NSNumber)?.intValue
        else { return "unsupported" }
        let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        switch raw {
        case 1: return rtl ? "right" : "left"  // UIVerticalBarEdgeLeading
        case 2: return rtl ? "left" : "right"  // UIVerticalBarEdgeTrailing
        default: return "none"                 // UIVerticalBarEdgeUnspecified
        }
    }
}

/// Draws nothing and takes no touches; reports layout, trait and safe-area
/// changes of the Flutter view (pane switch, divider drag, rotation). Moving
/// between Split View panes does not change the view's size, as both panes are
/// the same width, but it does change the safe-area insets, so those are the
/// signal for pane moves.
private final class EdgeObserverView: UIView {
    var onChange: ((UIView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onChange?(self)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        onChange?(self)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onChange?(self)
    }
}
