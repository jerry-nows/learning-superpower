import Foundation
import LoginDomain
import Moya
import Networking

/// Moya targets for the authentication API.
///
/// The target keeps the base URL explicit so the composition root can select a
/// local, staging, or production server without changing the feature module.
/// Credentials are only held by the request value long enough for Moya to
/// encode the request and are never included in diagnostics.
public enum AuthTarget: TargetType, Sendable {
    public struct LoginRequest: Codable, Equatable, Sendable {
        public let email: String
        public let password: String

        public init(email: String, password: String) {
            self.email = email
            self.password = password
        }
    }

    public struct RefreshRequest: Codable, Equatable, Sendable {
        public let refreshToken: String

        public init(refreshToken: String) {
            self.refreshToken = refreshToken
        }

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    case login(baseURL: URL, request: LoginRequest)
    case refresh(baseURL: URL, request: RefreshRequest)
    case logout(baseURL: URL, accessToken: String)

    public var baseURL: URL {
        switch self {
        case let .login(baseURL, _), let .refresh(baseURL, _), let .logout(baseURL, _):
            baseURL
        }
    }

    public var path: String {
        switch self {
        case .login:
            "/v1/auth/login"
        case .refresh:
            "/v1/auth/refresh"
        case .logout:
            "/v1/auth/logout"
        }
    }

    public var method: Moya.Method { .post }

    public var task: Moya.Task {
        switch self {
        case let .login(_, request):
            .requestJSONEncodable(request)
        case let .refresh(_, request):
            .requestJSONEncodable(request)
        case .logout:
            .requestPlain
        }
    }

    public var headers: [String: String]? {
        var result = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        if case let .logout(_, accessToken) = self {
            result["Authorization"] = "Bearer \(accessToken)"
        }
        return result
    }

    public var validationType: ValidationType { .successCodes }

    public var sampleData: Data { Data("{}".utf8) }
}

extension AuthTarget: CustomStringConvertible {
    public var description: String {
        "AuthTarget(POST \(path))"
    }
}
