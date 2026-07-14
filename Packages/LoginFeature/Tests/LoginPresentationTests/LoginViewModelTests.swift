import Foundation
import LoginDomain
import Testing
@testable import LoginPresentation

private actor AuthenticatorProbe: LoginAuthenticator {
    enum Reply: Sendable {
        case success(String)
        case failure(LoginAuthenticationError)
        case suspended
    }

    private let reply: Reply
    private(set) var calls: [(String, String)] = []
    init(reply: Reply) { self.reply = reply }

    func authenticate(email: String, password: String) async throws -> String {
        calls.append((email, password))
        switch reply {
        case let .success(userID): return userID
        case let .failure(error): throw error
        case .suspended:
            try await Task.sleep(for: .seconds(30))
            return "suspended-user"
        }
    }
}

@Test @MainActor
func viewModelRejectsInvalidInputWithoutCallingRepository() async {
    let probe = AuthenticatorProbe(reply: .success("unused"))
    let viewModel = LoginViewModel(authenticator: probe)

    viewModel.submit(email: "not-an-email", password: "")

    #expect(viewModel.state == .failure(.validation, message: "Enter a valid email and password."))
    #expect(await probe.calls.isEmpty)
}

@Test @MainActor
func viewModelPublishesLoadingBeforeAuthenticationCompletes() async {
    let probe = AuthenticatorProbe(reply: .suspended)
    let viewModel = LoginViewModel(authenticator: probe)

    viewModel.submit(email: " user@example.com ", password: "secret")
    #expect(viewModel.state == .loading)
    #expect(await probe.calls.count == 1)
    #expect(await probe.calls.first?.0 == "user@example.com")

    viewModel.cancel()
    #expect(viewModel.state == .idle)
}

@Test @MainActor
func viewModelPublishesSuccessWithoutExposingCredentials() async {
    let secret = "super-secret"
    let probe = AuthenticatorProbe(reply: .success("user-1"))
    let viewModel = LoginViewModel(authenticator: probe)

    viewModel.submit(email: "user@example.com", password: secret)
    await Task.yield()

    #expect(viewModel.state == .success(.authenticated(userID: "user-1")))
    #expect(!String(describing: viewModel.state).contains(secret))
}

@Test @MainActor
func viewModelLocalizesAuthenticationFailure() async {
    let probe = AuthenticatorProbe(reply: .failure(.failure(.invalidCredentials)))
    let viewModel = LoginViewModel(
        input: .init(configuration: .init(localeIdentifier: "vi-VN")),
        authenticator: probe
    )

    viewModel.submit(email: "user@example.com", password: "secret")
    await Task.yield()

    #expect(viewModel.state == .failure(.invalidCredentials, message: "Email hoặc mật khẩu không đúng."))
}

@Test @MainActor
func cancellingSubmissionReturnsToIdle() async {
    let probe = AuthenticatorProbe(reply: .suspended)
    let viewModel = LoginViewModel(authenticator: probe)

    viewModel.submit(email: "user@example.com", password: "secret")
    viewModel.cancel()
    await Task.yield()

    #expect(viewModel.state == .idle)
}

@Test @MainActor
func duplicateSubmitKeepsLatestResult() async {
    let first = AuthenticatorProbe(reply: .suspended)
    let second = AuthenticatorProbe(reply: .success("latest-user"))
    let authenticator = SwitchingAuthenticator(first: first, second: second)
    let viewModel = LoginViewModel(authenticator: authenticator)

    viewModel.submit(email: "first@example.com", password: "first-secret")
    viewModel.submit(email: "second@example.com", password: "second-secret")
    await Task.yield()
    await Task.yield()

    #expect(viewModel.state == .success(.authenticated(userID: "latest-user")))
}

private actor SwitchingAuthenticator: LoginAuthenticator {
    let first: AuthenticatorProbe
    let second: AuthenticatorProbe
    private var count = 0

    init(first: AuthenticatorProbe, second: AuthenticatorProbe) {
        self.first = first
        self.second = second
    }

    func authenticate(email: String, password: String) async throws -> String {
        count += 1
        if count == 1 {
            return try await first.authenticate(email: email, password: password)
        }
        return try await second.authenticate(email: email, password: password)
    }
}
