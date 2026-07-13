/// Input supplied by the application composition root when presenting login.
///
/// The value intentionally contains configuration only. Credentials and
/// implementation details remain private to LoginFeature.
public struct LoginFlowInput: Sendable, Equatable {
    public let configuration: LoginConfiguration

    public init(configuration: LoginConfiguration = .default) {
        self.configuration = configuration
    }
}

/// Policies that control the login experience without exposing UI types.
public struct LoginConfiguration: Sendable, Equatable {
    public enum BiometricPolicy: Sendable, Equatable {
        case disabled
        case optional
        case required
    }

    public enum CopyPolicy: Sendable, Equatable {
        case localized
        case fixed
    }

    public let biometricPolicy: BiometricPolicy
    public let localeIdentifier: String
    public let copyPolicy: CopyPolicy

    public init(
        biometricPolicy: BiometricPolicy = .optional,
        localeIdentifier: String = "en",
        copyPolicy: CopyPolicy = .localized
    ) {
        self.biometricPolicy = biometricPolicy
        self.localeIdentifier = localeIdentifier
        self.copyPolicy = copyPolicy
    }

    public static let `default` = LoginConfiguration()

    public var allowsBiometric: Bool {
        biometricPolicy != .disabled
    }
}

/// Terminal outcomes emitted by LoginFeature to the application root.
public enum LoginResult: Sendable, Equatable {
    case authenticated(userID: String)
    case cancelled
    case failed(LoginFailure)
}

/// Stable, transport-independent login failure reasons.
public enum LoginFailure: Sendable, Equatable {
    case invalidCredentials
    case validation
    case networkUnavailable
    case serviceUnavailable
    case biometricUnavailable
    case unknown
}
