import Foundation
import MenuData
import MenuDomain
import Moya
import Testing

private let baseURL = URL(string: "https://api.example.invalid")!

@Test("list target encodes allow-listed query values")
func listTargetQueryContract() throws {
    let target = ProductTarget.list(
        baseURL: baseURL,
        query: ProductQuery(
            search: "  shoes  ",
            categoryID: "footwear",
            filter: .init(minimumPrice: 100, maximumPrice: 500, inStockOnly: true),
            sort: .priceDescending,
            pagination: .init(cursor: "next-page", pageSize: 150)
        ),
        accessToken: "access-secret"
    )

    #expect(target.path == "/v1/products")
    #expect(target.method == .get)
    #expect(target.headers?["Authorization"] == "Bearer access-secret")
    guard case let .requestParameters(parameters, _) = target.task else {
        Issue.record("expected query parameters")
        return
    }
    #expect(parameters["search"] as? String == "shoes")
    #expect(parameters["category_id"] as? String == "footwear")
    #expect(parameters["sort"] as? String == "price_desc")
    #expect(parameters["cursor"] as? String == "next-page")
    #expect(parameters["page_size"] as? Int == 100)
    #expect(parameters["min_price"] as? Int64 == 100)
    #expect(parameters["max_price"] as? Int64 == 500)
    #expect(parameters["in_stock"] as? Bool == true)
}

@Test("detail section targets use independent read endpoints")
func detailTargetEndpoints() {
    let targets: [(ProductTarget, String)] = [
        (.detail(baseURL: baseURL, productID: "item/42", accessToken: nil), "/v1/products/item%2F42"),
        (.inventory(baseURL: baseURL, productID: "item-42", accessToken: nil), "/v1/products/item-42/inventory"),
        (.ratingSummary(baseURL: baseURL, productID: "item-42", accessToken: nil), "/v1/products/item-42/rating-summary"),
        (.comments(baseURL: baseURL, productID: "item-42", accessToken: nil), "/v1/products/item-42/comments"),
        (.categories(baseURL: baseURL, accessToken: nil), "/v1/categories")
    ]

    for (target, path) in targets {
        #expect(target.path == path)
        #expect(target.method == .get)
        if case .requestPlain = target.task {
            // expected for all non-list reads
        } else {
            Issue.record("expected an empty GET body for \(path)")
        }
    }
}

@Test("target diagnostics redact bearer tokens and query payloads")
func targetDiagnosticsAreRedacted() {
    let target = ProductTarget.list(
        baseURL: baseURL,
        query: .init(search: "private search", categoryID: "private-category"),
        accessToken: "access-secret"
    )

    #expect(!target.description.contains("access-secret"))
    #expect(!target.description.contains("private search"))
    #expect(!String(reflecting: target).contains("access-secret"))
    #expect(!String(reflecting: target).contains("private-category"))
    #expect(!String(decoding: target.sampleData, as: UTF8.self).contains("token"))
}
