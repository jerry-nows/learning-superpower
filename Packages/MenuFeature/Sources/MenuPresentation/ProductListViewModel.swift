import Foundation
import MenuData
import MenuDomain

/// The immutable data rendered by the product list. Keeping the loaded rows in
/// the snapshot lets the UI show them while a refresh or next-page request is
/// in flight.
public struct ProductListSnapshot: Sendable, Equatable {
    public let items: [Product]
    public let query: ProductQuery
    public let hasNextPage: Bool
    public let nextPageSkeletonCount: Int
    public let categories: [Category]

    public init(
        items: [Product] = [],
        query: ProductQuery = .init(),
        hasNextPage: Bool = false,
        nextPageSkeletonCount: Int = 0,
        categories: [Category] = []
    ) {
        self.items = items
        self.query = query
        self.hasNextPage = hasNextPage
        self.nextPageSkeletonCount = max(0, nextPageSkeletonCount)
        self.categories = categories
    }
}

public enum ProductListViewState: Sendable, Equatable {
    case idle
    case loading
    case loaded(ProductListSnapshot)
    case refreshing(ProductListSnapshot)
    case loadingNextPage(ProductListSnapshot)
    case empty(ProductListSnapshot)
    case failure(ProductListSnapshot?, message: String)
}

/// Main-actor presentation state for the catalogue. Search is debounced and
/// every new query cancels the previous request, preventing stale responses
/// from replacing a newer result.
@MainActor
public final class ProductListViewModel {
    public private(set) var state: ProductListViewState = .idle

    private let source: any ProductRemoteSource
    private let searchDebounce: Duration
    private var requestTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var categoriesTask: Task<Void, Never>?
    private var snapshot = ProductListSnapshot()
    private var requestGeneration = 0

    public init(
        source: any ProductRemoteSource,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.source = source
        self.searchDebounce = searchDebounce
    }

    deinit {
        requestTask?.cancel()
        searchTask?.cancel()
        categoriesTask?.cancel()
    }

    public func load() {
        guard case .idle = state else { return }
        beginRequest(kind: .initial, query: snapshot.query)
    }

    /// Loads the allow-listed categories independently from the product page.
    /// A category response never clears rows that are already on screen.
    public func loadCategories() {
        guard categoriesTask == nil else { return }
        categoriesTask = Task { [weak self] in
            guard let self else { return }
            defer { categoriesTask = nil }
            do {
                let categories = try await source.categories()
                guard !Task.isCancelled else { return }
                snapshot = ProductListSnapshot(
                    items: snapshot.items,
                    query: snapshot.query,
                    hasNextPage: snapshot.hasNextPage,
                    nextPageSkeletonCount: snapshot.nextPageSkeletonCount,
                    categories: categories
                )
                updateStateSnapshot(snapshot)
            } catch is CancellationError {
                return
            } catch {
                // Category loading is auxiliary; the product list remains usable.
            }
        }
    }

    public func refresh() {
        cancelRequests()
        requestGeneration += 1
        snapshot = ProductListSnapshot(
            items: snapshot.items,
            query: resetPagination(snapshot.query),
            hasNextPage: false,
            categories: snapshot.categories
        )
        state = .refreshing(snapshot)
        beginRequest(kind: .refresh, query: snapshot.query)
    }

    public func loadNextPage() {
        guard snapshot.hasNextPage, requestTask == nil else { return }
        let nextCursor = String(max(2, snapshot.query.pagination.cursor.flatMap(Int.init).map { $0 + 1 } ?? 2))
        var query = snapshot.query
        query.pagination = Pagination(cursor: nextCursor, pageSize: snapshot.query.pagination.pageSize, hasNext: true)
        state = .loadingNextPage(snapshotFor(query: query, skeletons: query.pagination.pageSize))
        beginRequest(kind: .nextPage, query: query)
    }

    public func setSearch(_ value: String) {
        searchTask?.cancel()
        cancelRequestOnly()
        requestGeneration += 1
        var query = snapshot.query
        query.search = value
        query.pagination = .initial
        snapshot = ProductListSnapshot(query: query, categories: snapshot.categories)
        state = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: searchDebounce) } catch { return }
            guard !Task.isCancelled else { return }
            beginRequest(kind: .initial, query: query)
        }
    }

    public func setCategory(_ categoryID: String?) {
        var query = snapshot.query
        query.categoryID = categoryID
        applyQuery(query)
    }

    public func setFilter(_ filter: ProductFilter) {
        var query = snapshot.query
        query.filter = filter
        applyQuery(query)
    }

    public func setSort(_ sort: ProductSort) {
        var query = snapshot.query
        query.sort = sort
        applyQuery(query)
    }

    public func cancel() {
        cancelRequests()
        state = .idle
    }

    private enum RequestKind { case initial, refresh, nextPage }

    private func applyQuery(_ query: ProductQuery) {
        searchTask?.cancel()
        cancelRequestOnly()
        requestGeneration += 1
        var query = query
        query.pagination = .initial
        snapshot = ProductListSnapshot(query: query, categories: snapshot.categories)
        state = .loading
        beginRequest(kind: .initial, query: query)
    }

    private func beginRequest(kind: RequestKind, query: ProductQuery) {
        requestTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        if kind == .initial, state == .idle { state = .loading }
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == requestGeneration { requestTask = nil }
            }
            do {
                let page = try await source.list(query: query)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                apply(page, query: query, kind: kind)
            } catch is CancellationError {
                guard generation == requestGeneration else { return }
                switch kind {
                case .initial: state = .idle
                case .refresh, .nextPage: state = .loaded(snapshot)
                }
                return
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                state = .failure(kind == .initial ? nil : snapshot, message: message(for: error))
            }
        }
    }

    private func apply(_ page: ProductPageResponse, query: ProductQuery, kind: RequestKind) {
        let rows = kind == .nextPage ? snapshot.items + page.items : page.items
        let nextQuery = ProductQuery(
            search: query.search,
            categoryID: query.categoryID,
            filter: query.filter,
            sort: query.sort,
            pagination: Pagination(cursor: page.hasNext ? String(page.page) : nil, pageSize: page.pageSize, hasNext: page.hasNext)
        )
        snapshot = ProductListSnapshot(items: rows, query: nextQuery, hasNextPage: page.hasNext, categories: snapshot.categories)
        state = rows.isEmpty ? .empty(snapshot) : .loaded(snapshot)
    }

    private func snapshotFor(query: ProductQuery, skeletons: Int) -> ProductListSnapshot {
        ProductListSnapshot(items: snapshot.items, query: query, hasNextPage: true, nextPageSkeletonCount: skeletons, categories: snapshot.categories)
    }

    private func resetPagination(_ query: ProductQuery) -> ProductQuery {
        var result = query
        result.pagination = .initial
        return result
    }

    private func cancelRequests() {
        searchTask?.cancel()
        let categoriesTask = categoriesTask
        self.categoriesTask = nil
        categoriesTask?.cancel()
        cancelRequestOnly()
    }

    private func updateStateSnapshot(_ value: ProductListSnapshot) {
        switch state {
        case .loaded: state = .loaded(value)
        case .refreshing: state = .refreshing(value)
        case .loadingNextPage: state = .loadingNextPage(value)
        case .empty: state = .empty(value)
        case .failure: state = .failure(value, message: "Unable to load products.")
        case .idle, .loading: break
        }
    }

    private func cancelRequestOnly() {
        requestTask?.cancel()
        requestTask = nil
    }

    private func message(for error: Error) -> String {
        if let error = error as? ProductRemoteDataSourceError {
            switch error {
            case .transport, .serviceUnavailable: return "No internet connection."
            case .unauthorized: return "Your session has expired."
            case .notFound: return "Products were not found."
            case let .server(code): return code
            case .malformedResponse: return "The catalogue response was invalid."
            case .cancelled: return ""
            }
        }
        return "Unable to load products."
    }
}
