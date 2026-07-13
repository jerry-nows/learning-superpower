import UIKit

public enum ColorToken: CaseIterable, Sendable {
    case backgroundPrimary
    case backgroundSecondary
    case surface
    case textPrimary
    case textSecondary
    case accent
    case separator
    case success
    case warning
    case error
    case skeletonBase
    case skeletonHighlight

    @MainActor
    public var color: UIColor {
        let values = colorValues
        return UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? values.dark : values.light)
        }
    }

    private var colorValues: (light: UInt32, dark: UInt32) {
        switch self {
        case .backgroundPrimary: (0xF7F3ED, 0x161411)
        case .backgroundSecondary: (0xEEE7DE, 0x211E1A)
        case .surface: (0xFFFCF8, 0x29251F)
        case .textPrimary: (0x241F1A, 0xF7F3ED)
        case .textSecondary: (0x6F655A, 0xBEB2A5)
        case .accent: (0x8C6547, 0xD2A77F)
        case .separator: (0xD9CEC1, 0x433C34)
        case .success: (0x477A56, 0x7EB68A)
        case .warning: (0xA36A24, 0xD9A15A)
        case .error: (0xA6453D, 0xE08379)
        case .skeletonBase: (0xE4DCD2, 0x35302A)
        case .skeletonHighlight: (0xF3EDE6, 0x494139)
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
