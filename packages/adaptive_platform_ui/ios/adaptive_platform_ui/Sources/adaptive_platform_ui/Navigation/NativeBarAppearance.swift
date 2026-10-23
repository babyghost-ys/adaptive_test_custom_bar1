import UIKit

/// The app's bar style as UIKit appearance, shared by every native bar so a
/// toolbar and a search header look the same.
enum NativeBarAppearance {
    /// An opaque bar of `color` (ARGB), or nil for the system's own bar.
    /// Carries the app's own title font through the package's bar restyling,
    /// which otherwise replaces every title font with its own.
    static let titleFontKey = NSAttributedString.Key("adaptive_platform_ui.titleFont")

    static func make(color: Int?, shadow: Bool, foreground: UIColor?,
                     titleStyle: [String: Any]? = nil) -> UINavigationBarAppearance? {
        guard let color else { return nil }
        let style = UINavigationBarAppearance()
        style.configureWithOpaqueBackground()
        style.backgroundColor = UIColor(argb: color)
        if shadow {
            // A short fade UIKit draws below the bar, tinted faintly.
            style.shadowImage = shadowImage
            style.shadowColor = UIColor.black.withAlphaComponent(0.1)
        } else {
            style.shadowColor = .clear
        }
        if let foreground {
            style.titleTextAttributes = [.foregroundColor: foreground]
            style.largeTitleTextAttributes = [.foregroundColor: foreground]
        }
        if let titleStyle, let font = font(from: titleStyle) {
            style.titleTextAttributes[.font] = font
            style.titleTextAttributes[titleFontKey] = font
            // Large titles take the same family and weight at the system's
            // large size.
            var large = titleStyle
            large["fontSize"] = 34
            if let largeFont = Self.font(from: large) {
                style.largeTitleTextAttributes[.font] = largeFont
                style.largeTitleTextAttributes[titleFontKey] = largeFont
            }
        }
        return style
    }

    /// The font a Flutter `TextStyle` (family, size, weight) describes. A
    /// family the device does not have falls back to the system font.
    static func font(from style: [String: Any]) -> UIFont? {
        let size = CGFloat((style["fontSize"] as? NSNumber)?.doubleValue ?? 17)
        let weight = (style["fontWeight"] as? NSNumber)?.intValue
        let system: UIFont.Weight = switch weight ?? 600 {
        case 800...: .heavy
        case 700...: .bold
        case 600...: .semibold
        case 500...: .medium
        default: .regular
        }
        if let family = style["fontFamily"] as? String {
            var base = UIFont(name: family, size: size)
            if base == nil, let first = UIFont.fontNames(forFamilyName: family).first {
                base = UIFont(name: first, size: size)
            }
            if let base {
                if system.rawValue >= UIFont.Weight.bold.rawValue,
                   !base.fontDescriptor.symbolicTraits.contains(.traitBold),
                   let bold = base.fontDescriptor.withSymbolicTraits(
                    base.fontDescriptor.symbolicTraits.union(.traitBold)) {
                    return UIFont(descriptor: bold, size: size)
                }
                return base
            }
        }
        guard style["fontSize"] != nil || style["fontWeight"] != nil || style["fontFamily"] != nil else { return nil }
        return .systemFont(ofSize: size, weight: system)
    }

    /// Applies [appearance] to every bar state of [item].
    static func apply(_ appearance: UINavigationBarAppearance?, to item: UINavigationItem) {
        item.standardAppearance = appearance
        item.scrollEdgeAppearance = appearance
        item.compactAppearance = appearance
        item.compactScrollEdgeAppearance = appearance
    }

    /// Whether a bar of `color` (ARGB) needs light content on it.
    static func isDark(_ color: Int) -> Bool {
        var white: CGFloat = 0
        UIColor(argb: color).getWhite(&white, alpha: nil)
        return white < 0.5
    }

    /// A vertical fade from opaque to clear. As a template image, the
    /// appearance's shadowColor sets its strength.
    static let shadowImage: UIImage = {
        let size = CGSize(width: 1, height: 6)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: 0, y: size.height), options: [])
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
}
