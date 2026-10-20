import Flutter
import UIKit

/// Measures where UIKit lays out a navigation bar's title for this window, so
/// the Flutter-drawn iPhone Duo title band follows the system instead of
/// assumed sizes. A hidden navigation controller is laid out under the app's
/// view controller, which gives it the window's traits (the vertical bar edge
/// among them), then removed again. Nothing is shown on screen.
final class DuoTitleBand {
    private let registrar: FlutterPluginRegistrar

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "measure" else {
            result(FlutterMethodNotImplemented)
            return
        }
        result(measure())
    }

    /// `contentTop`: where UIKit starts the page content below the bar.
    /// `largeTitleMidY` / `inlineTitleMidY`: vertical centre of each title.
    /// `titleMinX`: leading edge of the title. Positions are in points, in the
    /// Flutter view's coordinates. `…FontSize` / `…FontWeight`: the type of
    /// each title, the weight as the index of the nearest `UIFont.Weight`
    /// from ultra light to black. Nil when the view is not in a window yet.
    private func measure() -> [String: Double]? {
        guard let host = registrar.viewController, host.view.window != nil else { return nil }
        guard let large = layout(in: host, large: true),
              let inline = layout(in: host, large: false) else { return nil }
        return [
            "contentTop": Double(large.contentTop),
            "largeTitleMidY": Double(large.title.midY),
            "inlineTitleMidY": Double(inline.title.midY),
            "titleMinX": Double(large.title.minX),
            "largeTitleFontSize": Double(large.font.pointSize),
            "largeTitleFontWeight": Double(Self.weightIndex(of: large.font)),
            "inlineTitleFontSize": Double(inline.font.pointSize),
            "inlineTitleFontWeight": Double(Self.weightIndex(of: inline.font)),
        ]
    }

    private func layout(
        in host: UIViewController, large: Bool
    ) -> (contentTop: CGFloat, title: CGRect, font: UIFont)? {
        let marker = "Title"
        let page = UIViewController()
        page.title = marker
        page.navigationItem.largeTitleDisplayMode = large ? .always : .never
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = large
        navigation.view.isHidden = true
        navigation.view.isUserInteractionEnabled = false
        navigation.view.accessibilityElementsHidden = true
        navigation.view.frame = host.view.bounds

        host.addChild(navigation)
        host.view.insertSubview(navigation.view, at: 0)
        navigation.didMove(toParent: host)
        navigation.view.setNeedsLayout()
        navigation.view.layoutIfNeeded()

        let contentTop = page.view.convert(
            CGPoint(x: 0, y: page.view.safeAreaInsets.top), to: host.view
        ).y
        let label = Self.titleLabel(in: navigation.view, text: marker)
        let title = label.map { $0.convert($0.bounds, to: host.view) }

        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
        guard let title, let font = label?.font, contentTop > 0 else { return nil }
        return (contentTop, title, font)
    }

    private static let weights: [UIFont.Weight] = [
        .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
    ]

    /// Index in [weights] of the weight nearest to the font's.
    private static func weightIndex(of font: UIFont) -> Int {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let raw = (traits?[.weight] as? NSNumber).map { CGFloat($0.doubleValue) }
            ?? UIFont.Weight.regular.rawValue
        let distances = weights.map { abs($0.rawValue - raw) }
        return distances.firstIndex(of: distances.min()!) ?? weights.firstIndex(of: .regular)!
    }

    /// The label UIKit shows the title in: of the labels carrying it, the
    /// visible one with the largest font (large and inline labels coexist).
    private static func titleLabel(in view: UIView, text: String) -> UILabel? {
        var best: UILabel?
        func visit(_ view: UIView) {
            if let label = view as? UILabel,
               label.text == text || label.attributedText?.string == text,
               !label.isHidden, label.alpha > 0, !label.bounds.isEmpty,
               label.font.pointSize > (best?.font.pointSize ?? 0) {
                best = label
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best
    }
}
