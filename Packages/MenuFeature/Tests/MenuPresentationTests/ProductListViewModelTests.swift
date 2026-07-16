import MenuData
import MenuDomain
import Testing

@Test("initial load publishes products and pagination metadata")
@MainActor
func productListInitialLoad() async {
    let source = ListSource(pages: [ProductPageResponse(items: [product("one")], page: 1, pageSize: 1, total: 2, hasNext: true)])
    let model = ProductListViewModel(source: source, searchDebounce: .zero)
    model.load()
    await waitUntil { if case .loaded(let snapshot) = model.state { return snapshot.items.count == 1 }; return false }
    guard case let .loaded(snapshot) = model.state else { Issue.record("expected loaded state"); return }
    #expect(snapshot.hasNextPage)
    #expect(snapshot.items.map(\.id) == ["one"])
}

@Test("next page preserves loaded rows while skeleton state is visible")
@MainActor
func productListPagination() async {
    let source = ListSource(pages: [
        ProductPageResponse(items: [product("one")], page: 1, pageSize: 1, total: 2, hasNext: true),
        ProductPageResponse(items: [product("two")], page: 2, pageSize: 1, total: 2, hasNext: false)
    ])
    let model = ProductListViewModel(source: source, searchDebounce: .zero)
    model.load()
    await waitUntil { if case .loaded = model.state { return true }; return false }
    model.loadNextPage()
    guard case let .loadingNextPage(snapshot) = model.state else { Issue.record("expected next page skeleton state"); return }
    #expect(snapshot.items.map(\.id) == ["one"])
    #expect(snapshot.nextPageSkeletonCount == 1)
    await waitUntil { if case let .loaded(snapshot) = model.state { return snapshot.items.count == 2 }; return false }
}

@Test("search is debounced and only the latest query is requested")
@MainActor
func productListSearchDebounce() async {
    let source = ListSource(pages: [
        ProductPageResponse(items: [product("result")], page: 1, pageSize: 20, total: 1, hasNext: false)
    ])
    let model = ProductListViewModel(source: source, searchDebounce: .milliseconds(20))
    model.setSearch("old")
    model.setSearch("new")
    try? await Task.sleep(for: .milliseconds(50))
    await waitUntil { !source.queries.isEmpty }
    #expect(source.queries.last?.search == "new")
}

@Test("filter and sort reset pagination and trigger a fresh request")
@MainActor
func productListFilterAndSort() async {
    let source = ListSource(pages: [ProductPageResponse(items: [], page: 1, pageSize: 20, total: 0, hasNext: false)])
    let model = ProductListViewModel(source: source, searchDebounce: .zero)
    model.setFilter(ProductFilter(inStockOnly: true))
    await waitUntil { !source.queries.isEmpty }
    #expect(source.queries.last?.filter.inStockOnly == true)
    model.setSort(.priceDescending)
    await waitUntil { source.queries.count >= 2 }
    #expect(source.queries.last?.sort == .priceDescending)
    #expect(source.queries.last?.pagination.cursor == nil)
}

private func product(_ id: String) -> Product {
    Product(id: id, categoryID: "category", name: id, price: 100)
}

@MainActor
private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out waiting for async state")
}

private final class ListSource: ProductRemoteSource, @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [ProductPageResponse]
    private(set) var queries: [ProductQuery] = []

    init(pages: [ProductPageResponse]) { self.pages = pages }

    func list(query: ProductQuery) async throws -> ProductPageResponse {
        lock.lock()
        queries.append(query)
        let page = pages.isEmpty ? ProductPageResponse(items: [], page: 1, pageSize: 20, total: 0, hasNext: false) : pages.removeFirst()
        lock.unlock()
        return page
    }

    func detail(productID: String) async throws -> Product { fatalError() }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
    func categories() async throws -> [Category] { fatalError() }
}
