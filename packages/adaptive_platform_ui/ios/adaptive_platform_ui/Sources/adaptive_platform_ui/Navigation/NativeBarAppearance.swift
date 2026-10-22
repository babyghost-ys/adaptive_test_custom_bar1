import UIKit

/// The app's bar style as UIKit appearance, shared by every native bar so a
/// toolbar and a search header look the same.
enum NativeBarAppearance {
    /// An opaque bar of `color` (ARGB), or nil for the system's own bar.
    static func make(color: Int?, shadow: Bool, foreground: UIColor?) -> UINavigationBarAppearance? {
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
        return style
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
    private static let shadowImage: UIImage = {
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
