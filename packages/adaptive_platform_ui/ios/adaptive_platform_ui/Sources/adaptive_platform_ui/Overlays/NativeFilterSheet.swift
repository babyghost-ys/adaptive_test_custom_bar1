import Flutter
import UIKit

// MARK: - Specification

struct FilterOptionSpec {
    let id: String
    let title: String
    let symbol: String?
    let tint: UIColor?
}

enum FilterControlKind {
    case choices(options: [FilterOptionSpec], multiple: Bool, layout: String, columns: Int)
    case slider(min: Double, max: Double, prefix: String, suffix: String, decimals: Int,
                anyLabel: String?, anyAtMin: Bool)
}

struct FilterControlSpec {
    let id: String
    let symbol: String?
    let kind: FilterControlKind
}

private func filterColor(_ value: Any?) -> UIColor? {
    guard let argb = (value as? NSNumber)?.int64Value else { return nil }
    return UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255)
}

private func parseControls(_ raw: [[String: Any]]) -> [FilterControlSpec] {
    raw.compactMap { entry in
        guard let id = entry["id"] as? String, let type = entry["type"] as? String else { return nil }
        let symbol = entry["symbol"] as? String
        switch type {
        case "choices":
            let options = (entry["options"] as? [[String: Any]] ?? []).compactMap { option -> FilterOptionSpec? in
                guard let optionId = option["id"] as? String, let title = option["title"] as? String else { return nil }
                return FilterOptionSpec(id: optionId, title: title,
                                        symbol: option["symbol"] as? String,
                                        tint: filterColor(option["tint"]))
            }
            return FilterControlSpec(id: id, symbol: symbol, kind: .choices(
                options: options,
                multiple: entry["multiple"] as? Bool ?? false,
                layout: entry["layout"] as? String ?? "chips",
                columns: entry["columns"] as? Int ?? 3))
        case "slider":
            return FilterControlSpec(id: id, symbol: symbol, kind: .slider(
                min: (entry["min"] as? NSNumber)?.doubleValue ?? 0,
                max: (entry["max"] as? NSNumber)?.doubleValue ?? 1,
                prefix: entry["prefix"] as? String ?? "",
                suffix: entry["suffix"] as? String ?? "",
                decimals: entry["decimals"] as? Int ?? 0,
                anyLabel: entry["anyLabel"] as? String,
                anyAtMin: entry["anyAtMin"] as? Bool ?? true))
        default:
            return nil
        }
    }
}

/// Normalises a values map so equal selections compare equal.
private func normalised(_ values: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in values {
        if let list = value as? [String] {
            result[key] = list.sorted()
        } else if let number = value as? NSNumber {
            result[key] = number.doubleValue
        }
    }
    return result
}

// MARK: - Presenter

/// A UIKit sheet (`UISheetPresentationController`) built from a declarative
/// list of controls. It floats above the whole window, navigation bars
/// included, and reports each change to Dart so the apply button can show a
/// live result count.
final class NativeFilterSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    private let channel: FlutterMethodChannel
    private let hostProvider: () -> UIViewController?
    private var pending: FlutterResult?
    private weak var presented: FilterSheetController?

    init(channel: FlutterMethodChannel, hostProvider: @escaping () -> UIViewController?) {
        self.channel = channel
        self.hostProvider = hostProvider
    }

    private func visibleHost() -> UIViewController? {
        if let host = hostProvider(), host.viewIfLoaded?.window != nil { return host }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "show" else {
            result(FlutterMethodNotImplemented)
            return
        }
        if pending != nil {
            if let sheet = presented, sheet.presentingViewController != nil {
                result(FlutterError(code: "busy", message: "A filter sheet is already open", details: nil))
                return
            }
            finish(nil)
        }
        guard let host = visibleHost(),
              let args = call.arguments as? [String: Any],
              let rawControls = args["controls"] as? [[String: Any]] else {
            result(FlutterError(code: "unavailable", message: "No visible host for the filter sheet", details: nil))
            return
        }
        var presenter = host
        while let next = presenter.presentedViewController { presenter = next }
        guard !presenter.isBeingDismissed else {
            result(nil)
            return
        }

        let controller = FilterSheetController(
            title: args["title"] as? String ?? "",
            controls: parseControls(rawControls),
            values: normalised(args["values"] as? [String: Any] ?? [:]),
            cleared: normalised(args["cleared"] as? [String: Any] ?? [:]),
            accent: filterColor(args["tint"]) ?? .systemRed,
            detents: args["detents"] as? String ?? "halfAndFull",
            count: (args["count"] as? NSNumber)?.intValue ?? 0)
        controller.onChange = { [weak self] values, update in
            self?.channel.invokeMethod("changed", arguments: values) { reply in
                if let count = (reply as? NSNumber)?.intValue { update(count) }
            }
        }
        controller.onFinish = { [weak self] values in self?.finish(values) }
        controller.presentationController?.delegate = self
        pending = result
        presented = controller
        presenter.present(controller, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }

    private func finish(_ values: [String: Any]?) {
        let callback = pending
        pending = nil
        callback?(values)
    }
}

// MARK: - Sheet content

final class FilterSheetController: UIViewController {
    var onChange: (([String: Any], @escaping (Int) -> Void) -> Void)?
    var onFinish: (([String: Any]?) -> Void)?

    private let sheetTitle: String
    private let controls: [FilterControlSpec]
    private let cleared: [String: Any]
    private let accent: UIColor
    private let detents: String
    private var values: [String: Any]
    private var count: Int

    private let titleLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let sections = UIStackView()
    private var selectionRefreshers: [String: () -> Void] = [:]

    init(title: String, controls: [FilterControlSpec], values: [String: Any],
         cleared: [String: Any], accent: UIColor, detents: String, count: Int) {
        self.sheetTitle = title
        self.controls = controls
        self.values = values
        self.cleared = cleared
        self.accent = accent
        self.detents = detents
        self.count = count
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        configureSheet()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        switch detents {
        case "full":
            sheet.detents = [.large()]
        case "short":
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom(identifier: UISheetPresentationController.Detent.Identifier("short")) {
                    context in
                    min(context.maximumDetentValue, max(context.maximumDetentValue * 0.34, 300))
                }]
            } else {
                sheet.detents = [.medium()]
            }
        default:
            sheet.detents = [.medium(), .large()]
        }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        // In landscape on an iPhone the sheet would otherwise span the whole
        // screen, with nothing outside it to tap. Attached to the bottom edge
        // it keeps its portrait width, with the dimmed page either side.
        sheet.prefersEdgeAttachedInCompactHeight = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.text = sheetTitle
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        resetButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        resetButton.tintColor = .label
        resetButton.accessibilityLabel = "Reset filters"
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.addAction(UIAction { [weak self] _ in self?.reset() }, for: .touchUpInside)

        var apply = UIButton.Configuration.filled()
        apply.baseBackgroundColor = accent
        apply.baseForegroundColor = .white
        apply.cornerStyle = .capsule
        apply.image = UIImage(systemName: "checkmark")
        apply.imagePadding = 8
        apply.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        applyButton.configuration = apply
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true)
            self.onFinish?(self.values)
        }, for: .touchUpInside)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        sections.axis = .vertical
        sections.spacing = 0
        sections.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(sections)

        view.addSubview(titleLabel)
        view.addSubview(resetButton)
        view.addSubview(scroll)
        view.addSubview(applyButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resetButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            resetButton.widthAnchor.constraint(equalToConstant: 44),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -8),
            sections.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            sections.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            sections.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            sections.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            applyButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
        ])

        buildSections()
        refreshChrome()
    }

    // MARK: State

    private func reset() {
        values = cleared
        buildSections()
        notify()
    }

    private func notify() {
        refreshChrome()
        onChange?(values) { [weak self] count in
            self?.count = count
            self?.refreshChrome()
        }
    }

    private func refreshChrome() {
        resetButton.isEnabled = !NSDictionary(dictionary: values).isEqual(to: cleared)
        var config = applyButton.configuration
        config?.title = "\(count)"
        config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        applyButton.configuration = config
    }

    private func selected(_ id: String) -> [String] { values[id] as? [String] ?? [] }

    private func choose(_ control: FilterControlSpec, option: String, multiple: Bool) {
        if multiple {
            var set = Set(selected(control.id))
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
            values[control.id] = Array(set).sorted()
        } else {
            values[control.id] = [option]
        }
        selectionRefreshers[control.id]?()
        notify()
    }

    // MARK: Sections

    private func buildSections() {
        sections.arrangedSubviews.forEach { $0.removeFromSuperview() }
        selectionRefreshers = [:]
        for (index, control) in controls.enumerated() {
            sections.addArrangedSubview(makeSection(control, shaded: index % 2 == 1))
        }
    }

    private func makeSection(_ control: FilterControlSpec, shaded: Bool) -> UIView {
        let band = UIView()
        band.backgroundColor = shaded ? .secondarySystemBackground : .clear

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        band.addSubview(column)

        var edgeToEdge = false
        if case .choices(_, _, let layout, _) = control.kind, layout == "stack" { edgeToEdge = true }

        let insets: CGFloat = edgeToEdge ? 0 : 24
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: band.topAnchor, constant: edgeToEdge ? 0 : 18),
            column.bottomAnchor.constraint(equalTo: band.bottomAnchor, constant: edgeToEdge ? 0 : -22),
            column.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: insets),
            column.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -insets),
        ])

        if !edgeToEdge, let symbol = control.symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = .secondaryLabel
            icon.contentMode = .left
            icon.setContentHuggingPriority(.required, for: .vertical)
            column.addArrangedSubview(icon)
        }

        switch control.kind {
        case .choices(let options, let multiple, let layout, let columns):
            column.addArrangedSubview(
                makeChoices(control, options: options, multiple: multiple, layout: layout, columns: columns))
        case .slider(let min, let max, let prefix, let suffix, let decimals, let anyLabel, let anyAtMin):
            column.addArrangedSubview(makeSlider(
                control, min: min, max: max, prefix: prefix, suffix: suffix,
                decimals: decimals, anyLabel: anyLabel, anyAtMin: anyAtMin))
        }
        return band
    }

    // MARK: Choices

    private func makeChoices(_ control: FilterControlSpec, options: [FilterOptionSpec],
                             multiple: Bool, layout: String, columns: Int) -> UIView {
        if layout == "segmented" {
            let segmented = UISegmentedControl(items: options.map { $0.title })
            segmented.selectedSegmentTintColor = accent
            segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            let apply = { [weak self] in
                guard let self else { return }
                let chosen = self.selected(control.id).first
                segmented.selectedSegmentIndex = options.firstIndex { $0.id == chosen } ?? UISegmentedControl.noSegment
            }
            apply()
            selectionRefreshers[control.id] = apply
            segmented.addAction(UIAction { [weak self] _ in
                let index = segmented.selectedSegmentIndex
                guard index >= 0 else { return }
                self?.choose(control, option: options[index].id, multiple: false)
            }, for: .valueChanged)
            return segmented
        }

        var buttons: [(FilterOptionSpec, UIButton)] = []
        for option in options {
            let button = makeChoiceButton(option, layout: layout)
            button.addAction(UIAction { [weak self] _ in
                self?.choose(control, option: option.id, multiple: multiple)
            }, for: .touchUpInside)
            buttons.append((option, button))
        }
        let refresh = { [weak self] in
            guard let self else { return }
            let chosen = Set(self.selected(control.id))
            for (option, button) in buttons { button.isSelected = chosen.contains(option.id) }
        }
        refresh()
        selectionRefreshers[control.id] = refresh

        switch layout {
        case "blocks":
            let grid = UIStackView()
            grid.axis = .vertical
            grid.spacing = 2
            let perRow = max(1, columns)
            for start in stride(from: 0, to: buttons.count, by: perRow) {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 2
                let slice = buttons[start..<min(start + perRow, buttons.count)]
                slice.forEach { row.addArrangedSubview($0.1) }
                for _ in slice.count..<perRow { row.addArrangedSubview(UIView()) }
                grid.addArrangedSubview(row)
            }
            return grid
        case "stack":
            let list = UIStackView(arrangedSubviews: buttons.map { $0.1 })
            list.axis = .vertical
            list.spacing = 2
            return list
        case "strip":
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.clipsToBounds = false
            let row = UIStackView(arrangedSubviews: buttons.map { $0.1 })
            row.axis = .horizontal
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
                scroll.heightAnchor.constraint(equalTo: row.heightAnchor),
            ])
            return scroll
        default:
            let flow = FilterFlowView(spacing: layout == "swatches" ? 14 : 8)
            buttons.forEach { flow.addArrangedSubview($0.1) }
            return flow
        }
    }

    private func makeChoiceButton(_ option: FilterOptionSpec, layout: String) -> UIButton {
        let tint = option.tint ?? accent
        let symbol = option.symbol.flatMap { UIImage(systemName: $0) }
        var config = UIButton.Configuration.filled()
        config.title = option.title
        config.baseBackgroundColor = .tertiarySystemFill

        let button: UIButton = layout == "swatches" ? SwatchButton(configuration: config) : UIButton(configuration: config)
        var badge: UIImageView?

        switch layout {
        case "blocks":
            config.imagePlacement = .top
            config.imagePadding = 8
            config.cornerStyle = .fixed
            config.background.cornerRadius = 0
            config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
        case "stack":
            config.imagePlacement = .leading
            config.imagePadding = 14
            config.cornerStyle = .fixed
            config.background.cornerRadius = 0
            config.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20)
            button.contentHorizontalAlignment = .leading
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(check)
            NSLayoutConstraint.activate([
                check.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                check.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -20),
            ])
            badge = check
        case "swatches":
            config.cornerStyle = .capsule
            config.contentInsets = .zero
            config.title = option.title
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.systemFont(ofSize: 12, weight: .bold)
                return attributes
            }
        default:
            config.cornerStyle = .capsule
            config.imagePadding = 6
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        }
        if layout != "swatches" { config.image = symbol }
        button.configuration = config

        button.configurationUpdateHandler = { [accent] button in
            var updated = button.configuration
            let on = button.isSelected
            switch layout {
            case "blocks":
                updated?.baseBackgroundColor = on ? tint : .tertiarySystemFill
                updated?.baseForegroundColor = on ? .white : .label
                updated?.image = symbol?.withTintColor(on ? .white : tint, renderingMode: .alwaysOriginal)
            case "stack":
                updated?.baseBackgroundColor = on ? tint.withAlphaComponent(0.14) : .tertiarySystemFill
                updated?.baseForegroundColor = .label
                updated?.image = symbol?.withTintColor(tint, renderingMode: .alwaysOriginal)
                badge?.tintColor = tint
                badge?.isHidden = !on
            case "swatches":
                updated?.baseBackgroundColor = tint
                updated?.baseForegroundColor = .white
                updated?.background.strokeColor = accent
                updated?.background.strokeWidth = on ? 3 : 0
                updated?.background.strokeOutset = on ? 3 : 0
            default:
                updated?.baseBackgroundColor = on ? tint : .tertiarySystemFill
                updated?.baseForegroundColor = on ? .white : .label
                updated?.image = symbol?.withTintColor(on ? .white : tint, renderingMode: .alwaysOriginal)
            }
            button.configuration = updated
        }
        return button
    }

    // MARK: Slider

    private func makeSlider(_ control: FilterControlSpec, min: Double, max: Double, prefix: String,
                            suffix: String, decimals: Int, anyLabel: String?, anyAtMin: Bool) -> UIView {
        let readout = UILabel()
        readout.font = UIFont.systemFont(ofSize: 34, weight: .semibold)
        readout.adjustsFontSizeToFitWidth = true
        readout.minimumScaleFactor = 0.6

        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.minimumTrackTintColor = accent
        slider.value = Float((values[control.id] as? Double) ?? min)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals

        let update = {
            let value = Double(slider.value)
            let atAny = anyAtMin ? value <= min : value >= max
            if atAny, let anyLabel {
                readout.text = anyLabel
            } else {
                readout.text = prefix + (formatter.string(from: NSNumber(value: value)) ?? "") + suffix
            }
        }
        update()
        slider.addAction(UIAction { [weak self] _ in
            self?.values[control.id] = Double(slider.value)
            update()
            self?.notify()
        }, for: .valueChanged)

        let column = UIStackView(arrangedSubviews: [readout, slider])
        column.axis = .vertical
        column.spacing = 10
        return column
    }
}

// MARK: - Swatch

/// A disc of fixed size. The size comes from the intrinsic content size so the
/// flow layout can measure it without extra constraints.
final class SwatchButton: UIButton {
    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 64) }
}

// MARK: - Wrapping layout

/// Lays its subviews out left to right, wrapping onto new lines, and sizes
/// itself to the lines it needs.
final class FilterFlowView: UIView {
    private let spacing: CGFloat
    private var heightConstraint: NSLayoutConstraint?

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
        let constraint = heightAnchor.constraint(equalToConstant: 0)
        constraint.priority = .required
        constraint.isActive = true
        heightConstraint = constraint
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func addArrangedSubview(_ view: UIView) { addSubview(view) }

    private func place(width: CGFloat, apply: Bool) -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let intrinsic = view.intrinsicContentSize
            let size = intrinsic.width == UIView.noIntrinsicMetric
                ? view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                : intrinsic
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            if apply { view.frame = CGRect(origin: CGPoint(x: x, y: y), size: size) }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return y + lineHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let height = place(width: bounds.width, apply: true)
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
    }
}
