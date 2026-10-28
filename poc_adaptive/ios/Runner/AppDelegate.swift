import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var segmentHost: WindowSegmentHost?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WindowSegmentHost") {
      segmentHost = WindowSegmentHost(registrar: registrar)
    }
  }
}

/// A POC-only alternative to Flutter's embedded platform-view composition.
private final class WindowSegmentHost: NSObject {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private var controls: [Int: SegmentContainer] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "sheet_poc/window_segment", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int else {
      result(FlutterError(code: "bad_arguments", message: nil, details: nil))
      return
    }
    switch call.method {
    case "remove":
      controls.removeValue(forKey: id)?.removeFromSuperview()
      result(nil)
    case "update":
      guard let source = registrar.viewController?.viewIfLoaded,
            let window = source.window,
            let labels = args["labels"] as? [String],
            let frame = rect(args["frame"]), let clip = rect(args["clip"]),
            let index = args["index"] as? Int else {
        controls[id]?.isHidden = true
        result(false)
        return
      }
      let container: SegmentContainer
      if let existing = controls[id] {
        container = existing
      } else {
        container = SegmentContainer(labels: labels)
        container.changed = { [weak self] index in
          self?.channel.invokeMethod("changed", arguments: ["id": id, "index": index])
        }
        controls[id] = container
      }
      if container.superview !== window { window.addSubview(container) }
      let clipped = source.convert(clip, to: window).intersection(window.bounds)
      let controlFrame = source.convert(frame, to: window)
      UIView.performWithoutAnimation {
        container.isHidden = !(args["visible"] as? Bool ?? false) || clipped.isNull || clipped.isEmpty
        if !container.isHidden {
          container.frame = clipped
          container.segment.frame = controlFrame.offsetBy(dx: -clipped.minX, dy: -clipped.minY)
          container.segment.selectedSegmentIndex = index
          window.bringSubviewToFront(container)
        }
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func rect(_ value: Any?) -> CGRect? {
    guard let values = value as? [NSNumber], values.count == 4 else { return nil }
    return CGRect(x: values[0].doubleValue, y: values[1].doubleValue,
                  width: max(0, values[2].doubleValue), height: max(0, values[3].doubleValue))
  }
}

private final class SegmentContainer: UIView {
  let segment: UISegmentedControl
  var changed: ((Int) -> Void)?

  init(labels: [String]) {
    segment = UISegmentedControl(items: labels)
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = .clear
    segment.selectedSegmentTintColor = UIColor(red: 181 / 255, green: 33 / 255, blue: 50 / 255, alpha: 1)
    segment.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    addSubview(segment)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func segmentChanged() { changed?(segment.selectedSegmentIndex) }
}
