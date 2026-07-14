import Testing
import UIKit

@testable import CommerceApp
import LoginDomain
import LoginPresentation

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

    @Test("login flow factory can be replaced at the composition boundary")
    func loginFlowFactoryCanBeReplaced() {
        let replacement: LoginViewModelFactory = { input, authenticator in
            LoginViewModel(input: input, authenticator: authenticator)
        }
        AppContainer.shared.loginCoordinator.register { replacement }
        defer { AppContainer.shared.loginCoordinator.reset() }

        let coordinator = AppContainer.shared.makeLoginCoordinator()
        let viewController = coordinator.makeViewController()

        #expect(viewController is LoginViewController)
    }
}

@MainActor
private final class CoordinatorSpy: ApplicationCoordinating {
    let rootViewController = UINavigationController()

    func start() {}
}
