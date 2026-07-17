import DesignSystem
import UIKit
@preconcurrency import XCoordinator

enum AppRoute: Route {
    case login
}

@MainActor
protocol ApplicationChildFlow: AnyObject {
    var rootViewController: UIViewController { get }
}

typealias ApplicationChildFlowFactory = @MainActor () -> any ApplicationChildFlow

@MainActor
final class AppCoordinator: NavigationCoordinator<AppRoute>, ApplicationCoordinating {
    private let loginFlowFactory: ApplicationChildFlowFactory
    private var hasStarted = false

    init(loginFlowFactory: @escaping ApplicationChildFlowFactory = { PlaceholderLoginFlow() }) {
        self.loginFlowFactory = loginFlowFactory
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
        MainActor.assumeIsolated { [loginFlowFactory] in
            switch route {
            case .login:
                let loginFlow = loginFlowFactory()
                return .push(loginFlow.rootViewController)
            }
        }
    }
}

@MainActor
private final class PlaceholderLoginFlow: ApplicationChildFlow {
    let rootViewController: UIViewController

    init() {
        rootViewController = LoginPlaceholderViewController()
    }
}

@MainActor
private final class LoginPlaceholderViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Sign in"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ColorToken.backgroundPrimary.color
    }
}
