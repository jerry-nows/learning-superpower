import Testing
import UIKit

@testable import CommerceApp
import LoginDomain
import LoginPresentation
import MenuDomain
import MenuPresentation

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
        var invoked = false
        let replacement: LoginViewModelFactory = { input, authenticator in
            invoked = true
            return LoginViewModel(input: input, authenticator: authenticator)
        }
        AppContainer.shared.loginCoordinator.register { replacement }
        defer { AppContainer.shared.loginCoordinator.reset() }

        let coordinator = AppContainer.shared.makeLoginCoordinator()
        let viewController = coordinator.makeViewController()

        #expect(viewController is LoginViewController)
        #expect(invoked)
    }

    @Test("menu flow factory can be replaced at the composition boundary")
    func menuFlowFactoryCanBeReplaced() {
        var invoked = false
        let replacement: MenuViewModelFactory = { _, source in
            invoked = true
            return ProductListViewModel(source: source)
        }
        AppContainer.shared.menuCoordinator.register { replacement }
        defer { AppContainer.shared.menuCoordinator.reset() }

        let coordinator = AppContainer.shared.makeMenuCoordinator()
        _ = coordinator.makeViewController()

        #expect(invoked)
    }
}

@MainActor
private final class CoordinatorSpy: ApplicationCoordinating {
    let rootViewController = UINavigationController()

    func start() {}
}
