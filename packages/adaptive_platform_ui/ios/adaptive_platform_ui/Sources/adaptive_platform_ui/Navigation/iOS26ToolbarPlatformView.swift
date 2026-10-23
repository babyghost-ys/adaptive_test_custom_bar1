import UIKit
import Flutter

// MARK: - Factory
class iOS26ToolbarFactory: NSObject, FlutterPlatformViewFactory {
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
        return iOS26ToolbarPlatformView(
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

// MARK: - Native navigation state anchor
private final class ToolbarContainerView: UIView {
    var onWindowChange: (() -> Void)?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }
}

/// The platform view is a state/channel anchor. The real native bar belongs to
/// NativeNavigationHost, outside the Flutter surface that it navigates.
class iOS26ToolbarPlatformView: NSObject, FlutterPlatformView, NativeNavigationPage {
    private let containerView: ToolbarContainerView
    private let navigationItem = UINavigationItem()
    private let channel: FlutterMethodChannel
    private var configuredTint: UIColor?
    private var hidesButtonBackground = false
    private var usesLargeTitle = false
    private var verticalNavigation = false
    private var scrollOffset: CGFloat = 0
    private var scrollGeneration = 0
    private var active = true
    private var covered = false
    private var isDark = false
    private var leadingText: String?
    private var perActionTintTags: Set<Int> = []
    private var configuredActions: NSArray?
    private var lastInset: CGFloat?
    private var lastBarBottom: CGFloat?
    private var metricsGeneration = -1

    var nativeNavigationItem: UINavigationItem { navigationItem }
    var nativeLargeTitle: Bool { usesLargeTitle }
    var nativeVerticalNavigation: Bool { verticalNavigation }
    var nativeNeedsBack: Bool { leadingText == "" }
    var nativeScrollOffset: CGFloat { scrollOffset }
    var nativeDark: Bool { isDark }
    var nativeTint: UIColor? { configuredTint }

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger messenger: FlutterBinaryMessenger) {
        containerView = ToolbarContainerView(frame: frame)
        channel = FlutterMethodChannel(name: "adaptive_platform_ui/ios26_toolbar_\(viewId)", binaryMessenger: messenger)
        super.init()
        let params = args as? [String: Any] ?? [:]
        isDark = params["isDark"] as? Bool ?? false
        active = params["active"] as? Bool ?? true
        covered = params["covered"] as? Bool ?? false
        usesLargeTitle = params["largeTitle"] as? Bool ?? false
        verticalNavigation = params["verticalNavigation"] as? Bool ?? false
        scrollOffset = CGFloat(params["scrollOffset"] as? Double ?? 0)
        if let value = params["tint"] as? NSNumber { configuredTint = Self.colorFromARGB(value.intValue) }
        hidesButtonBackground = params["hidesNavigationButtonBackground"] as? Bool ?? false
        configureNavigationAppearance(params)
        configureItems(params)
        containerView.onWindowChange = { [weak self] in
            guard let self, self.active, self.containerView.window != nil else { return }
            NativeNavigationHost.connect(self, from: self.containerView)
        }
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView { containerView }

    func nativeNavigationLayout(contentInset: CGFloat, barBottom: CGFloat) {
        guard contentInset > 0, barBottom > 0 else { return }
        if metricsGeneration != scrollGeneration || lastInset != contentInset || lastBarBottom != barBottom {
            metricsGeneration = scrollGeneration
            lastInset = contentInset
            lastBarBottom = barBottom
            channel.invokeMethod("onNavigationMetrics", arguments: [
                "contentInset": Double(contentInset), "barBottom": Double(barBottom),
                "generation": scrollGeneration
            ])
        }
    }

    func nativeNavigationBack() { leadingTapped() }

    private func layoutScrollController() {
        guard active else { return }
        NativeNavigationHost.connect(self, from: containerView)
        NativeNavigationHost.update(self)
        NativeNavigationHost.setCovered(self, covered)
    }

    private func applyScrollOffset() {
        guard active else { return }
        NativeNavigationHost.scroll(self)
    }

    deinit {
        channel.setMethodCallHandler(nil)
        NativeNavigationHost.deactivate(self)
    }

    private func configureNavigationAppearance(_ params: [String: Any]) {
        NativeBarAppearance.apply(
            NativeBarAppearance.make(
                color: (params["navigationBarColor"] as? NSNumber)?.intValue,
                shadow: params["navigationBarShadow"] as? Bool == true,
                foreground: configuredTint,
                titleStyle: params["titleStyle"] as? [String: Any]),
            to: navigationItem)
    }

    private func configureButtonBackgrounds() {
        if #available(iOS 26.0, *) {
            for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                item.hidesSharedBackground = hidesButtonBackground && !verticalNavigation
            }
        }
        // Duo places the bar's controls in the side rail, outside the coloured
        // title bar. Use system label contrast on that page-coloured surface.
        if hidesButtonBackground && verticalNavigation {
            for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                item.tintColor = .label
            }
        }
    }

    private func configureItems(_ params: [String: Any]) {
        // Title
        if let title = params["title"] as? String {
            navigationItem.title = title
        }

        configuredActions = params["actions"] as? NSArray
        if params.keys.contains("leading") { leadingText = params["leading"] as? String }
        var leadingItems: [UIBarButtonItem] = []
        if let leading = leadingText {
            if !leading.isEmpty {
                leadingItems.append(UIBarButtonItem(title: leading, style: .plain, target: self, action: #selector(leadingTapped)))
            } else if hidesButtonBackground {
                // A regular native item supports hidesSharedBackground; the
                // automatically generated Back item ignores it on current iOS.
                // On Duo it keeps its glass, but as a regular item it replaces
                // the outgoing leading control in place. The generated item
                // arrives only after the push, so the outgoing control's glass
                // first merged into the status cluster above it.
                let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(leadingTapped))
                back.accessibilityLabel = "Back"
                leadingItems.append(back)
            }
        }

        // Process actions
        var leftGroup: [UIBarButtonItem] = []
        var rightGroup: [UIBarButtonItem] = []

        if let actions = params["actions"] as? [[String: Any]] {
            // First pass: check if any flexible spacer exists
            let hasFlexible = actions.contains { ($0["spacerAfter"] as? Int) == 2 }

            // Second pass: build buttons
            var foundFlexible = false

            for (index, action) in actions.enumerated() {
                var button: UIBarButtonItem?

                if let menuEntries = action["menu"] as? [[String: Any]] {
                    let menu = makeMenu(menuEntries, actionIndex: index)
                    if let icon = action["icon"] as? String {
                        button = UIBarButtonItem(
                            image: UIImage(systemName: icon) ?? UIImage(named: icon),
                            menu: menu
                        )
                    } else {
                        button = UIBarButtonItem(
                            title: action["title"] as? String,
                            menu: menu
                        )
                    }
                } else if let icon = action["icon"] as? String {
                    button = UIBarButtonItem(
                        image: UIImage(systemName: icon) ?? UIImage(named: icon),
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                } else if let title = action["title"] as? String {
                    button = UIBarButtonItem(
                        title: title,
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                }

                if let btn = button {
                    btn.tag = index
                    if let label = action["label"] as? String {
                        btn.accessibilityLabel = label
                        // An icon item still shows only its icon in the bar,
                        // but when the bar runs out of room (the Duo's
                        // vertical bar above a tall tab rail) UIKit folds it
                        // into a "more" menu, which lists it by this title.
                        if btn.image != nil, btn.title == nil { btn.title = label }
                    }

                    // Apply prominent style (iOS 26+)
                    if action["prominent"] as? Bool == true {
                        if #available(iOS 26.0, *) {
                            btn.style = .prominent
                        }
                    }

                    // Apply per-action tint color
                    if let n = action["tint"] as? NSNumber {
                        btn.tintColor = Self.colorFromARGB(n.intValue)
                        perActionTintTags.insert(index)
                    }

                    // If no flexible spacer exists, all go to right
                    // If flexible exists, split by it
                    if !hasFlexible {
                        rightGroup.append(btn)
                    } else if !foundFlexible {
                        leftGroup.append(btn)
                    } else {
                        rightGroup.append(btn)
                    }

                    // Check for spacers
                    if let spacerAfter = action["spacerAfter"] as? Int {
                        if spacerAfter == 1 {
                            // Fixed space
                            if #available(iOS 16.0, *) {
                                if !hasFlexible {
                                    rightGroup.append(.fixedSpace(12))
                                } else if !foundFlexible {
                                    leftGroup.append(.fixedSpace(12))
                                } else {
                                    rightGroup.append(.fixedSpace(12))
                                }
                            }
                        } else if spacerAfter == 2 {
                            // Flexible spacer - mark split point
                            foundFlexible = true
                        }
                    }
                }
            }
        }

        // Assign to navigation item
        // On Duo, match each page's first leading control across pushes and
        // pops, so UIKit morphs one glass item (menu into Back) instead of
        // dissolving the outgoing glass before the incoming one appears.
        // Without glass, a match only swaps the symbol ahead of the titles.
        if #available(iOS 26.0, *), verticalNavigation {
            (leadingItems + leftGroup).first?.identifier = Self.leadingIdentifier
        }
        navigationItem.leftBarButtonItems = leadingItems + leftGroup
        navigationItem.rightBarButtonItems = rightGroup.reversed()
        if let configuredTint {
            for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                if !perActionTintTags.contains(item.tag) { item.tintColor = configuredTint }
            }
        }
        configureButtonBackgrounds()
        NativeNavigationHost.update(self)
    }

    /// Builds the menu of a bar button; dividers split it into inline groups
    private func makeMenu(_ entries: [[String: Any]], actionIndex: Int) -> UIMenu {
        var groups: [[UIMenuElement]] = []
        var current: [UIMenuElement] = []

        for (itemIndex, entry) in entries.enumerated() {
            if entry["divider"] as? Bool == true {
                if !current.isEmpty { groups.append(current); current = [] }
                continue
            }

            let title = entry["title"] as? String ?? ""
            let image = (entry["icon"] as? String).flatMap {
                UIImage(systemName: $0) ?? UIImage(named: $0)
            }
            var attributes: UIMenuElement.Attributes = []
            if entry["enabled"] as? Bool == false { attributes.insert(.disabled) }
            if entry["destructive"] as? Bool == true { attributes.insert(.destructive) }

            let subtitle = entry["subtitle"] as? String
            let action = UIAction(
                title: title,
                subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                image: image,
                attributes: attributes,
                state: entry["selected"] as? Bool == true ? .on : .off
            ) { [weak self] _ in
                self?.channel.invokeMethod(
                    "onMenuItemTapped",
                    arguments: ["action": actionIndex, "item": itemIndex]
                )
            }
            current.append(action)
        }
        if !current.isEmpty { groups.append(current) }

        return UIMenu(
            title: "",
            children: groups.map { UIMenu(title: "", options: .displayInline, children: $0) }
        )
    }

    @objc private func leadingTapped() {
        channel.invokeMethod("onLeadingTapped", arguments: nil)
    }

    @objc private func actionTapped(_ sender: UIBarButtonItem) {
        channel.invokeMethod("onActionTapped", arguments: ["index": sender.tag])
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setActive":
            if let args = call.arguments as? [String: Any], let value = args["active"] as? Bool {
                active = value
                if value { layoutScrollController() } else { NativeNavigationHost.deactivate(self) }
            }
            result(nil)
        case "setCovered":
            if let args = call.arguments as? [String: Any], let value = args["covered"] as? Bool {
                covered = value
                if active { NativeNavigationHost.setCovered(self, value) }
            }
            result(nil)
        case "syncLargeTitleLayout":
            metricsGeneration = -1
            layoutScrollController()
            result(nil)
        case "setNavigationPage":
            if let args = call.arguments as? [String: Any],
               let generation = args["generation"] as? Int,
               generation >= scrollGeneration,
               let offset = args["offset"] as? Double, offset.isFinite {
                scrollGeneration = generation
                scrollOffset = CGFloat(offset)
                metricsGeneration = -1
                UIView.performWithoutAnimation {
                    navigationItem.title = args["title"] as? String ?? ""
                    layoutScrollController()
                }
            }
            result(nil)
        case "setScrollOffset":
            if let args = call.arguments as? [String: Any],
               args["generation"] as? Int == scrollGeneration,
               let offset = args["offset"] as? Double, offset.isFinite {
                scrollOffset = CGFloat(offset)
                applyScrollOffset()
            }
            result(nil)
        case "setTitleImage":
            let args = call.arguments as? [String: Any]
            if let data = (args?["bytes"] as? FlutterStandardTypedData)?.data,
               let scale = (args?["scale"] as? NSNumber)?.doubleValue,
               let image = UIImage(data: data, scale: CGFloat(scale)) {
                navigationItem.titleView = UIImageView(image: image)
            } else {
                navigationItem.titleView = nil
            }
            NativeNavigationHost.update(self)
            NativeNavigationHost.setTitleView(self, navigationItem.titleView)
            result(nil)
        case "updateTitle":
            if let args = call.arguments as? [String: Any], let title = args["title"] as? String {
                navigationItem.title = title
                NativeNavigationHost.update(self)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        case "setBrightness":
            if let args = call.arguments as? [String: Any],
               let dark = args["isDark"] as? Bool {
                isDark = dark
                if #available(iOS 13.0, *) {
                    containerView.overrideUserInterfaceStyle = dark ? .dark : .light
                    NativeNavigationHost.update(self)
                }
            }
            result(nil)
        case "updateActions":
            // Dart resends its actions whenever an anchor is created. Keep the
            // existing items when nothing changed: new instances restart their
            // glass and flash right after a push or pop.
            if let args = call.arguments as? [String: Any],
               (args["actions"] as? NSArray) != configuredActions {
                perActionTintTags.removeAll()
                configureItems(args)
                // Re-apply global tint to items without per-action tint
                if let globalTint = configuredTint {
                    for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                        if !perActionTintTags.contains(item.tag) {
                            item.tintColor = globalTint
                        }
                    }
                }
            }
            configureButtonBackgrounds()
            result(nil)
        case "setButtonBackground":
            if let args = call.arguments as? [String: Any] {
                let hidden = args["hidden"] as? Bool ?? false
                let changed = hidden != hidesButtonBackground
                hidesButtonBackground = hidden
                // Recreate only the leading item, and only when this policy
                // changes. A new instance on every resync restarts the item's
                // glass, which shows as a flash right after a push.
                if changed, leadingText == "" {
                    var items = navigationItem.leftBarButtonItems ?? []
                    items.removeAll { $0.accessibilityLabel == "Back" }
                    if hidesButtonBackground {
                        let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(leadingTapped))
                        back.accessibilityLabel = "Back"
                        back.tintColor = configuredTint
                        if #available(iOS 26.0, *), verticalNavigation { back.identifier = Self.leadingIdentifier }
                        items.insert(back, at: 0)
                    }
                    navigationItem.leftBarButtonItems = items
                }
                configureButtonBackgrounds()
                NativeNavigationHost.update(self)
            }
            result(nil)
        case "setNavigationBarColor":
            if let args = call.arguments as? [String: Any] {
                configureNavigationAppearance(args)
                NativeNavigationHost.update(self)
            }
            result(nil)
        case "setStyle":
            if let args = call.arguments as? [String: Any] {
                if let tintValue = args["tint"] {
                    if let n = tintValue as? NSNumber {
                        let color = Self.colorFromARGB(n.intValue)
                        containerView.tintColor = color
                        configuredTint = color
                        for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                            if !perActionTintTags.contains(item.tag) {
                                item.tintColor = color
                            }
                        }
                    } else if tintValue is NSNull {
                        containerView.tintColor = .label
                        configuredTint = nil
                        for item in (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? []) {
                            if !perActionTintTags.contains(item.tag) {
                                item.tintColor = nil
                            }
                        }
                    }
                }
            }
            configureButtonBackgrounds()
            NativeNavigationHost.update(self)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Marks the leading control UIKit morphs between pages on Duo.
    static let leadingIdentifier = "adaptive_platform_ui.leading"

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
