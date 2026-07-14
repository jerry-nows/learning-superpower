import Foundation
import Networking

/// Values returned by the authentication HTTP boundary. These types contain no
/// request DTOs and are safe for the repository layer to consume.
public struct RemoteAuthResponse: Equatable, Sendable {
    public let user: RemoteUser
    public let tokens: RemoteTokens

    public init(user: RemoteUser, tokens: RemoteTokens) {
        self.user = user
        self.tokens = tokens
    }
}

public struct RemoteUser: Equatable, Sendable {
    public let id: String
    public let email: String?
    public let status: String

    public init(id: String, email: String?, status: String) {
        self.id = id
        self.email = email
        self.status = status
    }
}

public struct RemoteTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresAt: Date
    public let refreshExpiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        accessExpiresAt: Date,
        refreshExpiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }
}

public enum AuthRemoteDataSourceError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidCredentials
    case refreshRejected
    case unauthorized
    case methodNotAllowed
    case cancelled
    case serviceUnavailable
    case server(code: String)
    case malformedResponse
    case transport
}

public protocol AuthRemoteSource: Sendable {
    func login(email: String, password: String) async throws -> RemoteAuthResponse
    func refresh(refreshToken: String) async throws -> RemoteAuthResponse
    func logout(accessToken: String) async throws
}

/// Moya-backed authentication data source. The provider is injected to keep
/// transport behavior deterministic in tests and to avoid global networking.
public final class AuthRemoteDataSource: AuthRemoteSource, @unchecked Sendable {
    private let provider: MoyaProvider<AuthTarget>
    private let decoder: JSONDecoder
    private let baseURL: URL

    public init(
        baseURL: URL,
        provider: MoyaProvider<AuthTarget> = MoyaProvider<AuthTarget>()
    ) {
        self.baseURL = baseURL
        self.provider = provider
        self.decoder = Self.makeDecoder()
    }

    public func login(email: String, password: String) async throws -> RemoteAuthResponse {
        let target = AuthTarget.login(
            baseURL: baseURL,
            request: .init(email: email, password: password)
        )
        return try await request(target, response: RemoteAuthDTO.self).asRemoteResponse()
    }

    public func refresh(refreshToken: String) async throws -> RemoteAuthResponse {
        let target = AuthTarget.refresh(
            baseURL: baseURL,
            request: .init(refreshToken: refreshToken)
        )
        return try await request(target, response: RemoteAuthDTO.self).asRemoteResponse()
    }

    public func logout(accessToken: String) async throws {
        let target = AuthTarget.logout(baseURL: baseURL, accessToken: accessToken)
        _ = try await request(target, response: EmptyResponse.self)
    }

    private func request<Response: Decodable & Sendable>(
        _ target: AuthTarget,
        response: Response.Type
    ) async throws -> Response {
        let state = RequestState<Response>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let token = provider.request(target) { [decoder] result in
                    switch result {
                    case let .success(value):
                        if Response.self == EmptyResponse.self {
                            state.resume(returning: EmptyResponse() as! Response)
                            return
                        }
                        do {
                            state.resume(returning: try decoder.decode(Response.self, from: value.data))
                        } catch {
                            state.resume(throwing: AuthRemoteDataSourceError.malformedResponse)
                        }
                    case let .failure(error):
                        state.resume(throwing: Self.map(error))
                    }
                }
                state.set(token)
            }
        }, onCancel: {
            state.cancel()
        })
    }

    private static func map(_ moyaError: MoyaError) -> AuthRemoteDataSourceError {
        if case let .statusCode(response) = moyaError {
            guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: response.data) else {
                return response.statusCode == 408 ? .cancelled : .server(code: "HTTP_\(response.statusCode)")
            }
            switch envelope.code {
            case "AUTH_INVALID_REQUEST": return .invalidRequest
            case "AUTH_AUTHENTICATION_FAILED": return .invalidCredentials
            case "AUTH_REFRESH_REJECTED": return .refreshRejected
            case "AUTH_UNAUTHORIZED": return .unauthorized
            case "AUTH_METHOD_NOT_ALLOWED": return .methodNotAllowed
            case "AUTH_AUTHENTICATION_CANCELLED", "AUTH_REFRESH_CANCELLED", "AUTH_LOGOUT_CANCELLED", "AUTH_TOKEN_ISSUE_CANCELLED": return .cancelled
            case "AUTH_REPOSITORY_FAILED", "AUTH_TOKEN_ISSUE_FAILED", "AUTH_LOGOUT_FAILED", "AUTH_INTERNAL": return .serviceUnavailable
            default: return .server(code: envelope.code)
            }
        }
        if case let .underlying(underlying, _) = moyaError,
           (underlying as NSError).code == NSURLErrorCancelled {
            return .cancelled
        }
        return .transport
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date")
            }
            return date
        }
        return decoder
    }
}

private struct RemoteAuthDTO: Decodable, Sendable {
    let user: UserDTO
    let tokens: TokensDTO

    func asRemoteResponse() throws -> RemoteAuthResponse {
        guard !user.id.isEmpty, !user.status.isEmpty,
              !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty else {
            throw AuthRemoteDataSourceError.malformedResponse
        }
        return RemoteAuthResponse(
            user: RemoteUser(id: user.id, email: user.email, status: user.status),
            tokens: RemoteTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accessExpiresAt: tokens.accessExpiresAt,
                refreshExpiresAt: tokens.refreshExpiresAt
            )
        )
    }
}

private struct UserDTO: Decodable, Sendable {
    let id: String
    let email: String?
    let status: String
}

private struct TokensDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

private struct ErrorEnvelope: Decodable, Sendable {
    let code: String
}

private struct EmptyResponse: Decodable, Sendable {}

private final class RequestState<Response>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Response, Error>?
    private var token: Cancellable?
    private var cancelled = false
    private var completed = false

    func install(_ continuation: CheckedContinuation<Response, Error>) {
        lock.lock()
        self.continuation = continuation
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            resume(throwing: AuthRemoteDataSourceError.cancelled)
        }
    }

    func set(_ token: Cancellable) {
        lock.lock()
        if cancelled || completed {
            lock.unlock()
            token.cancel()
            return
        }
        self.token = token
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let token = self.token
        lock.unlock()
        token?.cancel()
        resume(throwing: AuthRemoteDataSourceError.cancelled)
    }

    func resume(returning value: Response) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
