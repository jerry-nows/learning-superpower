import Testing
import UIKit
import LoginPresentation

@testable import CommerceApp

@MainActor
@Suite("AppCoordinator")
struct AppCoordinatorTests {
    @Test("start presents the login entry screen")
    func startPresentsLogin() async throws {
        let coordinator = AppCoordinator()

        coordinator.start()
        try await Task.sleep(for: .milliseconds(100))

        let loginViewController = coordinator.rootViewController.viewControllers.first
        #expect(loginViewController is LoginViewController)
        #expect(loginViewController?.title == "Sign in")
    }
}
