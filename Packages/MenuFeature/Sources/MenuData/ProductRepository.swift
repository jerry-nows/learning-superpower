import Foundation
import MenuDomain

public enum ProductCacheFreshness: Sendable, Equatable { case fresh, stale }

public struct ProductCachedValue<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value
    public let cachedAt: Date
    public let freshness: ProductCacheFreshness
    public init(value: Value, cachedAt: Date, freshness: ProductCacheFreshness) {
        self.value = value; self.cachedAt = cachedAt; self.freshness = freshness
    }
}

/// Repository-first API: network is authoritative, while reads can fall back
/// to an explicitly marked stale cache when the network is unavailable.
public final class ProductRepository: ProductRemoteSource, @unchecked Sendable {
    private let remote: ProductRemoteSource
    private let cache: ProductCacheStore
    private let clock: @Sendable () -> Date
    private let freshnessInterval: TimeInterval

    public init(
        remote: ProductRemoteSource,
        cache: ProductCacheStore,
        freshnessInterval: TimeInterval = 300,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.remote = remote
        self.cache = cache
        self.freshnessInterval = max(0, freshnessInterval)
        self.clock = clock
    }

    public func list(query: ProductQuery) async throws -> ProductPageResponse { try await listValue(query: query).value }
    public func detail(productID: String) async throws -> Product { try await detailValue(productID: productID).value }
    public func inventory(productID: String) async throws -> ProductStock { try await inventoryValue(productID: productID).value }
    public func ratingSummary(productID: String) async throws -> ProductRatingSummary { try await ratingValue(productID: productID).value }
    public func comments(productID: String) async throws -> [ProductComment] { try await commentsValue(productID: productID).value }
    public func categories() async throws -> [Category] { try await categoriesValue().value }

    public func listValue(query: ProductQuery) async throws -> ProductCachedValue<ProductPageResponse> {
        try await load(key: "list:\(queryKey(query))", decode: ProductPageResponse.self) { try await self.remote.list(query: query) }
    }
    public func detailValue(productID: String) async throws -> ProductCachedValue<Product> {
        try await load(key: "detail:\(productID)", decode: Product.self) {
            try await self.remote.detail(productID: productID)
        }
    }
    public func inventoryValue(productID: String) async throws -> ProductCachedValue<ProductStock> {
        try await load(key: "inventory:\(productID)", decode: ProductStock.self) {
            try await self.remote.inventory(productID: productID)
        }
    }
    public func ratingValue(productID: String) async throws -> ProductCachedValue<ProductRatingSummary> {
        try await load(key: "rating:\(productID)", decode: ProductRatingSummary.self) {
            try await self.remote.ratingSummary(productID: productID)
        }
    }
    public func commentsValue(productID: String) async throws -> ProductCachedValue<[ProductComment]> {
        try await load(key: "comments:\(productID)", decode: [ProductComment].self) {
            try await self.remote.comments(productID: productID)
        }
    }
    public func categoriesValue() async throws -> ProductCachedValue<[Category]> {
        try await load(key: "categories", decode: [Category].self) {
            try await self.remote.categories()
        }
    }

    public func invalidateList(query: ProductQuery) async throws { try await cache.invalidate(key: "list:\(queryKey(query))") }
    public func invalidateProduct(productID: String) async throws {
        let keys = [
            "detail:\(productID)", "inventory:\(productID)",
            "rating:\(productID)", "comments:\(productID)"
        ]
        for key in keys { try await cache.invalidate(key: key) }
    }

    private func load<Value: Codable & Sendable & Equatable>(
        key: String,
        decode: Value.Type,
        fetch: @escaping @Sendable () async throws -> Value
    ) async throws -> ProductCachedValue<Value> {
        let now = clock()
        do { return try await save(try await fetch(), key: key, now: now) } catch let error where isOffline(error) {
            guard let entry = try await cache.entry(for: key),
                  let value = try? JSONDecoder().decode(Value.self, from: entry.payload) else {
                throw error
            }
            let freshness: ProductCacheFreshness = now.timeIntervalSince(entry.cachedAt) <= freshnessInterval ? .fresh : .stale
            return ProductCachedValue(value: value, cachedAt: entry.cachedAt, freshness: freshness)
        }
    }

    private func save<Value: Codable & Sendable & Equatable>(_ value: Value, key: String, now: Date) async throws -> ProductCachedValue<Value> {
        let payload = try JSONEncoder().encode(value)
        try await cache.save(ProductCacheEntry(payload: payload, cachedAt: now), for: key)
        return ProductCachedValue(value: value, cachedAt: now, freshness: .fresh)
    }
    private func isOffline(_ error: Error) -> Bool {
        guard let error = error as? ProductRemoteDataSourceError else { return false }
        switch error {
        case .transport, .serviceUnavailable: return true
        default: return false
        }
    }
    private func queryKey(_ query: ProductQuery) -> String {
        [query.search, query.categoryID ?? "",
         query.filter.minimumPrice.map(String.init) ?? "",
         query.filter.maximumPrice.map(String.init) ?? "",
         String(query.filter.inStockOnly), query.sort.rawValue,
         query.pagination.cursor ?? "", String(query.pagination.pageSize)]
            .joined(separator: "|")
    }
}
