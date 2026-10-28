import UIKit

/// A side menu above the application's native chrome. The underlying bars
/// remain installed, visible and unmodified throughout presentation.
///
/// Parameters: `title`, `subtitle`, `sections` (lists of `id`/`title`/`symbol`
/// items, divided from each other), `selected` (an item id), `width`, and
/// optional `background` and `tint` colours as ARGB integers. Completes with
/// the chosen item's id, or nil when dismissed.
final class NativeDrawer: UIView, UIGestureRecognizerDelegate {
    private let panel = UIView()
    private let scrim = UIControl()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let requestedWidth: CGFloat
    private let completion: (String?) -> Void
    private var closing = false

    /// The status bar style that stays legible over the panel.
    let statusBarStyle: UIStatusBarStyle

    init(parameters: [String: Any], completion: @escaping (String?) -> Void) {
        requestedWidth = CGFloat(parameters["width"] as? Double ?? 320)
        self.completion = completion
        let background = (parameters["background"] as? Int).map { UIColor(argb: $0) }
        // A custom panel colour decides its own appearance, so labels stay
        // readable on it in either system mode. Otherwise follow the system.
        var style = UIUserInterfaceStyle.unspecified
        if let background {
            var white: CGFloat = 0
            background.getWhite(&white, alpha: nil)
            style = white > 0.5 ? .light : .dark
        }
        statusBarStyle = style == .dark ? .lightContent : style == .light ? .darkContent : .default
        super.init(frame: .zero)
        overrideUserInterfaceStyle = style
        accessibilityViewIsModal = true
        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        scrim.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        scrim.accessibilityLabel = parameters["closeLabel"] as? String ?? "Close"
        scrim.accessibilityTraits = .button
        addSubview(scrim)
        panel.backgroundColor = background ?? .secondarySystemBackground
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 22
        panel.layer.shadowOffset = CGSize(width: 8, height: 0)
        addSubview(panel)
        panel.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        if let text = parameters["title"] as? String {
            let title = UILabel()
            title.text = text
            title.font = UIFont.preferredFont(forTextStyle: .headline)
            title.textColor = .label
            title.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(title)
        }
        if let text = parameters["subtitle"] as? String {
            let subtitle = UILabel()
            subtitle.text = text
            subtitle.font = UIFont.preferredFont(forTextStyle: .caption1)
            subtitle.textColor = .secondaryLabel
            subtitle.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(subtitle)
        }
        if let header = stack.arrangedSubviews.last { stack.setCustomSpacing(28, after: header) }
        let tint = (parameters["tint"] as? Int).map { UIColor(argb: $0) } ?? tintColor
        let selected = parameters["selected"] as? String
        let sections = parameters["sections"] as? [[[String: Any]]] ?? []
        for (index, items) in sections.enumerated() {
            if index > 0 {
                if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(20, after: last) }
                let divider = UIView()
                divider.backgroundColor = UIColor.separator.withAlphaComponent(0.25)
                divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                stack.addArrangedSubview(divider)
                stack.setCustomSpacing(20, after: divider)
            }
            for item in items {
                let identifier = item["id"] as? String
                let isSelected = identifier != nil && identifier == selected
                var configuration = UIButton.Configuration.plain()
                configuration.title = item["title"] as? String
                configuration.image = UIImage(systemName: item["symbol"] as? String ?? "")
                configuration.imagePadding = 14
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 12, bottom: 15, trailing: 12)
                configuration.baseForegroundColor = .label
                configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in
                    isSelected ? tint ?? .label : .secondaryLabel
                }
                configuration.background.backgroundColor = isSelected ? .systemBackground : .clear
                configuration.background.cornerRadius = 12
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
                    var output = input
                    output.font = UIFont.preferredFont(forTextStyle: isSelected ? .headline : .subheadline)
                    return output
                }
                let button = UIButton(configuration: configuration)
                button.contentHorizontalAlignment = .leading
                if isSelected { button.accessibilityTraits.insert(.selected) }
                button.addAction(UIAction { [weak self] _ in self?.dismiss(selection: identifier) }, for: .primaryActionTriggered)
                stack.addArrangedSubview(button)
            }
        }
        let dismissalPan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        dismissalPan.delegate = self
        panel.addGestureRecognizer(dismissalPan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(in window: UIWindow) {
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(self)
        layoutIfNeeded()
        panel.transform = CGAffineTransform(translationX: -panel.bounds.width, y: 0)
        scrim.alpha = 0
        UIView.animate(withDuration: 0.25, animations: {
            self.panel.transform = .identity
            self.scrim.alpha = 1
        }, completion: { _ in UIAccessibility.post(notification: .screenChanged, argument: self.stack.arrangedSubviews.first) })
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = bounds
        let width = min(requestedWidth, bounds.width)
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        panel.center = CGPoint(x: width / 2, y: bounds.midY)
        panel.layer.shadowPath = UIBezierPath(rect: panel.bounds).cgPath
        let safe = window?.safeAreaInsets ?? safeAreaInsets
        scroll.frame = panel.bounds.inset(by: UIEdgeInsets(top: safe.top, left: safe.left, bottom: safe.bottom, right: 0))
    }
    @objc private func cancel() { dismiss(selection: nil) }
    override func accessibilityPerformEscape() -> Bool { cancel(); return true }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let offset = min(0, gesture.translation(in: self).x)
        if gesture.state == .changed {
            panel.transform = CGAffineTransform(translationX: offset, y: 0)
            scrim.alpha = max(0, 1 + offset / panel.bounds.width)
        } else if gesture.state == .ended || gesture.state == .cancelled {
            if offset < -panel.bounds.width * 0.3 || gesture.velocity(in: self).x < -300 {
                dismiss(selection: nil)
            } else {
                UIView.animate(withDuration: 0.2) { self.panel.transform = .identity; self.scrim.alpha = 1 }
            }
        }
    }
    /// Slides the panel away and completes with [selection].
    func dismiss(selection: String?) {
        guard !closing else { return }
        closing = true
        UIView.animate(withDuration: 0.22, animations: {
            self.panel.transform = CGAffineTransform(translationX: -self.panel.bounds.width, y: 0)
            self.scrim.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
            self.completion(selection)
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        })
    }
}
