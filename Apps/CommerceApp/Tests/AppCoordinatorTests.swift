import LoginPresentation
import MenuPresentation
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

    @Test("authenticated route replaces login with product list")
    func authenticatedRoutePresentsProducts() async throws {
        let coordinator = AppCoordinator()

        await coordinator.strongRouter.trigger(.authenticated)
        try await Task.sleep(for: .milliseconds(100))

        let productList = coordinator.rootViewController.viewControllers.first
        #expect(productList is ProductListViewController)
        productList?.loadViewIfNeeded()
        #expect(productList?.title == "Products")
    }
}
