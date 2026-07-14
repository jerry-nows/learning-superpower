import Foundation
import LoginData
import Testing
import Security

private let testDate = Date(timeIntervalSince1970: 1_700_000_000)

private func response(
    access: String = "access-1",
    refresh: String = "refresh-1"
) -> RemoteAuthResponse {
    RemoteAuthResponse(
        user: RemoteUser(id: "user-1", email: "user@example.invalid", status: "active"),
        tokens: RemoteTokens(
            accessToken: access,
            refreshToken: refresh,
            accessExpiresAt: testDate,
            refreshExpiresAt: testDate.addingTimeInterval(86_400)
        )
    )
}

private final class FakeRemote: AuthRemoteSource, @unchecked Sendable {
    var loginResult: Result<RemoteAuthResponse, Error> = .success(response())
    var refreshResult: Result<RemoteAuthResponse, Error> = .success(response(access: "access-2", refresh: "refresh-2"))
    var logoutResult: Result<Void, Error> = .success(())
    var loginCalls: [(String, String)] = []
    var refreshCalls: [String] = []
    var logoutCalls: [String] = []

    func login(email: String, password: String) async throws -> RemoteAuthResponse {
        loginCalls.append((email, password))
        return try loginResult.get()
    }

    func refresh(refreshToken: String) async throws -> RemoteAuthResponse {
        refreshCalls.append(refreshToken)
        try? await Swift.Task.sleep(for: .milliseconds(20))
        return try refreshResult.get()
    }

    func logout(accessToken: String) async throws {
        logoutCalls.append(accessToken)
        try logoutResult.get()
    }
}

@Test("concurrent refresh requests share one remote rotation")
func concurrentRefreshIsSingleFlight() async throws {
    let remote = FakeRemote()
    let store = FakeTokenStore(value: TokenPair(accessToken: "old-access", refreshToken: "old-refresh", accessTokenExpiresAt: testDate))
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    await withTaskGroup(of: Result<AuthenticatedUser, Error>.self) { group in
        for _ in 0..<8 {
            group.addTask {
                do { return .success(try await repository.refresh()) }
                catch { return .failure(error) }
            }
        }
        for await result in group {
            if case .failure(let error) = result { Issue.record("unexpected refresh error: \(error)") }
        }
    }
    #expect(remote.refreshCalls.count == 1)
}

private final class FakeTokenStore: TokenStore, @unchecked Sendable {
    var value: TokenPair?
    var loadError: Error?
    var saveError: Error?
    var clearError: Error?
    var saves: [TokenPair] = []
    var clearCount = 0

    init(value: TokenPair? = nil) { self.value = value }

    func save(_ tokens: TokenPair) throws {
        if let saveError { throw saveError }
        saves.append(tokens)
        value = tokens
    }

    func load() throws -> TokenPair? {
        if let loadError { throw loadError }
        return value
    }

    func clear() throws {
        clearCount += 1
        if let clearError { throw clearError }
        value = nil
    }
}

private enum StoreFailure: Error, Equatable { case unavailable }

@Test("login validates input, calls remote, persists tokens, and maps user")
func loginPersistsTokens() async throws {
    let remote = FakeRemote()
    let store = FakeTokenStore()
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    let user = try await repository.login(email: " user@example.invalid ", password: "secret")

    #expect(user == AuthenticatedUser(id: "user-1", email: "user@example.invalid", status: "active"))
    #expect(remote.loginCalls.count == 1)
    #expect(remote.loginCalls[0].0 == " user@example.invalid ")
    #expect(store.saves == [TokenPair(accessToken: "access-1", refreshToken: "refresh-1", accessTokenExpiresAt: testDate)])
}

@Test("login rejects empty credentials without touching dependencies")
func loginValidatesCredentials() async {
    let remote = FakeRemote()
    let store = FakeTokenStore()
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    do {
        _ = try await repository.login(email: "  ", password: "secret")
        Issue.record("expected validation error")
    } catch let error as AuthRepositoryError {
        #expect(error == .failure(.validation))
    } catch { Issue.record("unexpected error: \\(error)") }
    #expect(remote.loginCalls.isEmpty)
    #expect(store.saves.isEmpty)
}

@Test("refresh rotates the persisted pair and uses the stored refresh token")
func refreshRotatesTokens() async throws {
    let remote = FakeRemote()
    let store = FakeTokenStore(value: TokenPair(accessToken: "old-access", refreshToken: "old-refresh", accessTokenExpiresAt: testDate))
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    _ = try await repository.refresh()

    #expect(remote.refreshCalls == ["old-refresh"])
    #expect(store.value?.accessToken == "access-2")
    #expect(store.value?.refreshToken == "refresh-2")
}

@Test("terminal refresh rejection clears the local token")
func terminalRefreshClearsToken() async {
    let remote = FakeRemote()
    remote.refreshResult = .failure(AuthRemoteDataSourceError.refreshRejected)
    let store = FakeTokenStore(value: TokenPair(accessToken: "access", refreshToken: "refresh", accessTokenExpiresAt: testDate))
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    do {
        _ = try await repository.refresh()
        Issue.record("expected refresh rejection")
    } catch let error as AuthRepositoryError {
        #expect(error == .refreshRejected)
    } catch { Issue.record("unexpected error: \\(error)") }
    #expect(store.value == nil)
    #expect(store.clearCount == 1)
}

@Test("successful remote rotation followed by persistence failure clears stale credentials")
func refreshPersistenceFailureClearsStaleToken() async {
    let remote = FakeRemote()
    let store = FakeTokenStore(value: TokenPair(accessToken: "old-access", refreshToken: "old-refresh", accessTokenExpiresAt: testDate))
    store.saveError = StoreFailure.unavailable
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    do {
        _ = try await repository.refresh()
        Issue.record("expected token-store error")
    } catch let error as AuthRepositoryError {
        #expect(error == .tokenStore)
    } catch { Issue.record("unexpected error: \\(error)") }
    #expect(store.value == nil)
    #expect(store.clearCount == 1)
}

@Test("logout calls remote and clears the token after success")
func logoutSuccessClearsToken() async throws {
    let remote = FakeRemote()
    let store = FakeTokenStore(value: TokenPair(accessToken: "access", refreshToken: "refresh", accessTokenExpiresAt: testDate))
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    try await repository.logout()

    #expect(remote.logoutCalls == ["access"])
    #expect(store.value == nil)
}

@Test("logout failure still clears local credentials and maps transport error")
func logoutFailureClearsToken() async {
    let remote = FakeRemote()
    remote.logoutResult = .failure(AuthRemoteDataSourceError.transport)
    let store = FakeTokenStore(value: TokenPair(accessToken: "access", refreshToken: "refresh", accessTokenExpiresAt: testDate))
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    do {
        try await repository.logout()
        Issue.record("expected logout failure")
    } catch let error as AuthRepositoryError {
        #expect(error == .failure(.networkUnavailable))
    } catch { Issue.record("unexpected error: \\(error)") }
    #expect(store.value == nil)
}

@Test("remote errors map to stable repository failures")
func mapsRemoteErrors() async {
    let cases: [(AuthRemoteDataSourceError, LoginFailure)] = [
        (.invalidCredentials, .invalidCredentials),
        (.transport, .networkUnavailable),
        (.serviceUnavailable, .serviceUnavailable),
        (.malformedResponse, .unknown)
    ]
    for (remoteError, expected) in cases {
        let remote = FakeRemote()
        remote.loginResult = .failure(remoteError)
        let repository = DefaultAuthRepository(remote: remote, tokenStore: FakeTokenStore())
        do {
            _ = try await repository.login(email: "user@example.invalid", password: "secret")
            Issue.record("expected mapped error")
        } catch let error as AuthRepositoryError {
            #expect(error == .failure(expected))
        } catch { Issue.record("unexpected error: \\(error)") }
    }
}

@Test("presentation adapter preserves repository failure categories")
func authenticateMapsRepositoryFailure() async {
    let remote = FakeRemote()
    remote.loginResult = .failure(AuthRemoteDataSourceError.invalidCredentials)
    let repository = DefaultAuthRepository(remote: remote, tokenStore: FakeTokenStore())

    do {
        _ = try await repository.authenticate(email: "user@example.invalid", password: "secret")
        Issue.record("expected authentication failure")
    } catch let error as LoginAuthenticationError {
        #expect(error == .failure(.invalidCredentials))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("missing stored refresh token is terminal and clears defensively")
func missingRefreshTokenIsRejected() async {
    let remote = FakeRemote()
    let store = FakeTokenStore()
    let repository = DefaultAuthRepository(remote: remote, tokenStore: store)

    do {
        _ = try await repository.refresh()
        Issue.record("expected refresh rejection")
    } catch let error as AuthRepositoryError {
        #expect(error == .refreshRejected)
    } catch { Issue.record("unexpected error: \\(error)") }
    #expect(remote.refreshCalls.isEmpty)
    #expect(store.clearCount == 1)
}
