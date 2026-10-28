import Flutter
import UIKit

/// Factory for native inline UIDatePicker platform views.
class iOS26DatePickerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        iOS26DatePickerView(frame: frame, arguments: args, binaryMessenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// A UIDatePicker embedded in Flutter. UIKit draws the wheels or calendar,
/// so text metrics, haptics and accessibility are the system's own.
class iOS26DatePickerView: NSObject, FlutterPlatformView {
    private let container: UIView
    private let picker = UIDatePicker()
    private let channel: FlutterMethodChannel

    init(frame: CGRect, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger) {
        container = UIView(frame: frame)
        let config = args as? [String: Any] ?? [:]
        let id = config["id"] as? Int ?? 0
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_date_picker_\(id)",
                                       binaryMessenger: messenger)
        super.init()

        picker.datePickerMode = (config["mode"] as? String) == "dateAndTime" ? .dateAndTime : .date
        picker.preferredDatePickerStyle = (config["style"] as? String) == "inline" ? .inline : .wheels
        apply(config)
        if let dark = config["isDark"] as? Bool {
            container.overrideUserInterfaceStyle = dark ? .dark : .light
        }

        picker.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        picker.addTarget(self, action: #selector(changed), for: .valueChanged)

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case "update":
                self.apply(call.arguments as? [String: Any] ?? [:])
                result(nil)
            case "setBrightness":
                if let dark = (call.arguments as? [String: Any])?["isDark"] as? Bool {
                    self.container.overrideUserInterfaceStyle = dark ? .dark : .light
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    private func apply(_ config: [String: Any]) {
        if let ms = config["minimum"] as? NSNumber {
            picker.minimumDate = Date(timeIntervalSince1970: ms.doubleValue / 1000)
        }
        if let ms = config["maximum"] as? NSNumber {
            picker.maximumDate = Date(timeIntervalSince1970: ms.doubleValue / 1000)
        }
        if let ms = config["date"] as? NSNumber {
            let date = Date(timeIntervalSince1970: ms.doubleValue / 1000)
            if picker.date != date { picker.setDate(date, animated: false) }
        }
        if let argb = config["tint"] as? Int { picker.tintColor = UIColor(argb: argb) }
    }

    @objc private func changed() {
        channel.invokeMethod("valueChanged", arguments: [
            "date": Int64(picker.date.timeIntervalSince1970 * 1000)
        ])
    }

    deinit { channel.setMethodCallHandler(nil) }
}
