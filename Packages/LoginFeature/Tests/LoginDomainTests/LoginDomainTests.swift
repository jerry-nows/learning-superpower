@testable import LoginDomain
import Testing

@Test func domainModuleIsAvailable() {
    #expect(LoginDomain.moduleName == "LoginDomain")
}

@Test func loginFlowContractUsesImmutableSendableValues() {
    let configuration = LoginConfiguration(
        biometricPolicy: .optional,
        localeIdentifier: "vi",
        copyPolicy: .localized
    )
    let input = LoginFlowInput(configuration: configuration)

    #expect(input.configuration == configuration)
    #expect(configuration.allowsBiometric)
    #expect(LoginResult.authenticated(userID: "user-1") == .authenticated(userID: "user-1"))
    #expect(LoginResult.cancelled != .failed(.invalidCredentials))
}
