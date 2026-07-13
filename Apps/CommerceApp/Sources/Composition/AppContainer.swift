import FactoryKit
import UIKit

@MainActor
protocol ApplicationCoordinating: AnyObject {
    var rootViewController: UINavigationController { get }
    func start()
}

typealias AppContainer = Container

@MainActor
extension Container {
    var appCoordinator: Factory<any ApplicationCoordinating> {
        self { AppCoordinator() }.singleton
    }

    func makeAppCoordinator() -> any ApplicationCoordinating {
        appCoordinator()
    }
}
