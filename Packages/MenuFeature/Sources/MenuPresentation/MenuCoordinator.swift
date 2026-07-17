import MenuData
import MenuDomain
import UIKit

/// Factory used by the composition root to replace menu presentation in tests.
public typealias MenuViewModelFactory = @MainActor (
    _ input: MenuFlowInput,
    _ source: any ProductRemoteSource
) -> ProductListViewModel

/// UIKit flow boundary for MenuFeature. Hosts receive only `MenuResult` and do
/// not need to know about repositories, Moya targets, or view-model state.
@MainActor
public final class MenuCoordinator {
    public let input: MenuFlowInput
    private let source: any ProductRemoteSource
    private let viewModelFactory: MenuViewModelFactory

    public var onResult: (@MainActor (MenuResult) -> Void)?

    public init(
        input: MenuFlowInput = .init(),
        source: any ProductRemoteSource,
        viewModelFactory: @escaping MenuViewModelFactory = { _, source in
            ProductListViewModel(source: source)
        },
        onResult: (@MainActor (MenuResult) -> Void)? = nil
    ) {
        self.input = input
        self.source = source
        self.viewModelFactory = viewModelFactory
        self.onResult = onResult
    }

    public func makeViewController() -> ProductListViewController {
        ProductListViewController(
            viewModel: viewModelFactory(input, source),
            showsCategories: input.showsCategories,
            onProductSelected: { [weak self] productID in
                self?.onResult?(.selectedProduct(id: productID))
            }
        )
    }
}
