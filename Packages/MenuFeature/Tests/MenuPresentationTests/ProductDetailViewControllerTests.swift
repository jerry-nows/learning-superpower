#if canImport(UIKit)
import MenuData
import MenuDomain
import MenuPresentation
import UIKit
import XCTest

@MainActor
final class ProductDetailViewControllerTests: XCTestCase {
    func testSectionsExposeStableAccessibilityIdentifiers() {
        XCTAssertEqual(ProductDetailViewController.AccessibilityID.productSection, "product-detail.product")
        XCTAssertEqual(ProductDetailViewController.AccessibilityID.reviewsSection, "product-detail.reviews")
        XCTAssertEqual(ProductDetailViewController.AccessibilityID.commentsSection, "product-detail.comments")
        XCTAssertEqual(ProductDetailViewController.AccessibilityID.stockSection, "product-detail.stock")
    }

    func testDetailViewUsesDynamicTypeAndRendersSkeletons() {
        let controller = ProductDetailViewController(
            productID: "p-1",
            viewModel: ProductDetailViewModel(source: StubSource())
        )
        controller.loadViewIfNeeded()
        let labels = controller.view.subviews
            .compactMap { $0 as? UIScrollView }
            .flatMap { $0.subviews }
            .flatMap { ($0 as? UIStackView)?.arrangedSubviews ?? [] }
            .flatMap { ($0 as? UIStackView)?.arrangedSubviews ?? [] }
            .compactMap { $0 as? UILabel }
        XCTAssertTrue(labels.allSatisfy { $0.adjustsFontForContentSizeCategory })
    }
}

private struct StubSource: ProductRemoteSource {
    func list(query: ProductQuery) async throws -> ProductPageResponse { fatalError() }
    func categories() async throws -> [Category] { fatalError() }
    func detail(productID: String) async throws -> Product { fatalError() }
    func inventory(productID: String) async throws -> ProductStock { fatalError() }
    func ratingSummary(productID: String) async throws -> ProductRatingSummary { fatalError() }
    func comments(productID: String) async throws -> [ProductComment] { fatalError() }
}
#endif
