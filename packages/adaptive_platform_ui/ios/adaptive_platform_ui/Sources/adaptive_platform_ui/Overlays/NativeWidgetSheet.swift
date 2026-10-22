import Flutter
import UIKit

/// A real UIKit sheet (`UISheetPresentationController`) whose content is the
/// app's own Flutter widget.
///
/// The sheet's content is a second `FlutterViewController` on the same
/// engine. Only one view controller can drive an engine at a time, so while
/// the sheet is up the engine renders into the sheet, and the page behind it
/// keeps its last frame. Dart pushes the caller's widget as a full-window
/// route, which therefore fills the sheet, and runs in the same isolate as the
/// rest of the app, so the widget keeps its closures, its state and its blocs.
/// When the sheet goes, the engine is handed back to the original view
/// controller.
final class NativeWidgetSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private weak var originalHost: FlutterViewController?
    private weak var engine: FlutterEngine?
    private var sheet: UIViewController?

    /// The one controller that ever hosts a sheet. When a FlutterViewController
    /// is released, Flutter destroys an engine that may not run headless, so it
    /// is created once and kept for the life of the app, and reused.
    private var persistent: FlutterViewController?

    /// Height of the "fit" detent: what Dart measured for the content.
    private var fitHeight: CGFloat = 320

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.channel = channel
        self.hostProvider = hostProvider
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "present": present(call.arguments as? [String: Any] ?? [:], result: result)
        case "setHeight": setHeight(call.arguments as? [String: Any] ?? [:], result: result)
        case "dismiss": dismiss(result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func topPresenter(from host: UIViewController) -> UIViewController? {
        var presenter: UIViewController? = host.view.window?.rootViewController
        if presenter == nil {
            presenter = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?.rootViewController
        }
        while let next = presenter?.presentedViewController { presenter = next }
        return presenter
    }

    private func present(_ args: [String: Any], result: @escaping FlutterResult) {
        guard sheet == nil else {
            result(FlutterError(code: "busy", message: "A widget sheet is already open", details: nil))
            return
        }
        guard let host = hostProvider() as? FlutterViewController,
              let presenter = topPresenter(from: host), !presenter.isBeingDismissed else {
            result(FlutterError(code: "unavailable", message: "No Flutter view to present from", details: nil))
            return
        }

        let engine: FlutterEngine = host.engine
        let controller = persistent
            ?? FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        persistent = controller
        // Becoming the engine's view controller again if it already hosted a
        // sheet before.
        engine.viewController = controller
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            switch args["detents"] as? String ?? "halfAndFull" {
            case "full":
                sheet.detents = [.large()]
            case "fit":
                fitHeight = CGFloat((args["height"] as? NSNumber)?.doubleValue ?? 320)
                if #available(iOS 16.0, *) {
                    let fit = UISheetPresentationController.Detent.Identifier("fit")
                    sheet.detents = [
                        .custom(identifier: fit) { [weak self] context in
                            min(context.maximumDetentValue, self?.fitHeight ?? 320)
                        },
                        .large(),
                    ]
                    sheet.selectedDetentIdentifier = fit
                } else {
                    sheet.detents = [.medium(), .large()]
                }
            case "short":
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom(identifier: UISheetPresentationController.Detent.Identifier("short")) {
                        context in
                        min(context.maximumDetentValue, max(context.maximumDetentValue * 0.34, 300))
                    }]
                } else {
                    sheet.detents = [.medium()]
                }
            default:
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        controller.presentationController?.delegate = self

        originalHost = host
        self.engine = engine
        sheet = controller
        controller.view.backgroundColor = .systemBackground
        presenter.present(controller, animated: true)
        // Answer as soon as the engine has moved into the sheet, not when the
        // slide-up finishes: Dart switches the sheet's content on at that
        // point, so the sheet never shows the page it is about to cover.
        result(nil)
    }

    /// The content's height changed: resize the "fit" detent to it, animated.
    private func setHeight(_ args: [String: Any], result: @escaping FlutterResult) {
        defer { result(nil) }
        guard let height = (args["height"] as? NSNumber)?.doubleValue,
              abs(CGFloat(height) - fitHeight) > 0.5 else { return }
        fitHeight = CGFloat(height)
        guard #available(iOS 16.0, *), let sheet = sheet?.sheetPresentationController else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
    }

    private func dismiss(result: @escaping FlutterResult) {
        guard let sheet else {
            result(nil)
            return
        }
        sheet.dismiss(animated: true) { [weak self] in
            self?.restoreEngine()
            result(nil)
        }
    }

    /// The user dragged the sheet away.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        restoreEngine()
        channel.invokeMethod("dismissedByUser", arguments: nil)
    }

    /// Hands the engine back to the page's own view controller. The sheet's
    /// controller stays alive in [persistent]; releasing it would destroy the
    /// engine.
    private func restoreEngine() {
        sheet = nil
        guard let engine, let originalHost else { return }
        engine.viewController = originalHost
        // Re-attach the page's rendering surface. FlutterViewController does
        // this when it appears; it did not go away, so ask for it directly.
        let selector = NSSelectorFromString("surfaceUpdated:")
        if originalHost.responds(to: selector) {
            typealias Call = @convention(c) (AnyObject, Selector, Bool) -> Void
            let call = unsafeBitCast(originalHost.method(for: selector), to: Call.self)
            call(originalHost, selector, true)
        }
        originalHost.viewWillAppear(false)
        originalHost.viewDidAppear(false)
        originalHost.view.setNeedsLayout()
        originalHost.view.layoutIfNeeded()
    }
}
