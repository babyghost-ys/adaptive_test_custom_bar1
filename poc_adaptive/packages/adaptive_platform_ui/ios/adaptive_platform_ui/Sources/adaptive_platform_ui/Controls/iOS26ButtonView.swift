import Flutter
import UIKit

/// Factory for system UIButton platform views; historical channel names are stable.
class iOS26ButtonViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26ButtonView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// UIKit button configuration for the running supported iOS version.
class iOS26ButtonView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var button: UIButton!
    private var channel: FlutterMethodChannel
    private var buttonId: Int

    // Configuration
    private var buttonLabel: String = ""
    private var buttonStyle: String = "filled"
    private var buttonSize: String = "medium"
    private var buttonColor: UIColor = .systemBlue
    private var textColor: UIColor?
    private var isEnabled: Bool = true
    private var isDark: Bool = false
    private var iconName: String?
    private var iconSize: CGFloat?
    private var iconColor: UIColor?
    private var useSmoothRectangleBorder: Bool = true

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _view = UIView(frame: frame)

        // Extract configuration from arguments
        if let config = args as? [String: Any] {
            buttonId = config["id"] as? Int ?? 0
            buttonLabel = config["label"] as? String ?? ""
            buttonStyle = config["style"] as? String ?? "filled"
            buttonSize = config["size"] as? String ?? "medium"
            isEnabled = config["enabled"] as? Bool ?? true
            isDark = config["isDark"] as? Bool ?? false

            if let colorHex = config["color"] as? String {
                buttonColor = UIColor(hexString: colorHex) ?? .systemBlue
            }

            if let textColorHex = config["textColor"] as? String {
                textColor = UIColor(hexString: textColorHex)
            }

            // SF Symbol icon configuration
            iconName = config["iconName"] as? String
            if let size = config["iconSize"] as? Double {
                iconSize = CGFloat(size)
            }
            if let argb = config["iconColor"] as? Int {
                iconColor = UIColor(argb: argb)
            }

            // Use smooth rectangle border setting
            useSmoothRectangleBorder = config["useSmoothRectangleBorder"] as? Bool ?? true
        } else {
            buttonId = 0
        }

        // Setup method channel for communication
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_button_\(buttonId)",
            binaryMessenger: messenger
        )

        super.init()

        // Create the native button
        createNativeButton()
        NotificationCenter.default.addObserver(
            self, selector: #selector(nativeFontChanged), name: AdaptiveNativeFonts.didChange, object: nil)

        // Apply Flutter's brightness override
        if #available(iOS 13.0, *) {
            _view.overrideUserInterfaceStyle = isDark ? .dark : .light
        }

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _view
    }

    private func createNativeButton() {
        // Create iOS button with system type
        button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Set tint color
        button.tintColor = buttonColor

        // Apply the running system’s UIButton.Configuration.
        applySystemConfiguration()

        // Setup constraints
        _view.addSubview(button)

        // UIKit supplies the intrinsic size; Flutter allocates the container.
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: _view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: _view.trailingAnchor),
            button.topAnchor.constraint(equalTo: _view.topAnchor),
            button.bottomAnchor.constraint(equalTo: _view.bottomAnchor)
        ])

        // Low content hugging - button can expand if container wants
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Add tap action
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)

        // Apply enabled state
        button.isEnabled = isEnabled
    }

    private func applySystemConfiguration() {
        // The package's minimum deployment target is iOS 15.
        var config: UIButton.Configuration

        // Select configuration based on button style
        // Note: .glass() and .prominentGlass() are only available on iOS 26+
        switch buttonStyle {
        case "filled":
            config = .filled()
        case "tinted":
            config = .tinted()
        case "gray":
            config = .gray()
        case "bordered":
            config = .bordered()
        case "plain":
            config = .plain()
        case "glass":
            if #available(iOS 26.0, *) {
                config = .glass()
            } else {
                // Use an existing system style on systems without glass.
                config = .tinted()
            }
        case "prominentGlass":
            if #available(iOS 26.0, *) {
                config = .prominentGlass()
            } else {
                config = .filled()
            }
        default:
            config = .filled()
        }

        // Set title or icon based on configuration
        if let iconName = iconName {
            // SF Symbol icon mode
            if let image = UIImage(systemName: iconName) ?? UIImage(named: iconName) {
                var finalImage = image

                // Apply icon size
                let symbolSize = iconSize ?? 24.0
                finalImage = image.applyingSymbolConfiguration(
                    UIImage.SymbolConfiguration(pointSize: symbolSize)
                ) ?? image

                // Apply icon color
                if let color = iconColor {
                    finalImage = finalImage.withTintColor(color, renderingMode: .alwaysOriginal)
                }

                config.image = finalImage
                config.title = nil
                config.attributedTitle = nil
            }
        } else if !buttonLabel.isEmpty {
            // Text label mode
            config.title = buttonLabel
        }

        // Set corner style based on useSmoothRectangleBorder
        if useSmoothRectangleBorder {
            // Use smooth rectangle border (default iOS style)
            config.cornerStyle = .dynamic
        } else {
            // Use capsule (perfectly circular) shape
            config.cornerStyle = .capsule
        }

        // Set colors based on button style
        if let tint = button.tintColor {
            switch buttonStyle {
            case "filled":
                config.baseBackgroundColor = tint
                // Use custom text color if provided, otherwise white
                config.baseForegroundColor = textColor ?? .white
            case "tinted", "bordered", "gray", "plain":
                // Use custom text color if provided, otherwise tint
                config.baseForegroundColor = textColor ?? tint
            case "glass", "prominentGlass":
                // Glass buttons use tint color or custom text color
                config.baseForegroundColor = textColor ?? tint
            default:
                break
            }
        } else if let customTextColor = textColor {
            // If no tint but custom text color exists, use it
            config.baseForegroundColor = customTextColor
        }

        switch buttonSize {
        case "small": config.buttonSize = .small
        case "large": config.buttonSize = .large
        default: config.buttonSize = .medium
        }

        // A capsule keeps its title on one line; a title wider than the
        // space Flutter gives the button (a wide custom font) truncates.
        config.titleLineBreakMode = .byTruncatingTail

        // The package-wide native font, when one is set.
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            guard AdaptiveNativeFonts.family != nil else { return incoming }
            var outgoing = incoming
            outgoing.font = AdaptiveNativeFonts.font(size: incoming.font?.pointSize ?? 17, weight: .semibold)
            return outgoing
        }

        // Apply configuration
        button.configuration = config
    }

    @objc private func nativeFontChanged() {
        applySystemConfiguration()
    }

    @objc private func buttonTapped() {
        // Notify Flutter side about button press
        channel.invokeMethod("pressed", arguments: nil)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getIntrinsicSize":
            // UIKit applies a new configuration lazily; measure the current one,
            // such as a title just restyled in another font. Measure without
            // the current frame: a wider title would otherwise wrap inside it.
            button.updateConfiguration()
            let size = button.sizeThatFits(
                CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            result(["width": max(1, size.width), "height": max(1, size.height)])

        case "setSize":
            if let args = call.arguments as? [String: Any], let size = args["size"] as? String {
                buttonSize = size
                applySystemConfiguration()
            }
            result(nil)

        case "setStyle":
            if let args = call.arguments as? [String: Any],
               let style = args["style"] as? String {
                buttonStyle = style
                applySystemConfiguration()
            }
            result(nil)

        case "setLabel":
            if let args = call.arguments as? [String: Any],
               let label = args["label"] as? String {
                buttonLabel = label
                applySystemConfiguration()
            }
            result(nil)

        case "setEnabled":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                isEnabled = enabled
                button.isEnabled = enabled
            }
            result(nil)

        case "setColor":
            let args = call.arguments as? [String: Any]
            buttonColor = (args?["color"] as? String).flatMap { UIColor(hexString: $0) } ?? .systemBlue
            button.tintColor = buttonColor
            applySystemConfiguration()
            result(nil)

        case "setTextColor":
            let args = call.arguments as? [String: Any]
            textColor = (args?["color"] as? String).flatMap { UIColor(hexString: $0) }
            applySystemConfiguration()
            result(nil)

        case "setIcon":
            if let args = call.arguments as? [String: Any] {
                iconName = args["iconName"] as? String
                iconSize = (args["iconSize"] as? Double).map { CGFloat($0) }
                iconColor = (args["iconColor"] as? Int).map { UIColor(argb: $0) }
                applySystemConfiguration()
            }
            result(nil)

        case "setUseSmoothRectangleBorder":
            if let args = call.arguments as? [String: Any],
               let useSmoothRect = args["useSmoothRectangleBorder"] as? Bool {
                useSmoothRectangleBorder = useSmoothRect
                applySystemConfiguration()
            }
            result(nil)

        case "setBrightness":
            if let args = call.arguments as? [String: Any],
               let dark = args["isDark"] as? Bool {
                isDark = dark
                if #available(iOS 13.0, *) {
                    _view.overrideUserInterfaceStyle = dark ? .dark : .light
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

}

/// UIColor extension to parse hex color strings and ARGB integers
extension UIColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: // ARGB or RGBA
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }

    convenience init(argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
