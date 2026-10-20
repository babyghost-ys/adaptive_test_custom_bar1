import Flutter
import UIKit

/// UIAlertController owns its appearance, presentation, actions and dimming.
/// The historical view/channel names remain stable for existing Dart callers.
class iOS26AlertDialogView: NSObject, FlutterPlatformView, UITextFieldDelegate {
    private let channel: FlutterMethodChannel
    private let container: UIView
    private var alertController: UIAlertController?
    private var maxLength: Int?

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_alert_dialog_\(viewId)", binaryMessenger: messenger)
        container = UIView(frame: frame)
        super.init()
        let config = args as? [String: Any] ?? [:]
        var message = config["message"] as? String
        if let code = config["oneTimeCode"] as? String {
            message = [message, code].compactMap { $0 }.joined(separator: "\n\n")
        }
        let alert = UIAlertController(title: config["title"] as? String, message: message, preferredStyle: .alert)
        alertController = alert
        alert.overrideUserInterfaceStyle = (config["isDark"] as? Bool ?? false) ? .dark : .light
        if let tint = config["tint"] as? Int { alert.view.tintColor = UIColor(argb: tint) }
        maxLength = config["textFieldMaxLength"] as? Int
        if let placeholder = config["textFieldPlaceholder"] as? String {
            alert.addTextField { [weak self] field in
                field.placeholder = placeholder
                field.text = config["textFieldInitialValue"] as? String
                field.isSecureTextEntry = config["textFieldObscureText"] as? Bool ?? false
                field.delegate = self
                switch config["textFieldKeyboardType"] as? String {
                case "emailAddress": field.keyboardType = .emailAddress
                case "number": field.keyboardType = .numberPad
                case "phone": field.keyboardType = .phonePad
                case "url": field.keyboardType = .URL
                default: field.keyboardType = .default
                }
            }
        }
        let titles = config["actionTitles"] as? [String] ?? []
        let styles = config["actionStyles"] as? [String] ?? []
        let enabled = config["actionEnabled"] as? [Bool] ?? []
        for (index, title) in titles.enumerated() {
            let style = index < styles.count ? styles[index] : "defaultAction"
            let nativeStyle: UIAlertAction.Style = style == "cancel" ? .cancel : (style == "destructive" ? .destructive : .default)
            let action = UIAlertAction(title: title, style: nativeStyle) { [weak self] _ in
                var arguments: [String: Any] = ["index": index]
                if let text = self?.alertController?.textFields?.first?.text { arguments["textFieldValue"] = text }
                self?.channel.invokeMethod("actionPressed", arguments: arguments)
            }
            action.isEnabled = (index >= enabled.count || enabled[index]) && style != "disabled"
            alert.addAction(action)
            if style == "primary" { alert.preferredAction = action }
        }
        channel.setMethodCallHandler { [weak self] call, result in
            let values = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "setBrightness":
                self?.alertController?.overrideUserInterfaceStyle = (values["isDark"] as? Bool ?? false) ? .dark : .light
                result(nil)
            case "setStyle":
                if let tint = values["tint"] as? Int { self?.alertController?.view.tintColor = UIColor(argb: tint) }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let presenter = self.topViewController() else { return }
            presenter.present(alert, animated: true)
        }
    }

    func view() -> UIView { container }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let maxLength = maxLength, let current = textField.text,
              let textRange = Range(range, in: current) else { return true }
        return current.replacingCharacters(in: textRange, with: string).count <= maxLength
    }

    private func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        var controller = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

class iOS26AlertDialogViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        iOS26AlertDialogView(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}
