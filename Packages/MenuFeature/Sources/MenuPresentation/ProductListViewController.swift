import DesignSystem
import MenuDomain
import UIKit

/// UIKit catalogue screen. Product loading remains owned by `ProductListViewModel`;
/// the controller only translates user gestures into query changes and renders
/// the immutable view state.
@MainActor
public final class ProductListViewController: UIViewController {
    private let viewModel: ProductListViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private let categoryControl = UISegmentedControl()
    private let filterButton = UIButton(type: .system)
    private let sortButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let refreshControl = UIRefreshControl()
    private var stateTask: Task<Void, Never>?
    private var lastState: ProductListViewState?

    public init(viewModel: ProductListViewModel) {
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
        viewModel.load()
        viewModel.loadCategories()
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
        title = "Products"
        view.backgroundColor = ColorToken.backgroundPrimary.color
        tableView.backgroundColor = ColorToken.backgroundPrimary.color
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ProductCell.self, forCellReuseIdentifier: ProductCell.reuseIdentifier)
        tableView.register(ProductSkeletonCell.self, forCellReuseIdentifier: ProductSkeletonCell.reuseIdentifier)
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        refreshControl.accessibilityLabel = "Refresh products"

        searchBar.placeholder = "Search products"
        searchBar.searchTextField.accessibilityLabel = "Search products"
        searchBar.delegate = self
        searchBar.returnKeyType = .search

        categoryControl.accessibilityLabel = "Product category"
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        categoryControl.isHidden = true

        configureButton(filterButton, title: "Filter", action: #selector(showFilters))
        configureButton(sortButton, title: "Sort", action: #selector(showSortOptions))

        let controls = UIStackView(arrangedSubviews: [filterButton, sortButton])
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [searchBar, categoryControl, controls])
        header.axis = .vertical
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        tableView.tableHeaderView = header

        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = TypographyToken.body.font()
        emptyLabel.textColor = ColorToken.textSecondary.color
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.accessibilityTraits = .staticText
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: guide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            emptyLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor)
        ])
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = TypographyToken.body.font()
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = title
        button.accessibilityTraits = .button
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
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

    private func render(_ state: ProductListViewState) {
        lastState = state
        switch state {
        case .idle, .loading:
            emptyLabel.isHidden = true
            tableView.reloadData()
        case let .loaded(snapshot), let .refreshing(snapshot), let .loadingNextPage(snapshot):
            emptyLabel.isHidden = true
            updateCategories(snapshot.categories)
            tableView.reloadData()
            if case .refreshing = state { refreshControl.beginRefreshing() } else { refreshControl.endRefreshing() }
        case let .empty(snapshot):
            emptyLabel.text = "No products found.\nTry changing your search or filters."
            emptyLabel.isHidden = false
            updateCategories(snapshot.categories)
            tableView.reloadData()
            refreshControl.endRefreshing()
        case let .failure(snapshot, message):
            emptyLabel.text = message
            emptyLabel.isHidden = snapshot?.items.isEmpty == false
            tableView.reloadData()
            refreshControl.endRefreshing()
        }
        tableView.accessibilityValue = accessibilityValue(for: state)
    }

    private func updateCategories(_ categories: [Category]) {
        guard categoryControl.numberOfSegments != categories.count + 1 else { return }
        categoryControl.removeAllSegments()
        categoryControl.insertSegment(withTitle: "All", at: 0, animated: false)
        for (index, category) in categories.enumerated() {
            categoryControl.insertSegment(withTitle: category.name, at: index + 1, animated: false)
        }
        categoryControl.selectedSegmentIndex = 0
        categoryControl.isHidden = categories.isEmpty
        if var frame = tableView.tableHeaderView?.frame {
            frame.size.height = categories.isEmpty ? 112 : 152
            tableView.tableHeaderView?.frame = frame
        }
    }

    private func accessibilityValue(for state: ProductListViewState) -> String {
        switch state {
        case .idle: return "Ready"
        case .loading: return "Loading products"
        case let .loaded(snapshot): return "(snapshot.items.count) products"
        case let .refreshing(snapshot): return "Refreshing, (snapshot.items.count) products"
        case let .loadingNextPage(snapshot): return "Loading more, (snapshot.items.count) products"
        case .empty: return "No products"
        case .failure: return "Unable to load products"
        }
    }

    @objc private func refresh() { viewModel.refresh() }

    @objc private func categoryChanged() {
        guard categoryControl.selectedSegmentIndex > 0 else { viewModel.setCategory(nil); return }
        guard case let .loaded(snapshot) = viewModel.state,
              categoryControl.selectedSegmentIndex - 1 < snapshot.categories.count else { return }
        viewModel.setCategory(snapshot.categories[categoryControl.selectedSegmentIndex - 1].id)
    }

    @objc private func showFilters() {
        let alert = UIAlertController(title: "Filter", message: nil, preferredStyle: .actionSheet)
        let inStock = currentFilter.inStockOnly
        alert.addAction(UIAlertAction(title: inStock ? "Include out-of-stock" : "In stock only", style: .default) { [weak self] _ in
            guard let self else { return }
            var filter = currentFilter
            filter.inStockOnly.toggle()
            viewModel.setFilter(filter)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func showSortOptions() {
        let alert = UIAlertController(title: "Sort products", message: nil, preferredStyle: .actionSheet)
        let options: [(String, ProductSort)] = [
            ("Newest", .newest),
            ("Price: low to high", .priceAscending),
            ("Price: high to low", .priceDescending),
            ("Name: A to Z", .nameAscending)
        ]
        for (title, sort) in options {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in self?.viewModel.setSort(sort) })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private var currentFilter: ProductFilter {
        switch viewModel.state {
        case let .loaded(snapshot), let .refreshing(snapshot), let .loadingNextPage(snapshot), let .empty(snapshot): return snapshot.query.filter
        default: return .init()
        }
    }
}

extension ProductListViewController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch viewModel.state {
        case .loading: return 5
        case let .loaded(snapshot), let .refreshing(snapshot), let .loadingNextPage(snapshot): return snapshot.items.count + snapshot.nextPageSkeletonCount
        case let .empty(snapshot), let .failure(snapshot, _): return snapshot?.items.count ?? 0
        case .idle: return 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch viewModel.state {
        case .loading:
            return tableView.dequeueReusableCell(withIdentifier: ProductSkeletonCell.reuseIdentifier, for: indexPath)
        case let .loaded(snapshot), let .refreshing(snapshot), let .loadingNextPage(snapshot):
            guard indexPath.row < snapshot.items.count else { return tableView.dequeueReusableCell(withIdentifier: ProductSkeletonCell.reuseIdentifier, for: indexPath) }
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProductCell.reuseIdentifier, for: indexPath) as? ProductCell else {
                return UITableViewCell()
            }
            cell.configure(product: snapshot.items[indexPath.row])
            return cell
        case let .empty(snapshot), let .failure(snapshot, _):
            guard let product = snapshot?.items[indexPath.row] else { return UITableViewCell() }
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProductCell.reuseIdentifier, for: indexPath) as? ProductCell else {
                return UITableViewCell()
            }
            cell.configure(product: product)
            return cell
        case .idle: return UITableViewCell()
        }
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard case let .loaded(snapshot) = viewModel.state,
              snapshot.hasNextPage, indexPath.row >= snapshot.items.count - 2 else { return }
        viewModel.loadNextPage()
    }
}

extension ProductListViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { viewModel.setSearch(searchText) }
}

@MainActor
private final class ProductCell: UITableViewCell {
    static let reuseIdentifier = "ProductCell"
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        nameLabel.font = TypographyToken.body.font()
        nameLabel.textColor = ColorToken.textPrimary.color
        nameLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = TypographyToken.caption.font()
        detailLabel.textColor = ColorToken.textSecondary.color
        detailLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(product: Product) {
        nameLabel.text = product.name
        detailLabel.text = "\(product.price) \(product.currency) · \(product.stock) in stock"
        accessibilityLabel = "\(product.name), \(detailLabel.text ?? "")"
    }
}

@MainActor
private final class ProductSkeletonCell: UITableViewCell {
    static let reuseIdentifier = "ProductSkeletonCell"
    private let skeleton = SkeletonView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(skeleton)
        NSLayoutConstraint.activate([
            skeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            skeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            skeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            skeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            skeleton.heightAnchor.constraint(equalToConstant: 20)
        ])
        skeleton.startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
