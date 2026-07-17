/// Configuration supplied by the application when presenting the catalogue.
/// The feature keeps transport and UIKit details behind this boundary.
public struct MenuFlowInput: Sendable, Equatable {
    public let showsCategories: Bool

    public init(showsCategories: Bool = true) {
        self.showsCategories = showsCategories
    }
}

/// Terminal events emitted by the menu flow to its host coordinator.
public enum MenuResult: Sendable, Equatable {
    case selectedProduct(id: String)
    case cancelled
}
