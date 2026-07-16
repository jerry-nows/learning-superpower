import Foundation
import MenuData
import MenuDomain

/// The four independently rendered sections of a product detail screen.
/// Keeping the states separate allows a completed section to replace its
/// skeleton while slower requests continue to load.
public struct ProductDetailSnapshot: Sendable, Equatable {
    public var product: DetailSectionState<Product>
    public var reviews: DetailSectionState<ProductRatingSummary>
    public var comments: DetailSectionState<[ProductComment]>
    public var stock: DetailSectionState<ProductStock>

    public init(
        product: DetailSectionState<Product> = .skeleton,
        reviews: DetailSectionState<ProductRatingSummary> = .skeleton,
        comments: DetailSectionState<[ProductComment]> = .skeleton,
        stock: DetailSectionState<ProductStock> = .skeleton
    ) {
        self.product = product
        self.reviews = reviews
        self.comments = comments
        self.stock = stock
    }

    public var completedSectionCount: Int {
        [product.isSkeleton, reviews.isSkeleton, comments.isSkeleton, stock.isSkeleton]
            .filter { !$0 }.count
    }

    public var hasFailures: Bool {
        Self.isFailed(product) || Self.isFailed(reviews) || Self.isFailed(comments) || Self.isFailed(stock)
    }

    private static func isFailed<Value>(_ state: DetailSectionState<Value>) -> Bool where Value: Sendable & Equatable {
        if case .failed = state { return true }
        return false
    }
}

public enum ProductDetailViewState: Sendable, Equatable {
    case idle
    case loading(ProductDetailSnapshot)
    case partial(ProductDetailSnapshot)
    case loaded(ProductDetailSnapshot)
    case offline(ProductDetailSnapshot)
    case cancelled(ProductDetailSnapshot)
}

private enum DetailFetchResult: Sendable {
    case product(ResultValue<Product>)
    case reviews(ResultValue<ProductRatingSummary>)
    case comments(ResultValue<[ProductComment]>)
    case stock(ResultValue<ProductStock>)
}

/// Loads product detail sections concurrently. A request never waits for a
/// sibling request before publishing its result, which keeps skeletons and
/// already-loaded content visible during slow or partial responses.
@MainActor
public final class ProductDetailViewModel {
    public private(set) var state: ProductDetailViewState = .idle

    private let source: any ProductRemoteSource
    private var requestTask: Task<Void, Never>?
    private var snapshot = ProductDetailSnapshot()
    private var generation = 0

    public init(source: any ProductRemoteSource) {
        self.source = source
    }

    deinit { requestTask?.cancel() }

    public func load(productID: String) {
        requestTask?.cancel()
        generation += 1
        let requestGeneration = generation
        snapshot = ProductDetailSnapshot()
        state = .loading(snapshot)

        requestTask = Task { [weak self] in
            guard let self else { return }
            await self.loadSections(productID: productID, generation: requestGeneration)
        }
    }

    public func cancel() {
        requestTask?.cancel()
        requestTask = nil
        state = .cancelled(snapshot)
    }

    private func loadSections(productID: String, generation requestGeneration: Int) async {
        await withTaskGroup(of: DetailFetchResult?.self) { group in
            group.addTask { [source] in await Self.fetchProduct(source: source, productID: productID) }
            group.addTask { [source] in await Self.fetchReviews(source: source, productID: productID) }
            group.addTask { [source] in await Self.fetchComments(source: source, productID: productID) }
            group.addTask { [source] in await Self.fetchStock(source: source, productID: productID) }

            for await result in group {
                guard !Task.isCancelled else { return }
                guard let result else { continue }
                apply(result, generation: requestGeneration)
            }
        }

        guard requestGeneration == generation else { return }
        requestTask = nil
        if case .loading = state { state = .loaded(snapshot) }
    }

    private func apply(_ result: DetailFetchResult, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        switch result {
        case let .product(value): snapshot.product = value.state
        case let .reviews(value): snapshot.reviews = value.state
        case let .comments(value): snapshot.comments = value.state
        case let .stock(value): snapshot.stock = value.state
        }

        if result.isOfflineFailure {
            state = .offline(snapshot)
        } else if snapshot.completedSectionCount == 4 {
            if snapshot.hasFailures {
                state = snapshot.isOffline ? .offline(snapshot) : .partial(snapshot)
            } else {
                state = .loaded(snapshot)
            }
        } else {
            state = .partial(snapshot)
        }
    }

    private static func fetchProduct(source: any ProductRemoteSource, productID: String) async -> DetailFetchResult? {
        do { return .product(.success(try await source.detail(productID: productID))) }
        catch is CancellationError { return nil }
        catch { return .product(.failure(message(for: error), offline: isOffline(error))) }
    }

    private static func fetchReviews(source: any ProductRemoteSource, productID: String) async -> DetailFetchResult? {
        do { return .reviews(.success(try await source.ratingSummary(productID: productID))) }
        catch is CancellationError { return nil }
        catch { return .reviews(.failure(message(for: error), offline: isOffline(error))) }
    }

    private static func fetchComments(source: any ProductRemoteSource, productID: String) async -> DetailFetchResult? {
        do { return .comments(.success(try await source.comments(productID: productID))) }
        catch is CancellationError { return nil }
        catch { return .comments(.failure(message(for: error), offline: isOffline(error))) }
    }

    private static func fetchStock(source: any ProductRemoteSource, productID: String) async -> DetailFetchResult? {
        do { return .stock(.success(try await source.inventory(productID: productID))) }
        catch is CancellationError { return nil }
        catch { return .stock(.failure(message(for: error), offline: isOffline(error))) }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? ProductRemoteDataSourceError {
            switch error {
            case .transport, .serviceUnavailable: return "No internet connection."
            case .unauthorized: return "Your session has expired."
            case .notFound: return "This section was not found."
            case let .server(code): return code
            case .malformedResponse: return "The response was invalid."
            case .cancelled: return "Request cancelled."
            }
        }
        return "Unable to load this section."
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? ProductRemoteDataSourceError else { return false }
        switch error { case .transport, .serviceUnavailable: return true; default: return false }
    }
}

public enum ResultValue<Value: Sendable & Equatable>: Sendable, Equatable {
    case success(Value)
    case failure(String, offline: Bool)

    var state: DetailSectionState<Value> {
        switch self {
        case let .success(value): return .loaded(value)
        case let .failure(message, _): return .failed(message)
        }
    }
}

private extension ProductDetailSnapshot {
    var isOffline: Bool {
        Self.isOffline(product) || Self.isOffline(reviews) || Self.isOffline(comments) || Self.isOffline(stock)
    }

    private static func isOffline<Value>(_ state: DetailSectionState<Value>) -> Bool where Value: Sendable & Equatable {
        if case let .failed(message) = state { return message == "No internet connection." }
        return false
    }
}

private extension DetailFetchResult {
    var isOfflineFailure: Bool {
        switch self {
        case let .product(value): return value.isOfflineFailure
        case let .reviews(value): return value.isOfflineFailure
        case let .comments(value): return value.isOfflineFailure
        case let .stock(value): return value.isOfflineFailure
        }
    }
}

private extension ResultValue {
    var isOfflineFailure: Bool {
        if case let .failure(_, offline) = self { return offline }
        return false
    }
}
