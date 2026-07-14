import Foundation
import Testing

@testable import SecurityKit

@Suite("LocalAuthenticationBiometricGate")
struct BiometricGateTests {
    @Test("returns successfully when biometrics authenticate")
    func success() async throws {
        let context = FakeBiometricContext(canEvaluate: true, result: .success(()))
        let gate = LocalAuthenticationBiometricGate { context }

        try await gate.authenticate(reason: "Unlock account")

        #expect(context.capturedReason == "Unlock account")
    }

    @Test("maps user cancellation to a typed cancellation")
    func cancellation() async {
        let context = FakeBiometricContext(canEvaluate: true, result: .failure(.cancelled))
        let gate = LocalAuthenticationBiometricGate { context }

        await expectFailure(.cancelled, from: gate, reason: "Sensitive action")
    }

    @Test("maps authentication failure without exposing a payload")
    func failureDoesNotLeakDetails() async {
        let context = FakeBiometricContext(canEvaluate: true, result: .failure(.failed))
        let gate = LocalAuthenticationBiometricGate { context }
        let reason = "Unlock account with secret customer payload"

        let error = await captureFailure(from: gate, reason: reason)

        #expect(error == .failed)
        #expect(String(describing: error) == "failed")
        #expect(!String(describing: error).contains(reason))
    }

    @Test("reports unavailable biometrics before requesting authentication")
    func unavailable() async {
        let context = FakeBiometricContext(canEvaluate: false, result: .success(()))
        let gate = LocalAuthenticationBiometricGate { context }

        await expectFailure(.unavailable, from: gate, reason: "Unlock account")

        #expect(context.capturedReason == nil)
    }

    private func expectFailure(
        _ expected: BiometricGateError,
        from gate: LocalAuthenticationBiometricGate,
        reason: String
    ) async {
        let actual = await captureFailure(from: gate, reason: reason)
        #expect(actual == expected)
    }

    private func captureFailure(
        from gate: LocalAuthenticationBiometricGate,
        reason: String
    ) async -> BiometricGateError {
        do {
            try await gate.authenticate(reason: reason)
            Issue.record("Expected biometric authentication to fail")
            return .failed
        } catch let error as BiometricGateError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return .failed
        }
    }
}

private final class FakeBiometricContext: BiometricContext, @unchecked Sendable {
    private let canEvaluate: Bool
    private let result: Result<Void, BiometricGateError>
    private(set) var capturedReason: String?

    init(canEvaluate: Bool, result: Result<Void, BiometricGateError>) {
        self.canEvaluate = canEvaluate
        self.result = result
    }

    func canEvaluateBiometrics() -> Bool { canEvaluate }

    func evaluateBiometrics(
        reason: String,
        completion: @escaping @Sendable (Result<Void, BiometricGateError>) -> Void
    ) {
        capturedReason = reason
        completion(result)
    }
}
