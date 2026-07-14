import Foundation
import LoginData
import Moya
import Testing

private let baseURL = URL(string: "https://api.example.invalid")!

@Test("login target matches the OpenAPI endpoint and JSON body")
func loginTargetContract() throws {
    let target = AuthTarget.login(
        baseURL: baseURL,
        request: .init(email: "user@example.invalid", password: "secret-value")
    )

    #expect(target.baseURL == baseURL)
    #expect(target.path == "/v1/auth/login")
    #expect(target.method == .post)
    #expect(target.headers?["Accept"] == "application/json")
    #expect(target.headers?["Content-Type"] == "application/json")
    guard case let .requestJSONEncodable(request) = target.task else {
        Issue.record("expected JSON request")
        return
    }
    let data = try JSONEncoder().encode(request)
    #expect(String(decoding: data, as: UTF8.self).contains("user@example.invalid"))
    #expect(String(decoding: data, as: UTF8.self).contains("secret-value"))
}

@Test("refresh target uses the snake case refresh token field")
func refreshTargetContract() throws {
    let target = AuthTarget.refresh(
        baseURL: baseURL,
        request: .init(refreshToken: "opaque-refresh-token")
    )

    #expect(target.path == "/v1/auth/refresh")
    #expect(target.method == .post)
    guard case let .requestJSONEncodable(request) = target.task else {
        Issue.record("expected JSON request")
        return
    }
    let data = try JSONEncoder().encode(request)
    #expect(String(decoding: data, as: UTF8.self) == "{\"refresh_token\":\"opaque-refresh-token\"}")
}

@Test("logout target sends bearer access token without a body")
func logoutTargetContract() {
    let target = AuthTarget.logout(baseURL: baseURL, accessToken: "access-token")

    #expect(target.path == "/v1/auth/logout")
    #expect(target.method == .post)
    #expect(target.headers?["Authorization"] == "Bearer access-token")
    if case .requestPlain = target.task {
        // expected
    } else {
        Issue.record("expected an empty logout body")
    }
}

@Test("target description and sample data never expose credentials")
func authTargetDiagnosticsAreRedacted() {
    let target = AuthTarget.login(
        baseURL: baseURL,
        request: .init(email: "private@example.invalid", password: "password-value")
    )

    #expect(!target.description.contains("private@example.invalid"))
    #expect(!target.description.contains("password-value"))
    #expect(!String(decoding: target.sampleData, as: UTF8.self).contains("password"))
    #expect(!String(decoding: target.sampleData, as: UTF8.self).contains("token"))
}
