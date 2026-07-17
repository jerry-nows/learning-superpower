import MenuData
import MenuDomain
import Testing

@Test("detail requests run independently and publish an all-success snapshot")
@MainActor
func productDetailAllSectionsLoad() async {
    let source = DetailSource()
    let model = ProductDetailViewModel(source: source)
    model.load(productID: "p-1")
    await waitUntil { if case .loaded(let snapshot) = model.state { return snapshot.completedSectionCount == 4 }; return false }
    guard case let .loaded(snapshot) = model.state else { Issue.record("expected loaded state"); return }
    #expect(snapshot.product == .loaded(Product(id: "p-1", categoryID: "c", name: "Lamp", price: 100)))
    #expect(snapshot.reviews.isSkeleton == false)
    #expect(source.calls.count == 4)
}

@Test("one failed section leaves other sections available")
@MainActor
func productDetailPartialSuccess() async {
    let model = ProductDetailViewModel(source: DetailSource(failing: .comments))
    model.load(productID: "p-1")
    await waitUntil { if case .partial(let snapshot) = model.state { return snapshot.completedSectionCount == 4 }; return false }
    guard case let .partial(snapshot) = model.state else { Issue.record("expected partial state"); return }
    #expect(snapshot.comments.isSkeleton == false)
    #expect(snapshot.product.isSkeleton == false)
}

@Test("offline failures are surfaced after all sections complete")
@MainActor
func productDetailOffline() async {
    let model = ProductDetailViewModel(source: DetailSource(failing: .allOffline))
    model.load(productID: "p-1")
    await waitUntil { if case .offline = model.state { return true }; return false }
    guard case let .offline(snapshot) = model.state else { Issue.record("expected offline state"); return }
    #expect(snapshot.completedSectionCount == 4)
}

@Test("cancelling a detail request exposes a cancellation state")
@MainActor
func productDetailCancellation() async {
    let source = DetailSource(blocking: true)
    let model = ProductDetailViewModel(source: source)
    model.load(productID: "p-1")
    model.cancel()
    guard case .cancelled = model.state else { Issue.record("expected cancelled state"); return }
    #expect(source.calls.isEmpty)
}

@MainActor
private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting for async state")
}

private final class DetailSource: ProductRemoteSource, @unchecked Sendable {
    enum Failure: Sendable, Equatable { case comments, allOffline }
    let failing: Failure?
    let blocking: Bool
    private(set) var calls: [String] = []
    private let lock = NSLock()

    init(failing: Failure? = nil, blocking: Bool = false) {
        self.failing = failing
        self.blocking = blocking
    }

    func list(query: ProductQuery) async throws -> ProductPageResponse { fatalError() }
    func categories() async throws -> [Category] { fatalError() }

    func detail(productID: String) async throws -> Product {
        try await record("product")
        return Product(id: productID, categoryID: "c", name: "Lamp", price: 100)
    }

    func inventory(productID: String) async throws -> ProductStock {
        try await record("stock")
        return ProductStock(productID: productID, available: 2, updatedAt: .now)
    }

    func ratingSummary(productID: String) async throws -> ProductRatingSummary {
        try await record("reviews")
        return ProductRatingSummary(productID: productID, averageRating: 4.5, reviewCount: 3)
    }

    func comments(productID: String) async throws -> [ProductComment] {
        try await record("comments")
        return []
    }

    private func record(_ name: String) async throws {
        lock.lock(); calls.append(name); lock.unlock()
        if blocking { try await Task.sleep(for: .seconds(60)) }
        if failing == .comments && name == "comments" || failing == .allOffline {
            throw ProductRemoteDataSourceError.transport
        }
    }
}
