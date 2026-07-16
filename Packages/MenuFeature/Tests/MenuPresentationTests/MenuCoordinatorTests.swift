#if canImport(UIKit)
import MenuData
import MenuDomain
@testable import MenuPresentation
import UIKit
import XCTest

@MainActor
final class MenuCoordinatorTests: XCTestCase {
    func testCoordinatorCreatesProductListEntryController() {
        let coordinator = MenuCoordinator(source: StubSource())

        let controller = coordinator.makeViewController()

        XCTAssertTrue(controller is ProductListViewController)
        XCTAssertEqual(coordinator.input, MenuFlowInput())
    }

    func testViewModelFactoryCanBeReplacedAtBoundary() {
        var invoked = false
        let coordinator = MenuCoordinator(
            source: StubSource(),
            viewModelFactory: { _, source in
                invoked = true
                return ProductListViewModel(source: source)
            }
        )

        _ = coordinator.makeViewController()

        XCTAssertTrue(invoked)
    }
}

private struct StubSource: ProductRemoteSource {
    func list(query: ProductQuery) async throws -> ProductPageResponse {
        .init(items: [], page: 1, pageSize: 20, total: 0, hasNext: false)
    }

    func detail(productID: String) async throws -> Product { fatalError() }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
    func categories() async throws -> [Category] { [] }
}
#endif
