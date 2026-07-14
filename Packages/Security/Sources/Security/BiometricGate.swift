import Foundation

public enum BiometricGateError: Error, Equatable, Sendable {
    case unavailable
    case cancelled
    case failed
}

public protocol BiometricGate: Sendable {
    func authenticate(reason: String) async throws
}

public protocol BiometricContext: AnyObject {
    func canEvaluateBiometrics() -> Bool
    func evaluateBiometrics(reason: String, completion: @escaping @Sendable (Result<Void, BiometricGateError>) -> Void)
}

@available(macOS 10.15, iOS 13, *)
public final class LocalAuthenticationBiometricGate: BiometricGate, @unchecked Sendable {
    private let contextFactory: @Sendable () -> BiometricContext

    public init(contextFactory: @escaping @Sendable () -> BiometricContext = LocalAuthenticationBiometricGate.makeContext) {
        self.contextFactory = contextFactory
    }

    public func authenticate(reason: String) async throws {
        let context = contextFactory()
        guard context.canEvaluateBiometrics() else { throw BiometricGateError.unavailable }
        try await withCheckedThrowingContinuation { continuation in
            context.evaluateBiometrics(reason: reason) { result in
                continuation.resume(with: result)
            }
        }
    }

    public static func makeContext() -> BiometricContext {
        #if os(iOS) && !SWIFT_PACKAGE
        return LAContextAdapter()
        #else
        return UnavailableBiometricContext()
        #endif
    }
}

private final class UnavailableBiometricContext: BiometricContext {
    func canEvaluateBiometrics() -> Bool { false }
    func evaluateBiometrics(reason: String, completion: @escaping @Sendable (Result<Void, BiometricGateError>) -> Void) {
        completion(.failure(.unavailable))
    }
}

#if os(iOS) && !SWIFT_PACKAGE
import LocalAuthentication

private final class LAContextAdapter: BiometricContext, @unchecked Sendable {
    private let context = LAContext()

    func canEvaluateBiometrics() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func evaluateBiometrics(reason: String, completion: @escaping @Sendable (Result<Void, BiometricGateError>) -> Void) {
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            if success { completion(.success(())); return }
            guard let error = error as? LAError else { completion(.failure(.failed)); return }
            switch error.code {
            case .userCancel, .systemCancel, .appCancel, .authenticationFailed:
                completion(.failure(error.code == .authenticationFailed ? .failed : .cancelled))
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
                completion(.failure(.unavailable))
            default:
                completion(.failure(.failed))
            }
        }
    }
}
#endif
