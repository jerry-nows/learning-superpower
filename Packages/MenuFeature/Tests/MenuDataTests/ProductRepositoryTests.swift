import Foundation
import MenuData
import MenuDomain
import Testing

private actor FakeCache: ProductCacheStore {
    var values: [String: ProductCacheEntry] = [:]
    func entry(for key: String) async throws -> ProductCacheEntry? { values[key] }
    func save(_ entry: ProductCacheEntry, for key: String) async throws { values[key] = entry }
    func invalidate(key: String) async throws { values.removeValue(forKey: key) }
    func removeAll() async throws { values.removeAll() }
}

private struct FakeRemote: ProductRemoteSource {
    var result: Result<ProductPageResponse, ProductRemoteDataSourceError>
    func list(query: ProductQuery) async throws -> ProductPageResponse { try result.get() }
    func detail(productID: String) async throws -> Product { fatalError() }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
    func categories() async throws -> [Category] { fatalError() }
}

private let page = ProductPageResponse(items: [Product(id: "p1", categoryID: "c1", name: "Coffee", price: 100)], page: 1, pageSize: 20, total: 1, hasNext: false)

@Test("repository caches network response and serves a cache hit")
func cacheHit() async throws {
    let cache = FakeCache()
    let repository = ProductRepository(remote: FakeRemote(result: .success(page)), cache: cache, clock: { Date(timeIntervalSince1970: 100) })
    let first = try await repository.listValue(query: .init())
    let second = try await repository.listValue(query: .init())
    #expect(first.value == second.value); #expect(second.freshness == .fresh)
}

@Test("repository reports a miss when remote fails without cache")
func cacheMiss() async {
    let repository = ProductRepository(remote: FakeRemote(result: .failure(.transport)), cache: FakeCache())
    do { _ = try await repository.list(query: .init()); Issue.record("expected transport failure") }
    catch let error as ProductRemoteDataSourceError { #expect(error == .transport) }
    catch { Issue.record("unexpected error") }
}

@Test("stale cache is returned when the network is unavailable")
func staleFallback() async throws {
    let cache = FakeCache()
    let old = ProductCacheEntry(payload: try JSONEncoder().encode(page), cachedAt: Date(timeIntervalSince1970: 1))
    try await cache.save(old, for: "list:||||false|newest||20")
    let repository = ProductRepository(remote: FakeRemote(result: .failure(.transport)), cache: cache, freshnessInterval: 10, clock: { Date(timeIntervalSince1970: 100) })
    let result = try await repository.listValue(query: .init())
    #expect(result.value == page); #expect(result.freshness == .stale)
}

@Test("repository invalidates list cache")
func invalidation() async throws {
    let cache = FakeCache()
    let repository = ProductRepository(remote: FakeRemote(result: .success(page)), cache: cache)
    _ = try await repository.list(query: .init())
    try await repository.invalidateList(query: .init())
    let entry = try await cache.entry(for: "list:||||false|newest||20")
    #expect(entry == nil)
}

@Test("Core Data cache store persists and invalidates entries")
func coreDataStoreRoundTrip() async throws {
    let store = CoreDataProductCacheStore(inMemory: true)
    let entry = ProductCacheEntry(payload: Data("payload".utf8), cachedAt: Date(timeIntervalSince1970: 42))
    try await store.save(entry, for: "product:p1")
    let stored = try await store.entry(for: "product:p1")
    #expect(stored == entry)
    try await store.invalidate(key: "product:p1")
    let removed = try await store.entry(for: "product:p1")
    #expect(removed == nil)
}
