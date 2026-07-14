import Foundation
import LoginData
import Moya
import Testing

private let remoteBaseURL = URL(string: "https://api.example.invalid")!

private func stubProvider(status: Int, data: Data) -> MoyaProvider<AuthTarget> {
    MoyaProvider<AuthTarget>(
        endpointClosure: { target in
            Endpoint(
                url: target.baseURL.appendingPathComponent(target.path).absoluteString,
                sampleResponseClosure: .networkResponse(status, data),
                method: target.method,
                task: target.task,
                httpHeaderFields: target.headers
            )
        },
        stubClosure: MoyaProvider.immediatelyStub
    )
}

private let successJSON = Data("""
{"user":{"id":"user-1","email":"user@example.invalid","status":"active"},"tokens":{"access_token":"access","refresh_token":"refresh","access_expires_at":"2030-01-01T00:00:00Z","refresh_expires_at":"2030-01-02T00:00:00Z"}}
""".utf8)

@Test("remote source decodes login response without exposing DTOs")
func remoteSourceDecodesSuccess() async throws {
    let source = AuthRemoteDataSource(baseURL: remoteBaseURL, provider: stubProvider(status: 200, data: successJSON))
    let result = try await source.login(email: "user@example.invalid", password: "secret")
    #expect(result.user.id == "user-1")
    #expect(result.tokens.accessToken == "access")
}

@Test("remote source maps stable authentication errors")
func remoteSourceMapsAuthErrors() async {
    let cases: [(String, AuthRemoteDataSourceError)] = [
        ("AUTH_AUTHENTICATION_FAILED", .invalidCredentials),
        ("AUTH_REFRESH_REJECTED", .refreshRejected),
        ("AUTH_UNAUTHORIZED", .unauthorized),
        ("AUTH_INVALID_REQUEST", .invalidRequest)
    ]
    for (code, expected) in cases {
        let body = Data("{\"code\":\"\(code)\"}".utf8)
        let source = AuthRemoteDataSource(baseURL: remoteBaseURL, provider: stubProvider(status: 401, data: body))
        do {
            _ = try await source.refresh(refreshToken: "refresh")
            Issue.record("expected error for \(code)")
        } catch let error as AuthRemoteDataSourceError {
            #expect(error == expected)
        } catch {
            Issue.record("unexpected error type for \(code)")
        }
    }
}

@Test("malformed successful payload fails closed")
func remoteSourceRejectsMalformedPayload() async {
    let source = AuthRemoteDataSource(baseURL: remoteBaseURL, provider: stubProvider(status: 200, data: Data("{}".utf8)))
    do {
        _ = try await source.login(email: "user@example.invalid", password: "secret")
        Issue.record("expected malformed response")
    } catch let error as AuthRemoteDataSourceError {
        #expect(error == .malformedResponse)
    } catch {
        Issue.record("unexpected error type")
    }
}

@Test("target diagnostics never contain credential values")
func remoteSourceTargetRemainsRedacted() {
    let target = AuthTarget.login(baseURL: remoteBaseURL, request: .init(email: "private@example.invalid", password: "secret-value"))
    #expect(!target.description.contains("private@example.invalid"))
    #expect(!String(reflecting: target).contains("secret-value"))
}
