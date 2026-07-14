import Testing
@testable import LoginPresentation
import LoginDomain

@Test func presentationModuleIsAvailable() {
    #expect(LoginPresentation.moduleName == "LoginPresentation")
}

private struct FakeAuthenticator: LoginAuthenticator {
    let result: Result<String, LoginAuthenticationError>

    func authenticate(email: String, password: String) async throws -> String {
        try result.get()
    }
}

@Test @MainActor
func invalidCredentialsAreValidatedBeforeCallingAuthenticator() {
    let viewModel = LoginViewModel(authenticator: FakeAuthenticator(result: .success("ignored")))
    viewModel.submit(email: "bad", password: "")
    #expect(viewModel.state == .failure(.validation, message: "Enter a valid email and password."))
}

@Test @MainActor
func successfulAuthenticationEmitsStableResult() async {
    let viewModel = LoginViewModel(authenticator: FakeAuthenticator(result: .success("user-1")))
    viewModel.submit(email: "user@example.com", password: "password")
    for _ in 0..<20 where viewModel.state == .loading { await Task.yield() }
    #expect(viewModel.state == .success(.authenticated(userID: "user-1")))
}

@Test @MainActor
func domainFailureIsLocalizedByConfiguration() async {
    let viewModel = LoginViewModel(
        input: .init(configuration: .init(localeIdentifier: "vi-VN")),
        authenticator: FakeAuthenticator(result: .failure(.failure(.invalidCredentials)))
    )
    viewModel.submit(email: "user@example.com", password: "password")
    for _ in 0..<20 where viewModel.state == .loading { await Task.yield() }
    #expect(viewModel.state == .failure(.invalidCredentials, message: "Email hoặc mật khẩu không đúng."))
}
