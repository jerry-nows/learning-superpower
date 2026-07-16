import LoginPresentation
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

        let loginViewController = coordinator.rootViewController.viewControllers.first
        #expect(loginViewController is LoginViewController)
        loginViewController?.loadViewIfNeeded()
        #expect(loginViewController?.title == "Sign in")
    }
}
