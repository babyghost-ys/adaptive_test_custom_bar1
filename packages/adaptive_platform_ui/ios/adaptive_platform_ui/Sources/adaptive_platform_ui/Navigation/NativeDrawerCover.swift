import UIKit

/// Lets a Flutter-drawn drawer panel show above the native bars. The panel
/// lies beneath the bars, so the bar views are cut open where the panel is,
/// and the rest of the screen gets the native drawer's dimmed backdrop.
final class NativeDrawerCover: UIView {
    private let scrim = UIControl()
    private var targets: [(view: UIView, mask: CALayer?, interaction: Bool, hidden: Bool)] = []

    var tapped: (() -> Void)?

    /// The status bar style that stays legible over the panel colour.
    let statusBarStyle: UIStatusBarStyle

    init(background: UIColor) {
        var white: CGFloat = 0
        background.getWhite(&white, alpha: nil)
        statusBarStyle = white > 0.5 ? .darkContent : .lightContent
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        scrim.addTarget(self, action: #selector(tap), for: .touchUpInside)
        scrim.accessibilityTraits = .button
        addSubview(scrim)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tap() { tapped?() }

    /// Starts cutting [views] open; [update] moves the opening.
    func mask(_ views: [UIView]) {
        guard targets.isEmpty else { return }
        targets = views.map { ($0, $0.layer.mask, $0.isUserInteractionEnabled, $0.accessibilityElementsHidden) }
        for view in views {
            // Touches in the opening must reach the Flutter panel below.
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }
    }

    /// Puts every cut view back as it was.
    func restore() {
        for target in targets {
            target.view.layer.mask = target.mask
            target.view.isUserInteractionEnabled = target.interaction
            target.view.accessibilityElementsHidden = target.hidden
        }
        targets = []
    }

    /// Places the opening and backdrop for a panel whose left edge is at [x].
    func update(x: CGFloat, width: CGFloat) {
        let progress = min(1, max(0, (x + width) / width))
        let right = x + width
        scrim.frame = CGRect(x: right, y: 0, width: max(0, bounds.width - right), height: bounds.height)
        scrim.alpha = progress
        guard let window else { return }
        let hole = CGRect(x: x, y: -64, width: width, height: bounds.height + 128)
        for target in targets {
            let path = UIBezierPath(rect: target.view.bounds.insetBy(dx: -64, dy: -64))
            path.append(UIBezierPath(rect: target.view.convert(hole, from: window)))
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            target.view.layer.mask = layer
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
