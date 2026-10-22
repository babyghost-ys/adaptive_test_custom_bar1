import Flutter
import UIKit

/// Retained by the channel handler; one presentation at a time per engine.
final class AnchoredActionSheet: NSObject, UIPopoverPresentationControllerDelegate {
    private let hostProvider: () -> UIViewController?
    private var pending: FlutterResult?
    private weak var presented: UIAlertController?

    init(hostProvider: @escaping () -> UIViewController?) {
        self.hostProvider = hostProvider
    }

    private func visibleHost() -> UIViewController? {
        // Implicit engines register plugins before their FlutterViewController
        // is attached. Resolve at presentation time, never during registration.
        if let host = hostProvider(), host.viewIfLoaded?.window != nil {
            return host
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "show" else {
            result(FlutterMethodNotImplemented)
            return
        }
        if pending != nil {
            if let sheet = presented, sheet.presentingViewController != nil {
                result(FlutterError(code: "busy", message: "An action sheet is already open", details: nil))
                return
            }
            // The previous sheet left the screen without running a handler
            // (for example its presenter was torn down). Resolve its caller
            // rather than refusing every later sheet as "busy".
            finish(nil)
        }
        guard let host = visibleHost(), host.view.window != nil,
              let args = call.arguments as? [String: Any],
              let actions = args["actions"] as? [[String: Any]], !actions.isEmpty else {
            result(FlutterError(code: "unavailable", message: "No visible source for action sheet", details: nil))
            return
        }
        var presenter = host
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        guard !presenter.isBeingDismissed else {
            result(nil)
            return
        }
        let alert = UIAlertController(title: args["title"] as? String,
                                      message: args["message"] as? String,
                                      preferredStyle: .actionSheet)
        for (index, action) in actions.enumerated() {
            alert.addAction(UIAlertAction(title: action["title"] as? String,
                style: action["destructive"] as? Bool == true ? .destructive : .default) { [weak self] _ in
                    self?.finish(index)
                })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(nil)
        })
        if let popover = alert.popoverPresentationController {
            // Normalized Flutter-view coordinates remain correct in windowed mode.
            let bounds = host.view.bounds
            let rect = CGRect(
                x: (args["x"] as? Double ?? 0.5) * bounds.width,
                y: (args["y"] as? Double ?? 0.5) * bounds.height,
                width: (args["width"] as? Double ?? 0) * bounds.width,
                height: (args["height"] as? Double ?? 0) * bounds.height
            )
            let visible = rect.intersection(bounds)
            popover.sourceView = host.view
            // An anchor scrolled off screen gives a null rect; point at the
            // centre of the view instead of an undefined location.
            popover.sourceRect = visible.isNull
                ? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
                : visible
            popover.delegate = self
        }
        pending = result
        presented = alert
        presenter.present(alert, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }

    private func finish(_ selection: Int?) {
        let callback = pending
        pending = nil
        callback?(selection)
    }
}
