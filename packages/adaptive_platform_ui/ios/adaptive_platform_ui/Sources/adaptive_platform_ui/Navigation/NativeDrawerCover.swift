import UIKit

/// Lets a Flutter-drawn drawer panel show above the native bars. The panel
/// lies beneath the bars, so the bar views are cut open where the panel is,
/// and the rest of the screen gets the native drawer's dimmed backdrop.
final class NativeDrawerCover: UIView {
    private let scrim = UIControl()
    private var targets: [(view: UIView, mask: CALayer?, interaction: Bool, hidden: Bool)] = []
    /// Tab bars hidden while the panel is out, and whether each was hidden
    /// before.
    private var hiddenBars: [(view: UIView, wasHidden: Bool)] = []
    /// The panel's last reported edge and width, to place everything again
    /// when the window changes size.
    private var panel: (x: CGFloat, width: CGFloat)?

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
        // Before iOS 27 the tab bar's Liquid Glass is drawn whole whatever
        // masks, clips or fades its views: the mask cuts its items open but
        // the glass capsule stays over the panel. Hidden is the one state it
        // honours, so the tab bar goes while the panel is out.
        if #unavailable(iOS 27) {
            func hasTabBar(_ view: UIView) -> Bool {
                view is UITabBar || view.subviews.contains(where: hasTabBar)
            }
            hiddenBars = views.filter(hasTabBar).map { ($0, $0.isHidden) }
            for bar in hiddenBars { bar.view.isHidden = true }
        }
    }

    /// Puts every cut view back as it was.
    func restore() {
        for target in targets {
            target.view.layer.mask = target.mask
            target.view.isUserInteractionEnabled = target.interaction
            target.view.accessibilityElementsHidden = target.hidden
        }
        for bar in hiddenBars { bar.view.isHidden = bar.wasHidden }
        hiddenBars = []
        targets = []
        panel = nil
    }

    /// Places the opening and backdrop for a panel whose left edge is at [x].
    func update(x: CGFloat, width: CGFloat) {
        panel = (x, width)
        let progress = min(1, max(0, (x + width) / width))
        let right = x + width
        scrim.frame = CGRect(x: right, y: 0, width: max(0, bounds.width - right), height: bounds.height)
        scrim.alpha = progress
        guard let window else { return }
        for target in targets {
            // The mask keeps everything the bar draws on screen, including
            // glass and shadows past its own bounds, so it spans the whole
            // window as well as the view. The opening is the panel's column,
            // the full height of that.
            let view = target.view
            let visible = view.bounds.union(view.convert(window.bounds, from: window))
            let column = view.convert(CGRect(x: x, y: 0, width: width, height: 1), from: window)
            let hole = CGRect(x: column.minX, y: visible.minY, width: column.width, height: visible.height)
            let path = UIBezierPath(rect: visible)
            path.append(UIBezierPath(rect: hole))
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillRule = .evenOdd
            target.view.layer.mask = layer

    }

    /// A rotation with the panel open resizes the window and the bars, but
    /// the panel does not move, so Dart reports nothing new. Size the
    /// backdrop and the bars' openings again, once the bars have their new
    /// size too.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let panel else { return }
        update(x: panel.x, width: panel.width)
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.update(x: panel.x, width: panel.width)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
