#if canImport(UIKit)
import MenuData
import MenuDomain
@testable import MenuPresentation
import UIKit
import XCTest

@MainActor
final class ProductListViewControllerTests: XCTestCase {
    func testListExposesSearchAndAccessibleFilterControls() {
        let controller = ProductListViewController(viewModel: ProductListViewModel(source: StubSource()))
        load(controller)
        XCTAssertNotNil(descendants(of: controller.view, matching: UISearchBar.self).first)
        XCTAssertEqual(descendants(of: controller.view, matching: UIButton.self).map(\.accessibilityLabel).compactMap { $0 }, ["Filter", "Sort"])
    }

    func testLoadingStateShowsSkeletonRows() {
        let model = ProductListViewModel(source: StubSource())
        let controller = ProductListViewController(viewModel: model)
        load(controller)
        model.load()
        let table = descendants(of: controller.view, matching: UITableView.self).first
        XCTAssertEqual(table?.accessibilityValue, "Loading products")
        XCTAssertEqual(table?.numberOfRows(inSection: 0), 5)
    }

    func testEmptyStateShowsRecoveryMessage() async {
        let model = ProductListViewModel(source: StubSource(page: .init(items: [], page: 1, pageSize: 20, total: 0, hasNext: false)))
        let controller = ProductListViewController(viewModel: model)
        load(controller)
        model.load()
        for _ in 0..<20 {
            if case .empty = model.state { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        controller.view.layoutIfNeeded()
        XCTAssertTrue(descendants(of: controller.view, matching: UILabel.self).contains { $0.text?.contains("No products found") == true })
    }

    func testLoadedStateAnnouncesProductCount() async {
        let model = ProductListViewModel(source: StubSource())
        let controller = ProductListViewController(viewModel: model)
        load(controller)
        controller.viewWillAppear(false)
        for _ in 0..<20 {
            if case .loaded = model.state { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let table = descendants(of: controller.view, matching: UITableView.self).first
        XCTAssertEqual(table?.accessibilityValue, "1 products")
        controller.viewDidDisappear(false)
    }

    func testCategoryConfigurationCanHideCategoryLoading() async {
        let model = ProductListViewModel(source: StubSource(categories: [Category(id: "c", name: "Coffee")]))
        let controller = ProductListViewController(viewModel: model, showsCategories: false)
        load(controller)
        for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(5)) }
        let control = descendants(of: controller.view, matching: UISegmentedControl.self).first
        XCTAssertTrue(control?.isHidden == true)
        controller.viewDidDisappear(false)
    }

    private func load(_ controller: UIViewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
    }

    private func descendants<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            let matches = child as? T
            return (matches.map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }
}

private final class StubSource: ProductRemoteSource, @unchecked Sendable {
    let page: ProductPageResponse
    let categoryValues: [Category]
    init(page: ProductPageResponse = .init(
        items: [Product(id: "1", categoryID: "c", name: "Coffee", price: 10)],
        page: 1,
        pageSize: 20,
        total: 1,
        hasNext: false
    ), categories: [Category] = []) {
        self.page = page
        self.categoryValues = categories
    }
    func list(query: ProductQuery) async throws -> ProductPageResponse { page }
    func detail(productID: String) async throws -> Product { page.items[0] }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
    func categories() async throws -> [Category] { categoryValues }
}
#endif
