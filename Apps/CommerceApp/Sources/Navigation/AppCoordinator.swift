import DesignSystem
import UIKit
@preconcurrency import XCoordinator

enum AppRoute: Route {
    case login
}

@MainActor
final class AppCoordinator: NavigationCoordinator<AppRoute>, ApplicationCoordinating {
    private var hasStarted = false

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
                .push(LoginPlaceholderViewController())
            }
        }
    }
}

@MainActor
private final class LoginPlaceholderViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Sign in"
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
