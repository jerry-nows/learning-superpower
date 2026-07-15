#if canImport(UIKit)
import LoginDomain
@testable import LoginPresentation
import UIKit
import XCTest

@MainActor
final class LoginViewControllerTests: XCTestCase {
    func testLoginFormExposesAccessibleLabelsAndSecurePasswordEntry() {
        let viewController = makeViewController()
        load(viewController)

        let fields = descendants(of: viewController.view, matching: UITextField.self)
        let email = try! XCTUnwrap(fields.first { $0.textContentType == .emailAddress })
        let password = try! XCTUnwrap(fields.first { $0.textContentType == .password })

        XCTAssertEqual(email.accessibilityLabel, "Email address")
        XCTAssertEqual(password.accessibilityLabel, "Password")
        XCTAssertTrue(password.isSecureTextEntry)
        XCTAssertTrue(email.accessibilityTraits.contains(.none))
        XCTAssertTrue(password.accessibilityTraits.contains(.none))
    }

    func testLoginFormUsesReadableLabelsAndMinimumTouchTargets() {
        let viewController = makeViewController()
        load(viewController)

        let labels = descendants(of: viewController.view, matching: UILabel.self)
        XCTAssertTrue(labels.contains { $0.text == "Welcome back" })
        XCTAssertTrue(labels.contains { $0.text == "Sign in to continue shopping" })

        let button = try! XCTUnwrap(
            descendants(of: viewController.view, matching: UIButton.self)
                .first { $0.title(for: .normal) == "Sign in" }
        )
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        for field in descendants(of: viewController.view, matching: UITextField.self) {
            XCTAssertGreaterThanOrEqual(field.bounds.height, 44)
        }
    }

    func testLoginFormSupportsDynamicType() {
        let viewController = makeViewController()
        load(viewController)

        let labels = descendants(of: viewController.view, matching: UILabel.self)
        XCTAssertTrue(labels.filter { $0.text != nil }.allSatisfy { $0.adjustsFontForContentSizeCategory })
        let button = descendants(of: viewController.view, matching: UIButton.self).first
        XCTAssertTrue(button?.titleLabel?.adjustsFontForContentSizeCategory == true)
    }

    func testSubmittingValidCredentialsShowsLoadingWithoutNetworkDependency() {
        let authenticator = StubAuthenticator(result: .suspended)
        let viewModel = LoginViewModel(authenticator: authenticator)
        let viewController = LoginViewController(viewModel: viewModel)
        load(viewController)

        let fields = descendants(of: viewController.view, matching: UITextField.self)
        let email = fields.first { $0.textContentType == .emailAddress }
        let password = fields.first { $0.textContentType == .password }
        email?.text = "user@example.com"
        password?.text = "secret"
        let button = descendants(of: viewController.view, matching: UIButton.self).first
        button?.sendActions(for: .touchUpInside)

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertFalse(button?.isEnabled ?? true)
        XCTAssertTrue(descendants(of: viewController.view, matching: UIActivityIndicatorView.self).first?.isAnimating == true)
        viewModel.cancel()
    }

    func testValidationErrorIsRenderedForInvalidCredentials() {
        let viewModel = LoginViewModel(authenticator: StubAuthenticator(result: .success("unused")))
        let viewController = LoginViewController(viewModel: viewModel)
        load(viewController)

        let button = descendants(of: viewController.view, matching: UIButton.self).first
        button?.sendActions(for: .touchUpInside)

        let errorLabel = descendants(of: viewController.view, matching: UILabel.self)
            .first { $0.text == "Enter a valid email and password." }
        XCTAssertNotNil(errorLabel)
        XCTAssertFalse(errorLabel?.isHidden ?? true)
    }

    private func makeViewController() -> LoginViewController {
        LoginViewController(viewModel: LoginViewModel(authenticator: StubAuthenticator(result: .success("unused"))))
    }

    private func load(_ viewController: UIViewController) {
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
    }

    private func descendants<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            let matches = child as? T
            return (matches.map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }
}

private struct StubAuthenticator: LoginAuthenticator {
    enum Result: Sendable { case success(String); case suspended }
    let result: Result

    func authenticate(email: String, password: String) async throws -> String {
        switch result {
        case let .success(userID): return userID
        case .suspended:
            try await Task.sleep(for: .seconds(30))
            return "suspended"
        }
    }
}
#endif
