import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Build 9: while the screen turns, the Flutter layer keeps its old frame
/// unscaled at the top-left corner instead of stretching to the animating
/// bounds, so it matches UIKit's fading picture of the old screen pixel for
/// pixel. The default gravity returns when the turn ends.
@objc(RotationViewController)
final class RotationViewController: FlutterViewController {
  override func viewWillTransition(
    to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    let layers = [view.layer] + view.subviews.map(\.layer)
    let previous = layers.map(\.contentsGravity)
    for layer in layers { layer.contentsGravity = .topLeft }
    coordinator.animate(alongsideTransition: nil) { _ in
      for (layer, gravity) in zip(layers, previous) { layer.contentsGravity = gravity }
    }
    // Build 10: take the new size at once, as a UIKit view does, instead of
    // holding the old frame for the first half of the turn. The engine's
    // layout pass that follows sends the new metrics straight away.
    let hold = Selector(("setShouldIgnoreViewportMetricsUpdatesDuringRotation:"))
    if responds(to: hold) {
      setValue(false, forKey: "shouldIgnoreViewportMetricsUpdatesDuringRotation")
    }
  }
}
