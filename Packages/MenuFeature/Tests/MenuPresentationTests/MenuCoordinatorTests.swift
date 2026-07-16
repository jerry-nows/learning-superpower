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

    func testSelectingAProductEmitsSelectedResult() async {
        var result: MenuResult?
        let coordinator = MenuCoordinator(source: StubSource(page: .init(
            items: [Product(id: "product-7", categoryID: "c", name: "Coffee", price: 10)],
            page: 1, pageSize: 20, total: 1, hasNext: false
        )))
        coordinator.onResult = { result = $0 }
        let controller = coordinator.makeViewController()
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        let table = descendants(of: controller.view, matching: UITableView.self).first
        for _ in 0..<20 {
            if table?.numberOfRows(inSection: 0) == 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        if let table { controller.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0)) }
        XCTAssertEqual(result, .selectedProduct(id: "product-7"))
        controller.viewDidDisappear(false)
    }

    private func descendants<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            let matches = child as? T
            return (matches.map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }
}

private struct StubSource: ProductRemoteSource {
    let page: ProductPageResponse

    init(page: ProductPageResponse = .init(items: [], page: 1, pageSize: 20, total: 0, hasNext: false)) {
        self.page = page
    }

    func list(query: ProductQuery) async throws -> ProductPageResponse {
        page
    }

    func detail(productID: String) async throws -> Product { fatalError() }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
    func categories() async throws -> [Category] { [] }
}
#endif
