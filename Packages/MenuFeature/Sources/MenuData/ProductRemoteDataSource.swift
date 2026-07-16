import Foundation
import struct MenuDomain.Category
import MenuDomain
import Networking

public struct ProductPageResponse: Codable, Equatable, Sendable {
    public let items: [Product]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let hasNext: Bool

    public init(items: [Product], page: Int, pageSize: Int, total: Int, hasNext: Bool) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.hasNext = hasNext
    }

    private enum CodingKeys: String, CodingKey { case items, page, pageSize = "page_size", total, hasNext = "has_next" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([WireProduct].self, forKey: .items).map(\.value)
        page = try container.decode(Int.self, forKey: .page)
        pageSize = try container.decode(Int.self, forKey: .pageSize)
        total = try container.decode(Int.self, forKey: .total)
        hasNext = try container.decode(Bool.self, forKey: .hasNext)
    }
}

public struct ProductRatingSummary: Codable, Equatable, Sendable {
    public let productID: String
    public let averageRating: Double
    public let reviewCount: Int

    public init(productID: String, averageRating: Double, reviewCount: Int) {
        self.productID = productID
        self.averageRating = averageRating
        self.reviewCount = reviewCount
    }

    private enum CodingKeys: String, CodingKey { case productID = "product_id", averageRating = "average_rating", reviewCount = "review_count" }
}

public struct ProductComment: Codable, Equatable, Sendable {
    public let id: String
    public let productID: String
    public let userID: String
    public let body: String
    public let createdAt: Date

    public init(id: String, productID: String, userID: String, body: String, createdAt: Date) {
        self.id = id
        self.productID = productID
        self.userID = userID
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, productID = "product_id", userID = "user_id", body, createdAt = "created_at" }
}

public struct ProductStock: Codable, Equatable, Sendable {
    public let productID: String
    public let available: Int
    public let updatedAt: Date

    public init(productID: String, available: Int, updatedAt: Date) {
        self.productID = productID
        self.available = available
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case productID = "product_id", available, updatedAt = "updated_at" }
}

public enum ProductRemoteDataSourceError: Error, Equatable, Sendable {
    case unauthorized
    case notFound
    case serviceUnavailable
    case server(code: String)
    case malformedResponse
    case transport
    case cancelled
}

public protocol ProductRemoteSource: Sendable {
    func list(query: ProductQuery) async throws -> ProductPageResponse
    func detail(productID: String) async throws -> Product
    func inventory(productID: String) async throws -> ProductStock
    func ratingSummary(productID: String) async throws -> ProductRatingSummary
    func comments(productID: String) async throws -> [ProductComment]
    func categories() async throws -> [Category]
}

/// Moya-backed, read-only catalog source. Each request gets a fresh decoder so
/// decoding state is never shared across concurrent detail-section requests.
public final class ProductRemoteDataSource: ProductRemoteSource, @unchecked Sendable {
    private let provider: MoyaProvider<ProductTarget>
    private let baseURL: URL
    private let accessToken: String?

    public init(
        baseURL: URL,
        accessToken: String? = nil,
        provider: MoyaProvider<ProductTarget> = MoyaProvider<ProductTarget>()
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.provider = provider
    }

    public func list(query: ProductQuery) async throws -> ProductPageResponse {
        try await request(.list(baseURL: baseURL, query: query, accessToken: accessToken), response: ProductPageResponse.self)
    }

    public func detail(productID: String) async throws -> Product {
        let value = try await request(.detail(baseURL: baseURL, productID: productID, accessToken: accessToken), response: WireProduct.self)
        return value.value
    }

    public func inventory(productID: String) async throws -> ProductStock {
        try await request(.inventory(baseURL: baseURL, productID: productID, accessToken: accessToken), response: ProductStock.self)
    }

    public func ratingSummary(productID: String) async throws -> ProductRatingSummary {
        try await request(.ratingSummary(baseURL: baseURL, productID: productID, accessToken: accessToken), response: ProductRatingSummary.self)
    }

    public func comments(productID: String) async throws -> [ProductComment] {
        try await request(.comments(baseURL: baseURL, productID: productID, accessToken: accessToken), response: [ProductComment].self)
    }

    public func categories() async throws -> [Category] {
        (try await request(.categories(baseURL: baseURL, accessToken: accessToken), response: [WireCategory].self)).map(\.value)
    }

    private func request<Response: Decodable & Sendable>(
        _ target: ProductTarget,
        response: Response.Type
    ) async throws -> Response {
        let state = RequestState<Response>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let token = provider.request(target) { result in
                    switch result {
                    case let .success(value):
                        do {
                            state.resume(returning: try Self.makeDecoder().decode(Response.self, from: value.data))
                        } catch {
                            state.resume(throwing: ProductRemoteDataSourceError.malformedResponse)
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

    private static func map(_ error: MoyaError) -> ProductRemoteDataSourceError {
        if case let .statusCode(response) = error {
            if response.statusCode == 401 { return .unauthorized }
            if response.statusCode == 404 { return .notFound }
            if response.statusCode == 408 { return .serviceUnavailable }
            if response.statusCode == 429 || response.statusCode >= 500 { return .serviceUnavailable }
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: response.data) {
                return .server(code: envelope.code)
            }
            return .server(code: "HTTP_\(response.statusCode)")
        }
        if case let .underlying(underlying, _) = error,
           (underlying as NSError).code == NSURLErrorCancelled {
            return .cancelled
        }
        return .transport
    }
}

private struct ErrorEnvelope: Decodable, Sendable { let code: String }

private struct WireProduct: Decodable, Sendable {
    let id: String
    let categoryID: String
    let name: String
    let description: String
    let price: Int64
    let currency: String
    let stock: Int
    let imageURL: URL?

    var value: Product {
        Product(id: id, categoryID: categoryID, name: name, description: description, price: price, currency: currency, stock: stock, imageURL: imageURL)
    }

    enum CodingKeys: String, CodingKey { case id, categoryID = "category_id", name, description, price, currency, stock, imageURL = "image_url" }
}

private struct WireCategory: Decodable, Sendable {
    let id: String
    let name: String
    var value: Category { Category(id: id, name: name) }
}

private final class RequestState<Response>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Response, Error>?
    private var token: Cancellable?
    private var cancelled = false
    private var completed = false

    func install(_ continuation: CheckedContinuation<Response, Error>) {
        lock.lock(); self.continuation = continuation; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { resume(throwing: ProductRemoteDataSourceError.cancelled) }
    }

    func set(_ token: Cancellable) {
        lock.lock()
        if cancelled || completed { lock.unlock(); token.cancel(); return }
        self.token = token
        lock.unlock()
    }

    func cancel() {
        lock.lock(); cancelled = true; let token = self.token; lock.unlock()
        token?.cancel(); resume(throwing: ProductRemoteDataSourceError.cancelled)
    }

    func resume(returning value: sending Response) {
        lock.lock(); guard !completed, let continuation else { lock.unlock(); return }
        completed = true; self.continuation = nil; lock.unlock(); continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock(); guard !completed, let continuation else { lock.unlock(); return }
        completed = true; self.continuation = nil; lock.unlock(); continuation.resume(throwing: error)
    }
}
