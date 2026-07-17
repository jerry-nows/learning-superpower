import DesignSystem
import MenuData
import MenuDomain
import UIKit

/// Detail screen for a product. Each section is rendered independently so a
/// fast response can replace its skeleton while slower requests remain visible.
@MainActor
public final class ProductDetailViewController: UIViewController {
    public enum AccessibilityID {
        public static let scrollView = "product-detail.scroll"
        public static let productSection = "product-detail.product"
        public static let reviewsSection = "product-detail.reviews"
        public static let commentsSection = "product-detail.comments"
        public static let stockSection = "product-detail.stock"
    }

    private let viewModel: ProductDetailViewModel
    private let productID: String
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var stateTask: Task<Void, Never>?
    private var lastState: ProductDetailViewState?

    public init(productID: String, viewModel: ProductDetailViewModel) {
        self.productID = productID
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { stateTask?.cancel() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        render(viewModel.state)
        viewModel.load(productID: productID)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observeViewModel()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stateTask?.cancel()
        stateTask = nil
    }

    private func configureView() {
        view.backgroundColor = ColorToken.backgroundPrimary.color
        title = "Product details"
        scrollView.accessibilityIdentifier = AccessibilityID.scrollView
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func observeViewModel() {
        stateTask?.cancel()
        stateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let state = viewModel.state
                if state != lastState { render(state) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func render(_ state: ProductDetailViewState) {
        lastState = state
        let snapshot: ProductDetailSnapshot
        switch state {
        case .idle: snapshot = ProductDetailSnapshot()
        case let .loading(value), let .partial(value), let .loaded(value), let .offline(value), let .cancelled(value):
            snapshot = value
        }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(section(snapshot.product, title: "Product", id: AccessibilityID.productSection) { value in
            let label = self.label(value.name, style: .title2)
            let description = self.label(value.description.isEmpty ? "No description" : value.description, style: .body)
            description.numberOfLines = 0
            return [label, description, self.label("\(value.price) \(value.currency)", style: .headline)]
        } failed: { self.errorLabel($0) })
        stack.addArrangedSubview(section(snapshot.reviews, title: "Reviews", id: AccessibilityID.reviewsSection) { value in
            let rating = String(format: "%.1f", value.averageRating)
            return [self.label("\(rating) out of 5 · \(value.reviewCount) reviews", style: .body)]
        } failed: { self.errorLabel($0) })
        stack.addArrangedSubview(section(snapshot.comments, title: "Comments", id: AccessibilityID.commentsSection) { values in
            if values.isEmpty { return [self.label("No comments yet", style: .body)] }
            return values.map { self.label($0.body, style: .body) }
        } failed: { self.errorLabel($0) })
        stack.addArrangedSubview(section(snapshot.stock, title: "Availability", id: AccessibilityID.stockSection) { value in
            [self.label(value.available > 0 ? "\(value.available) in stock" : "Out of stock", style: .body)]
        } failed: { self.errorLabel($0) })
    }

    private func section<Value: Sendable & Equatable>(
        _ state: DetailSectionState<Value>,
        title: String,
        id: String,
        loaded: (Value) -> [UIView],
        failed: (String) -> UIView
    ) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        container.backgroundColor = ColorToken.surface.color
        container.layer.cornerRadius = 12
        container.accessibilityIdentifier = id
        let heading = label(title, style: .headline)
        heading.accessibilityTraits = .header
        container.addArrangedSubview(heading)
        switch state {
        case .skeleton:
            (0..<2).forEach { _ in
                let skeleton = SkeletonView()
                skeleton.translatesAutoresizingMaskIntoConstraints = false
                skeleton.heightAnchor.constraint(equalToConstant: 20).isActive = true
                skeleton.startAnimating()
                container.addArrangedSubview(skeleton)
            }
        case let .loaded(value): loaded(value).forEach(container.addArrangedSubview)
        case let .failed(message): container.addArrangedSubview(failed(message))
        }
        return container
    }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = ColorToken.textPrimary.color
        label.numberOfLines = 0
        return label
    }

    private func errorLabel(_ message: String) -> UIView {
        let label = label(message, style: .body)
        label.textColor = ColorToken.error.color
        label.accessibilityTraits = .staticText
        return label
    }
}
