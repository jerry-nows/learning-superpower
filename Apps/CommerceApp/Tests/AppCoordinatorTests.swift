import Testing
import UIKit

@testable import CommerceApp

@MainActor
@Suite("AppCoordinator")
struct AppCoordinatorTests {
    @Test("start presents the login entry screen")
    func startPresentsLogin() async throws {
        let coordinator = AppCoordinator()

        coordinator.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.rootViewController.viewControllers.first?.title == "Sign in")
    }
}
