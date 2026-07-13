import UIKit

public enum TypographyToken: CaseIterable, Sendable {
    case displayLarge
    case title
    case body
    case caption

    public var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .displayLarge, .title:
            .serif
        case .body, .caption:
            .default
        }
    }

    @MainActor
    public func font(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: pointSize, weight: weight)
        let descriptor = baseFont.fontDescriptor.withDesign(design) ?? baseFont.fontDescriptor
        let designedFont = UIFont(descriptor: descriptor, size: pointSize)

        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: designedFont,
            compatibleWith: traits
        )
    }

    private var pointSize: CGFloat {
        switch self {
        case .displayLarge: 40
        case .title: 24
        case .body: 17
        case .caption: 13
        }
    }

    private var weight: UIFont.Weight {
        switch self {
        case .displayLarge: .bold
        case .title: .semibold
        case .body, .caption: .regular
        }
    }

    private var textStyle: UIFont.TextStyle {
        switch self {
        case .displayLarge: .largeTitle
        case .title: .title2
        case .body: .body
        case .caption: .caption1
        }
    }
}
