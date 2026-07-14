import DesignSystem
import LoginPresentation
import UIKit
@preconcurrency import XCoordinator

enum AppRoute: Route {
    case login
    case authenticated
}

@MainActor
final class AppCoordinator: NavigationCoordinator<AppRoute>, ApplicationCoordinating {
    private var hasStarted = false
    private var loginCoordinator: LoginCoordinator?

    init() {
        super.init(rootViewController: UINavigationController(), initialRoute: nil)
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        strongRouter.trigger(.login)
    }

    override func prepareTransition(for route: AppRoute) -> NavigationTransition {
        // XCoordinator's synchronous route API predates Swift actor annotations.
        // UIKit navigation invokes this hook on the main thread; assert that invariant at runtime.
        MainActor.assumeIsolated {
            switch route {
            case .login:
                let coordinator = AppContainer.shared.makeLoginCoordinator()
                loginCoordinator = coordinator
                coordinator.onResult = { [weak self] result in
                    guard case .authenticated = result else { return }
                    self?.loginCoordinator?.onResult = nil
                    self?.loginCoordinator = nil
                    self?.strongRouter.trigger(.authenticated)
                }
                return .push(coordinator.makeViewController())
            case .authenticated:
                return .push(AuthenticatedPlaceholderViewController())
            }
        }
    }
}

@MainActor
private final class AuthenticatedPlaceholderViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Products"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ColorToken.backgroundPrimary.color
    }
}
