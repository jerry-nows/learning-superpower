import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite("ColorToken")
struct ColorTokenTests {
    @Test("background adapts to interface style")
    func backgroundAdaptsToInterfaceStyle() {
        let light = ColorToken.backgroundPrimary.color.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        let dark = ColorToken.backgroundPrimary.color.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )

        #expect(light != dark)
    }

    @Test("every semantic token resolves an opaque color")
    func everyTokenResolves() {
        for token in ColorToken.allCases {
            let resolved = token.color.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            )
            #expect(resolved.cgColor.alpha == 1)
        }
    }
}
