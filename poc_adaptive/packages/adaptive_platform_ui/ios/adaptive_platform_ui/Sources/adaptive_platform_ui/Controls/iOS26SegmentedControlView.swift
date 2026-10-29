import Flutter
import UIKit

final class iOS26SegmentedControlViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        iOS26SegmentedControlView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// The UIKit control itself is the platform view. Flutter owns its frame;
/// UIKit owns its contents, native selection animation and Liquid Glass.
/// There is no second view or layout pass trying to resize the control.
final class iOS26SegmentedControlView: NSObject, FlutterPlatformView {
    private let control: UISegmentedControl
    private let channel: FlutterMethodChannel
    private var configuration: Configuration?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        control = UISegmentedControl(frame: frame)
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/segmented_control/\(viewId)",
            binaryMessenger: messenger)
        super.init()

        apply(Configuration(args as? [String: Any] ?? [:]))
        control.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self, selector: #selector(nativeFontChanged),
            name: AdaptiveNativeFonts.didChange, object: nil)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "disposed", message: "The segmented control was disposed.", details: nil))
                return
            }
            guard call.method == "update" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let values = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_arguments", message: "Expected a control configuration.", details: nil))
                return
            }
            self.apply(Configuration(values))
            result(nil)
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
        NotificationCenter.default.removeObserver(self)
    }

    func view() -> UIView { control }

    private func apply(_ next: Configuration) {
        let previous = configuration
        guard next != previous else { return }
        configuration = next

        let itemsChanged = previous?.labels != next.labels || previous?.symbols != next.symbols
        if itemsChanged {
            control.removeAllSegments()
            for index in 0..<next.itemCount {
                // Keep an item for every input index, including invalid symbols.
                // Otherwise native selection indices no longer match Dart.
                control.insertSegment(withTitle: next.title(at: index), at: index, animated: false)
            }
        }
        if itemsChanged || previous?.iconSize != next.iconSize || previous?.iconColor != next.iconColor {
            for index in 0..<next.itemCount where !next.symbols.isEmpty {
                if let image = next.image(at: index) {
                    control.setImage(image, forSegmentAt: index)
                }
            }
        }
        if previous?.enabled != next.enabled { control.isEnabled = next.enabled }
        if previous?.isDark != next.isDark {
            control.overrideUserInterfaceStyle = next.isDark ? .dark : .light
        }
        if previous == nil || previous?.tintColor != next.tintColor {
            control.selectedSegmentTintColor = next.tintColor.map(Self.color)
        }
        if previous == nil || previous?.textColor != next.textColor || previous?.selectedTextColor != next.selectedTextColor {
            applyTitleAttributes(next)
        }
        if itemsChanged || previous?.selectedIndex != next.selectedIndex {
            let selected = (0..<next.itemCount).contains(next.selectedIndex)
                ? next.selectedIndex : UISegmentedControl.noSegment
            if control.selectedSegmentIndex != selected { control.selectedSegmentIndex = selected }
        }
    }

    private func applyTitleAttributes(_ configuration: Configuration) {
        let normal = configuration.textColor.map(Self.color) ?? .label
        let selected = configuration.selectedTextColor.map(Self.color) ?? normal
        let font = AdaptiveNativeFonts.font(size: 13, weight: .medium)
        control.setTitleTextAttributes([.foregroundColor: normal, .font: font], for: .normal)
        let selectedStates: [UIControl.State] = [.selected, [.selected, .highlighted], [.selected, .focused]]
        for state in selectedStates {
            control.setTitleTextAttributes([.foregroundColor: selected, .font: font], for: state)
        }
        control.setTitleTextAttributes(
            [.foregroundColor: normal.withAlphaComponent(0.5), .font: font], for: .disabled)
        control.setTitleTextAttributes(
            [.foregroundColor: selected.withAlphaComponent(0.5), .font: font], for: [.selected, .disabled])
    }

    @objc private func nativeFontChanged() {
        if let configuration { applyTitleAttributes(configuration) }
    }

    @objc private func valueChanged() {
        channel.invokeMethod("valueChanged", arguments: ["index": control.selectedSegmentIndex])
    }

    private static func color(_ argb: Int) -> UIColor {
        UIColor(
            red: CGFloat((argb >> 16) & 0xff) / 255,
            green: CGFloat((argb >> 8) & 0xff) / 255,
            blue: CGFloat(argb & 0xff) / 255,
            alpha: CGFloat((argb >> 24) & 0xff) / 255)
    }

    private struct Configuration: Equatable {
        let labels: [String]
        let symbols: [String]
        let selectedIndex: Int
        let enabled: Bool
        let isDark: Bool
        let tintColor: Int?
        let textColor: Int?
        let selectedTextColor: Int?
        let iconSize: Double?
        let iconColor: Int?

        init(_ values: [String: Any]) {
            labels = values["labels"] as? [String] ?? []
            symbols = values["sfSymbols"] as? [String] ?? []
            selectedIndex = values["selectedIndex"] as? Int ?? UISegmentedControl.noSegment
            enabled = values["enabled"] as? Bool ?? true
            isDark = values["isDark"] as? Bool ?? false
            tintColor = (values["tintColor"] as? NSNumber)?.intValue
            textColor = (values["textColor"] as? NSNumber)?.intValue
            selectedTextColor = (values["selectedTextColor"] as? NSNumber)?.intValue
            iconSize = (values["iconSize"] as? NSNumber)?.doubleValue
            iconColor = (values["iconColor"] as? NSNumber)?.intValue
        }

        var itemCount: Int { symbols.isEmpty ? labels.count : symbols.count }

        func title(at index: Int) -> String {
            labels.indices.contains(index) ? labels[index] : ""
        }

        func image(at index: Int) -> UIImage? {
            guard symbols.indices.contains(index), var image = UIImage(systemName: symbols[index]) else { return nil }
            if let iconSize, iconSize.isFinite, iconSize > 0 {
                image = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: CGFloat(iconSize)))
            }
            if let iconColor { image = image.withTintColor(iOS26SegmentedControlView.color(iconColor), renderingMode: .alwaysOriginal) }
            return image
        }
    }
}
