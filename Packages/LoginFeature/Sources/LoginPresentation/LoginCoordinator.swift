import LoginDomain
import UIKit

/// Factory used by the composition root to replace the view model in tests or
/// in an alternate application configuration.
public typealias LoginViewModelFactory = @MainActor (
    _ input: LoginFlowInput,
    _ authenticator: any LoginAuthenticator
) -> LoginViewModel

/// UIKit flow boundary for LoginFeature.
///
/// The coordinator owns construction only. The application receives a stable
/// `LoginResult` callback and never needs to know about view models, text
/// fields, tokens, or transport errors.
@MainActor
public final class LoginCoordinator {
    public let input: LoginFlowInput

    private let authenticator: any LoginAuthenticator
    private let viewModelFactory: LoginViewModelFactory

    /// Terminal flow results delivered to the application composition root.
    public var onResult: (@MainActor (LoginResult) -> Void)?

    public init(
        input: LoginFlowInput = .init(),
        authenticator: any LoginAuthenticator,
        viewModelFactory: @escaping LoginViewModelFactory = { input, authenticator in
            LoginViewModel(input: input, authenticator: authenticator)
        },
        onResult: (@MainActor (LoginResult) -> Void)? = nil
    ) {
        self.input = input
        self.authenticator = authenticator
        self.viewModelFactory = viewModelFactory
        self.onResult = onResult
    }

    /// Creates the feature's entry controller for presentation by the host.
    public func makeViewController() -> LoginViewController {
        let viewModel = viewModelFactory(input, authenticator)
        let viewController = LoginViewController(viewModel: viewModel)
        viewController.onResult = { [weak self] result in
            self?.onResult?(result)
        }
        return viewController
    }
}
