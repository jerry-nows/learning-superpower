import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite("ConnectivityBanner")
struct ConnectivityBannerTests {
    @Test("offline state announces connection loss")
    func offlineStateIsAccessible() {
        let banner = ConnectivityBanner()

        banner.show(.offline)

        #expect(banner.accessibilityLabel == "No internet connection")
        #expect(banner.accessibilityValue == "Waiting to reconnect")
    }

    @Test("restored state announces recovery")
    func restoredStateIsAccessible() {
        let banner = ConnectivityBanner()

        banner.show(.restored)

        #expect(banner.accessibilityLabel == "Internet connection restored")
        #expect(banner.accessibilityValue == nil)
    }
}
