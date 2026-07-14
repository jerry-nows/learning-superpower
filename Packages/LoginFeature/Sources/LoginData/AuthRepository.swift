import Foundation
import LoginDomain
import Networking
import Security

/// The authenticated user value exposed to the presentation layer. Tokens are
/// deliberately not part of this value; they remain behind `TokenStore`.
public struct AuthenticatedUser: Equatable, Sendable {
    public let id: String
    public let email: String?
    public let status: String

    public init(id: String, email: String?, status: String) {
        self.id = id
        self.email = email
        self.status = status
    }
}

public enum AuthRepositoryError: Error, Equatable, Sendable {
    case failure(LoginFailure)
    case refreshRejected
    case tokenStore
}

public extension AuthRepositoryError {
    /// Stable UI-facing category for callers that do not need the transport
    /// distinction between a rejected refresh and another auth failure.
    var loginFailure: LoginFailure {
        switch self {
        case let .failure(value): value
        case .refreshRejected: .invalidCredentials
        case .tokenStore: .serviceUnavailable
        }
    }
}

/// Data boundary consumed by `LoginViewModel`. Implementations own transport
/// DTO mapping and secure token persistence.
public protocol AuthRepository: Sendable {
    func login(email: String, password: String) async throws -> AuthenticatedUser
    func refresh() async throws -> AuthenticatedUser
    func logout() async throws
}

public final class DefaultAuthRepository: AuthRepository, @unchecked Sendable {
    private let remote: any AuthRemoteSource
    private let tokenStore: any TokenStore
    private let refreshActor: AuthRefreshActor<AuthenticatedUser>

    public init(remote: any AuthRemoteSource, tokenStore: any TokenStore) {
        self.remote = remote
        self.tokenStore = tokenStore
        self.refreshActor = AuthRefreshActor()
    }

    public func login(email: String, password: String) async throws -> AuthenticatedUser {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            throw AuthRepositoryError.failure(.validation)
        }

        do {
            let response = try await remote.login(email: email, password: password)
            try persist(response.tokens)
            return map(response.user)
        } catch let error as AuthRepositoryError {
            throw error
        } catch {
            throw map(error)
        }
    }

    public func refresh() async throws -> AuthenticatedUser {
        try await refreshActor.refresh { [weak self] in
            guard let self else { throw AuthRepositoryError.failure(.serviceUnavailable) }
            return try await self.performRefresh()
        }
    }

    private func performRefresh() async throws -> AuthenticatedUser {
        let tokens: TokenPair
        do {
            guard let stored = try tokenStore.load() else {
                clearBestEffort()
                throw AuthRepositoryError.refreshRejected
            }
            tokens = stored
        } catch let error as AuthRepositoryError {
            throw error
        } catch {
            throw AuthRepositoryError.tokenStore
        }

        do {
            let response = try await remote.refresh(refreshToken: tokens.refreshToken)
            do {
                try persist(response.tokens)
            } catch {
                // Rotation succeeded remotely; discard the stale local token if
                // secure replacement cannot be committed, avoiding reuse of it.
                clearBestEffort()
                throw error
            }
            return map(response.user)
        } catch let error as AuthRepositoryError {
            if isTerminalRefresh(error) { clearBestEffort() }
            throw error
        } catch {
            let mapped = map(error, refresh: true)
            if isTerminalRefresh(mapped) { clearBestEffort() }
            throw mapped
        }
    }

    public func logout() async throws {
        var accessToken: String?
        do {
            accessToken = try tokenStore.load()?.accessToken
        } catch {
            clearBestEffort()
            throw AuthRepositoryError.tokenStore
        }

        guard let accessToken, !accessToken.isEmpty else {
            do { try tokenStore.clear() }
            catch { throw AuthRepositoryError.tokenStore }
            return
        }

        do {
            try await remote.logout(accessToken: accessToken)
        } catch {
            clearBestEffort()
            throw map(error)
        }

        do { try tokenStore.clear() }
        catch { throw AuthRepositoryError.tokenStore }
    }

    private func persist(_ tokens: RemoteTokens) throws {
        do {
            try tokenStore.save(TokenPair(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accessTokenExpiresAt: tokens.accessExpiresAt
            ))
        } catch {
            throw AuthRepositoryError.tokenStore
        }
    }

    private func map(_ user: RemoteUser) -> AuthenticatedUser {
        AuthenticatedUser(id: user.id, email: user.email, status: user.status)
    }

    private func map(_ error: Error, refresh: Bool = false) -> AuthRepositoryError {
        guard let error = error as? AuthRemoteDataSourceError else {
            return .failure(.unknown)
        }
        switch error {
        case .invalidRequest: return .failure(.validation)
        case .invalidCredentials: return .failure(.invalidCredentials)
        case .refreshRejected: return refresh ? .refreshRejected : .failure(.invalidCredentials)
        case .unauthorized: return refresh ? .refreshRejected : .failure(.invalidCredentials)
        case .cancelled: return .failure(.unknown)
        case .transport: return .failure(.networkUnavailable)
        case .serviceUnavailable, .methodNotAllowed, .server: return .failure(.serviceUnavailable)
        case .malformedResponse: return .failure(.unknown)
        }
    }

    private func isTerminalRefresh(_ error: AuthRepositoryError) -> Bool {
        switch error {
        case .refreshRejected: true
        case let .failure(failure): failure == .invalidCredentials || failure == .unknown
        case .tokenStore: false
        }
    }

    private func clearBestEffort() {
        _ = try? tokenStore.clear()
    }
}

extension DefaultAuthRepository: LoginAuthenticator {
    public func authenticate(email: String, password: String) async throws -> String {
        let user = try await login(email: email, password: password)
        return user.id
    }
}
