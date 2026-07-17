import Testing
import UIKit

@testable import CommerceApp

@MainActor
@Suite("AppCoordinator")
struct AppCoordinatorTests {
    @Test("start presents the injected child flow controller")
    func startPresentsInjectedChildFlow() async throws {
        let childFlow = ChildFlowSpy()
        let coordinator = AppCoordinator(loginFlowFactory: { childFlow })

        coordinator.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.rootViewController.viewControllers.first === childFlow.rootViewController)
    }

    @Test("start presents the login entry screen")
    func startPresentsLogin() async throws {
        let coordinator = AppCoordinator()

        coordinator.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.rootViewController.viewControllers.first?.title == "Sign in")
    }
}

@MainActor
private final class ChildFlowSpy: ApplicationChildFlow {
    let rootViewController = UIViewController()
}
