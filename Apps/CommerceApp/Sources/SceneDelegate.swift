import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let appCoordinator = AppContainer.shared.makeAppCoordinator()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = appCoordinator.rootViewController
        self.window = window
        self.appCoordinator = appCoordinator
        appCoordinator.start()
        window.makeKeyAndVisible()
    }
}
