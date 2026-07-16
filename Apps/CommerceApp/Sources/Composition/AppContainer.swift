import FactoryKit
import Foundation
import LoginData
import LoginDomain
import LoginPresentation
import MenuData
import MenuDomain
import MenuPresentation
import Networking
import SecurityKit
import UIKit

@MainActor
protocol ApplicationCoordinating: AnyObject {
    var rootViewController: UINavigationController { get }
    func start()
}

typealias AppContainer = Container

@MainActor
extension Container {
    /// Runtime API endpoint is replaceable so tests never need to contact the
    /// network and alternate environments can be configured at launch.
    var apiBaseURL: Factory<URL> {
        self {
            let configured = ProcessInfo.processInfo.environment["API_BASE_URL"]
            return URL(string: configured ?? "http://127.0.0.1:8080")!
        }.singleton
    }

    /// Secure storage is app-scoped, while token values remain in Keychain and
    /// are never retained by the composition root itself.
    var tokenStore: Factory<any TokenStore> {
        self { try! KeychainTokenStore() }.singleton
    }

    var biometricGate: Factory<any BiometricGate> {
        self { LocalAuthenticationBiometricGate() }.singleton
    }

    var authRemoteDataSource: Factory<any AuthRemoteSource> {
        self { AuthRemoteDataSource(baseURL: self.apiBaseURL()) }.singleton
    }

    var authRepository: Factory<DefaultAuthRepository> {
        self {
            DefaultAuthRepository(
                remote: self.authRemoteDataSource(),
                tokenStore: self.tokenStore()
            )
        }.singleton
    }

    var loginAuthenticator: Factory<any LoginAuthenticator> {
        self { self.authRepository() }.singleton
    }

    var loginCoordinator: Factory<LoginViewModelFactory> {
        self { { input, authenticator in
            LoginViewModel(input: input, authenticator: authenticator)
        }}
    }

    var productRemoteSource: Factory<any ProductRemoteSource> {
        self {
            let accessToken = try? self.tokenStore().load()?.accessToken
            return ProductRemoteDataSource(baseURL: self.apiBaseURL(), accessToken: accessToken)
        }.singleton
    }

    var menuCoordinator: Factory<MenuViewModelFactory> {
        self { { input, source in
            ProductListViewModel(source: source)
        }}
    }

    var appCoordinator: Factory<any ApplicationCoordinating> {
        self { AppCoordinator() }.singleton
    }

    func makeAppCoordinator() -> any ApplicationCoordinating {
        appCoordinator()
    }

    func makeLoginCoordinator(input: LoginFlowInput = .init()) -> LoginCoordinator {
        return LoginCoordinator(
            input: input,
            authenticator: loginAuthenticator(),
            viewModelFactory: loginCoordinator()
        )
    }

    func makeMenuCoordinator(input: MenuFlowInput = .init()) -> MenuCoordinator {
        MenuCoordinator(
            input: input,
            source: productRemoteSource(),
            viewModelFactory: menuCoordinator()
        )
    }
}
