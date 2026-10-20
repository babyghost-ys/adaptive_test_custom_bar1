import Flutter
import UIKit

/// One font family for the package's native UIKit components.
///
/// Components read `font(size:weight:)` when they style their text and
/// observe `didChange` to restyle live. Bars managed by UIKit (navigation
/// bar titles and buttons, tab bar labels, search fields) are restyled here,
/// both through appearance proxies for bars created later and directly for
/// bars already on screen. System menus, alerts, action sheets and date
/// pickers have no public font API and keep the system font.
enum AdaptiveNativeFonts {
    static let didChange = Notification.Name("AdaptiveNativeFontsDidChange")

    /// The family in use, or nil for the system font.
    private(set) static var family: String?

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "adaptive_platform_ui/native_fonts", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "setFamily":
                let name = (call.arguments as? [String: Any])?["family"] as? String
                setFamily(name?.isEmpty == false ? name : nil)
                result(nil)
            case "availableFamilies":
                result(UIFont.familyNames.sorted())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    static func setFamily(_ name: String?) {
        // Ignore a family the system does not have rather than falling back
        // to an unexpected face.
        let resolved = name.flatMap { UIFont.fontNames(forFamilyName: $0).isEmpty ? nil : $0 }
        guard resolved != family else { return }
        family = resolved
        applyAppearanceProxies()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { restyle(window) }
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The configured family at `size`, as close to `weight` as the family
    /// offers, or the system font when no family is set.
    static func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        guard let family else { return .systemFont(ofSize: size, weight: weight) }
        var descriptor = UIFontDescriptor(fontAttributes: [.family: family])
        if weight.rawValue >= UIFont.Weight.semibold.rawValue,
           let bold = descriptor.withSymbolicTraits(.traitBold) {
            descriptor = bold
        }
        let font = UIFont(descriptor: descriptor, size: size)
        // A descriptor that matched nothing falls back to Helvetica.
        return font.familyName == family ? font : UIFont(name: family, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Bars

    private static func titleAttributes(size: CGFloat, weight: UIFont.Weight) -> [NSAttributedString.Key: Any] {
        family == nil ? [:] : [.font: font(size: size, weight: weight)]
    }

    private static func styled(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
        let copy = appearance.copy()
        copy.titleTextAttributes.removeValue(forKey: .font)
        copy.largeTitleTextAttributes.removeValue(forKey: .font)
        copy.titleTextAttributes.merge(titleAttributes(size: 17, weight: .semibold)) { $1 }
        copy.largeTitleTextAttributes.merge(titleAttributes(size: 34, weight: .bold)) { $1 }
        let button = UIBarButtonItemAppearance(style: .plain)
        button.normal.titleTextAttributes = titleAttributes(size: 17, weight: .regular)
        copy.buttonAppearance = button
        copy.backButtonAppearance = button
        let done = UIBarButtonItemAppearance(style: .done)
        done.normal.titleTextAttributes = titleAttributes(size: 17, weight: .semibold)
        copy.doneButtonAppearance = done
        return copy
    }

    private static func styled(_ appearance: UITabBarAppearance) -> UITabBarAppearance {
        let copy = appearance.copy()
        let attributes = titleAttributes(size: 10, weight: .medium)
        for layout in [copy.stackedLayoutAppearance, copy.inlineLayoutAppearance, copy.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected] {
                state.titleTextAttributes.removeValue(forKey: .font)
                state.titleTextAttributes.merge(attributes) { $1 }
            }
        }
        return copy
    }

    private static func applyAppearanceProxies() {
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = styled(bar.standardAppearance)
        bar.scrollEdgeAppearance = styled(bar.scrollEdgeAppearance ?? bar.standardAppearance)
        bar.compactAppearance = styled(bar.compactAppearance ?? bar.standardAppearance)
        let tabs = UITabBar.appearance()
        tabs.standardAppearance = styled(tabs.standardAppearance)
        tabs.scrollEdgeAppearance = styled(tabs.scrollEdgeAppearance ?? tabs.standardAppearance)
    }

    /// Whether `attributes` already use the configured family.
    private static func matches(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        let current = (attributes[.font] as? UIFont)?.familyName
        return current == family
    }

    /// Restyles a bar that was created or reset after the family changed,
    /// such as the bar of a page pushed later. Cheap when already styled.
    static func ensureStyled(_ bar: UINavigationBar) {
        guard !matches(bar.standardAppearance.largeTitleTextAttributes)
                || !matches(bar.standardAppearance.titleTextAttributes) else { return }
        restyle(bar)
    }

    static func ensureStyled(_ bar: UITabBar) {
        guard !matches(bar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes) else { return }
        restyle(bar)
    }

    /// Restyles bars and search fields already in `view`'s hierarchy.
    static func restyle(_ view: UIView) {
        switch view {
        case let bar as UINavigationBar:
            bar.standardAppearance = styled(bar.standardAppearance)
            if let edge = bar.scrollEdgeAppearance { bar.scrollEdgeAppearance = styled(edge) }
            else { bar.scrollEdgeAppearance = styled(bar.standardAppearance) }
            if let compact = bar.compactAppearance { bar.compactAppearance = styled(compact) }
        case let tabs as UITabBar:
            tabs.standardAppearance = styled(tabs.standardAppearance)
            tabs.scrollEdgeAppearance = styled(tabs.scrollEdgeAppearance ?? tabs.standardAppearance)
        case let field as UISearchTextField:
            field.font = font(size: 17)
        default:
            break
        }
        for subview in view.subviews { restyle(subview) }
    }
}
