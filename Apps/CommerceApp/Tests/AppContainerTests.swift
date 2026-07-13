import Testing
import UIKit

@testable import CommerceApp

@MainActor
@Suite("AppContainer")
struct AppContainerTests {
    @Test("composition root permits coordinator replacement")
    func coordinatorCanBeReplaced() {
        let replacement = CoordinatorSpy()
        AppContainer.shared.appCoordinator.register { replacement }
        defer { AppContainer.shared.appCoordinator.reset() }

        let resolved = AppContainer.shared.makeAppCoordinator()

        #expect(resolved === replacement)
    }
}

@MainActor
private final class CoordinatorSpy: ApplicationCoordinating {
    let rootViewController = UINavigationController()

    func start() {}
}
