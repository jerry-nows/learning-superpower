import Foundation

/// Stable identity for a catalog product. IDs are opaque and never derived from display data.
public struct Product: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let categoryID: String
    public let name: String
    public let description: String
    public let price: Int64
    public let currency: String
    public let stock: Int
    public let imageURL: URL?

    public init(
        id: String,
        categoryID: String,
        name: String,
        description: String = "",
        price: Int64,
        currency: String = "VND",
        stock: Int = 0,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name
        self.description = description
        self.price = price
        self.currency = currency
        self.stock = stock
        self.imageURL = imageURL
    }
}

public struct Category: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ProductFilter: Codable, Sendable, Equatable {
    public var minimumPrice: Int64?
    public var maximumPrice: Int64?
    public var inStockOnly: Bool

    public init(minimumPrice: Int64? = nil, maximumPrice: Int64? = nil, inStockOnly: Bool = false) {
        self.minimumPrice = minimumPrice
        self.maximumPrice = maximumPrice
        self.inStockOnly = inStockOnly
    }
}

public enum ProductSort: String, Codable, Sendable, Equatable {
    case newest
    case priceAscending = "price_asc"
    case priceDescending = "price_desc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
}

public struct Pagination: Codable, Sendable, Equatable {
    public let cursor: String?
    public let pageSize: Int
    public let hasNext: Bool

    public init(cursor: String? = nil, pageSize: Int = 20, hasNext: Bool = true) {
        self.cursor = cursor
        self.pageSize = max(1, pageSize)
        self.hasNext = hasNext
    }

    public static let initial = Pagination()
}

public struct ProductQuery: Codable, Sendable, Equatable {
    public var search: String
    public var categoryID: String?
    public var filter: ProductFilter
    public var sort: ProductSort
    public var pagination: Pagination

    public init(
        search: String = "",
        categoryID: String? = nil,
        filter: ProductFilter = .init(),
        sort: ProductSort = .newest,
        pagination: Pagination = .initial
    ) {
        self.search = search
        self.categoryID = categoryID
        self.filter = filter
        self.sort = sort
        self.pagination = pagination
    }
}

/// Independent state lets a detail screen replace one skeleton without hiding other sections.
public enum DetailSectionState<Value: Sendable & Equatable>: Sendable, Equatable {
    case skeleton
    case loaded(Value)
    case failed(String)

    public var isSkeleton: Bool {
        if case .skeleton = self { return true }
        return false
    }
}

public enum ProductDetailSection: String, CaseIterable, Sendable, Equatable {
    case product
    case reviews
    case comments
    case stock
}
