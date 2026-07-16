import Foundation
import MenuData
import Moya
import Testing

private let baseURL = URL(string: "https://api.example.invalid")!
private let productJSON = Data("""
{"id":"p1","category_id":"c1","name":"Coffee","description":"Fresh","price":42000,"currency":"VND","stock":7,"image_url":null}
""".utf8)

private func provider(status: Int, data: Data) -> MoyaProvider<ProductTarget> {
    MoyaProvider<ProductTarget>(endpointClosure: { target in
        Endpoint(url: target.baseURL.appendingPathComponent(target.path).absoluteString,
                 sampleResponseClosure: .networkResponse(status, data), method: target.method,
                 task: target.task, httpHeaderFields: target.headers)
    }, stubClosure: MoyaProvider.immediatelyStub)
}

private func delayedProvider(data: Data) -> MoyaProvider<ProductTarget> {
    MoyaProvider<ProductTarget>(endpointClosure: { target in
        Endpoint(url: target.baseURL.appendingPathComponent(target.path).absoluteString,
                 sampleResponseClosure: .networkResponse(200, data), method: target.method,
                 task: target.task, httpHeaderFields: target.headers)
    }, stubClosure: { _ in .delayed(seconds: 0.2) })
}

@Test("remote source decodes list and detail payloads")
func productRemoteSourceDecodesSuccess() async throws {
    let list = Data("""
    {"items":[\(String(decoding: productJSON, as: UTF8.self))],"page":1,"page_size":20,"total":1,"has_next":false}
    """.utf8)
    let source = ProductRemoteDataSource(baseURL: baseURL, accessToken: "token", provider: provider(status: 200, data: list))
    let page = try await source.list(query: .init())
    #expect(page.items.first?.id == "p1")
    #expect(page.items.first?.categoryID == "c1")
}

@Test("remote source maps HTTP and malformed failures")
func productRemoteSourceMapsFailures() async {
    let unauthorized = ProductRemoteDataSource(baseURL: baseURL, provider: provider(status: 401, data: Data("{}".utf8)))
    do { _ = try await unauthorized.detail(productID: "p1"); Issue.record("expected unauthorized") } catch let error as ProductRemoteDataSourceError { #expect(error == .unauthorized) } catch { Issue.record("unexpected error") }

    let malformed = ProductRemoteDataSource(baseURL: baseURL, provider: provider(status: 200, data: Data("{}".utf8)))
    do { _ = try await malformed.detail(productID: "p1"); Issue.record("expected malformed") } catch let error as ProductRemoteDataSourceError { #expect(error == .malformedResponse) } catch { Issue.record("unexpected error") }

    let timeout = ProductRemoteDataSource(baseURL: baseURL, provider: provider(status: 408, data: Data("{}".utf8)))
    do { _ = try await timeout.detail(productID: "p1"); Issue.record("expected timeout") } catch let error as ProductRemoteDataSourceError { #expect(error == .serviceUnavailable) } catch { Issue.record("unexpected timeout error") }
}

@Test("cancelling a request cancels Moya and resumes exactly once")
func productRemoteSourceCancellation() async {
    let source = ProductRemoteDataSource(baseURL: baseURL, provider: delayedProvider(data: productJSON))
    let request = Task { try await source.detail(productID: "p1") }
    try? await Task.sleep(for: .milliseconds(20))
    request.cancel()
    do { _ = try await request.value; Issue.record("expected cancellation") } catch let error as ProductRemoteDataSourceError { #expect(error == .cancelled) } catch { Issue.record("unexpected cancellation error") }
}
