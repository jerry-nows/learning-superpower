import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite("TypographyToken")
struct TypographyTests {
    @Test("display typography uses a serif design")
    func displayUsesSerifDesign() {
        #expect(TypographyToken.displayLarge.design == .serif)
    }

    @Test("body typography scales for accessibility sizes")
    func bodyScalesForAccessibility() {
        let standard = TypographyToken.body.font(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let accessibility = TypographyToken.body.font(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )

        #expect(accessibility.pointSize > standard.pointSize)
    }
}
