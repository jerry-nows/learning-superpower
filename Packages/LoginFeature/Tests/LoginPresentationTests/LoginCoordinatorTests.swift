#if canImport(UIKit)
import LoginDomain
import UIKit
import XCTest
@testable import LoginPresentation

@MainActor
final class LoginCoordinatorTests: XCTestCase {
    func testCoordinatorForwardsOnlyTerminalLoginResult() async {
        let authenticator = CoordinatorAuthenticator()
        let coordinator = LoginCoordinator(authenticator: authenticator)
        var received: LoginResult?
        coordinator.onResult = { result in received = result }

        let viewController = coordinator.makeViewController()
        viewController.loadViewIfNeeded()
        let fields = descendants(of: viewController.view, matching: UITextField.self)
        fields.first { $0.textContentType == .emailAddress }?.text = "user@example.com"
        fields.first { $0.textContentType == .password }?.text = "secret"
        descendants(of: viewController.view, matching: UIButton.self)
            .first { $0.title(for: .normal) == "Sign in" }?
            .sendActions(for: .touchUpInside)
        await Task.yield()

        XCTAssertEqual(received, .authenticated(userID: "user-1"))
    }

    func testCoordinatorPassesConfigurationToInjectedViewModelFactory() {
        let configuration = LoginConfiguration(
            biometricPolicy: .disabled,
            localeIdentifier: "vi-VN",
            copyPolicy: .fixed
        )
        let input = LoginFlowInput(configuration: configuration)
        var factoryInput: LoginFlowInput?
        let coordinator = LoginCoordinator(
            input: input,
            authenticator: CoordinatorAuthenticator(),
            viewModelFactory: { input, authenticator in
                factoryInput = input
                return LoginViewModel(input: input, authenticator: authenticator)
            }
        )

        _ = coordinator.makeViewController()

        XCTAssertEqual(factoryInput, input)
        XCTAssertEqual(coordinator.input, input)
    }

    func testCoordinatorProducesFeatureControllerWithoutExposingTransportTypes() {
        let coordinator = LoginCoordinator(authenticator: CoordinatorAuthenticator())

        let controller = coordinator.makeViewController()

        XCTAssertTrue(controller is LoginViewController)
        XCTAssertNil(controller.restorationIdentifier)
    }

    private func descendants<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            let matches = child as? T
            return (matches.map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }
}

private struct CoordinatorAuthenticator: LoginAuthenticator {
    func authenticate(email: String, password: String) async throws -> String {
        "user-1"
    }
}
#endif
