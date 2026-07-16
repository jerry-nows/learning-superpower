import Foundation
import MenuDomain
import Networking

/// Moya targets for the read-only product catalogue API.
///
/// The target deliberately models each detail section as an independent
/// request. This lets the presentation layer render a completed section while
/// another section is still loading. Only values from the domain allow-lists
/// (for example `ProductSort`) are sent to the server.
public enum ProductTarget: TargetType, Sendable {
    case list(baseURL: URL, query: ProductQuery, accessToken: String?)
    case detail(baseURL: URL, productID: String, accessToken: String?)
    case inventory(baseURL: URL, productID: String, accessToken: String?)
    case ratingSummary(baseURL: URL, productID: String, accessToken: String?)
    case comments(baseURL: URL, productID: String, accessToken: String?)
    case categories(baseURL: URL, accessToken: String?)

    public var baseURL: URL {
        switch self {
        case let .list(baseURL, _, _), let .detail(baseURL, _, _),
             let .inventory(baseURL, _, _), let .ratingSummary(baseURL, _, _),
             let .comments(baseURL, _, _), let .categories(baseURL, _):
            baseURL
        }
    }

    public var path: String {
        switch self {
        case .list:
            "/v1/products"
        case let .detail(_, productID, _):
            "/v1/products/\(Self.pathComponent(productID))"
        case let .inventory(_, productID, _):
            "/v1/products/\(Self.pathComponent(productID))/inventory"
        case let .ratingSummary(_, productID, _):
            "/v1/products/\(Self.pathComponent(productID))/rating-summary"
        case let .comments(_, productID, _):
            "/v1/products/\(Self.pathComponent(productID))/comments"
        case .categories:
            "/v1/categories"
        }
    }

    public var method: Moya.Method { .get }

    public var task: Moya.Task {
        guard case let .list(_, query, _) = self else { return .requestPlain }
        return .requestParameters(parameters: Self.parameters(for: query), encoding: URLEncoding.queryString)
    }

    public var headers: [String: String]? {
        var result = ["Accept": "application/json"]
        if let accessToken = accessToken {
            result["Authorization"] = "Bearer \(accessToken)"
        }
        return result
    }

    public var validationType: ValidationType { .successCodes }

    public var sampleData: Data { Data("{}".utf8) }

    private var accessToken: String? {
        switch self {
        case let .list(_, _, accessToken), let .detail(_, _, accessToken),
             let .inventory(_, _, accessToken), let .ratingSummary(_, _, accessToken),
             let .comments(_, _, accessToken), let .categories(_, accessToken):
            accessToken
        }
    }

    private static func parameters(for query: ProductQuery) -> [String: Any] {
        var parameters: [String: Any] = [
            "page_size": min(max(query.pagination.pageSize, 1), 100),
            "sort": query.sort.rawValue
        ]
        if let cursor = query.pagination.cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { parameters["search"] = search }
        if let categoryID = query.categoryID, !categoryID.isEmpty {
            parameters["category_id"] = categoryID
        }
        if let minimumPrice = query.filter.minimumPrice, minimumPrice >= 0 {
            parameters["min_price"] = minimumPrice
        }
        if let maximumPrice = query.filter.maximumPrice, maximumPrice >= 0 {
            parameters["max_price"] = maximumPrice
        }
        if query.filter.inStockOnly { parameters["in_stock"] = true }
        return parameters
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension ProductTarget: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ProductTarget(GET \(path))" }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror("ProductTarget(GET \(path))", unlabeledChildren: [], displayStyle: .enum)
    }
}
