import Foundation
import LoginDomain

/// UI state deliberately contains stable domain values and localized copy,
/// rather than transport errors or UIKit types.
public enum LoginViewState: Sendable, Equatable {
    case idle
    case validating
    case loading
    case success(LoginResult)
    case failure(LoginFailure, message: String)
}

@MainActor
public final class LoginViewModel {
    public private(set) var state: LoginViewState = .idle

    private let input: LoginFlowInput
    private let authenticator: any LoginAuthenticator
    private var loginTask: Task<Void, Never>?

    public init(input: LoginFlowInput = .init(), authenticator: any LoginAuthenticator) {
        self.input = input
        self.authenticator = authenticator
    }

    deinit {
        loginTask?.cancel()
    }

    public func submit(email: String, password: String) {
        loginTask?.cancel()
        state = .validating

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(email: normalizedEmail), !password.isEmpty else {
            state = .failure(.validation, message: message(for: .validation))
            return
        }

        state = .loading
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let userID = try await authenticator.authenticate(
                    email: normalizedEmail,
                    password: password
                )
                guard !Task.isCancelled else { return }
                state = .success(.authenticated(userID: userID))
            } catch is CancellationError {
                return
            } catch let error as LoginAuthenticationError {
                guard !Task.isCancelled else { return }
                switch error {
                case let .failure(failure):
                    state = .failure(failure, message: message(for: failure))
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failure(.unknown, message: message(for: .unknown))
            }
        }
    }

    public func cancel() {
        loginTask?.cancel()
        loginTask = nil
        state = .idle
    }

    private func isValid(email: String) -> Bool {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex,
              at != email.index(before: email.endIndex) else { return false }
        return !email.contains(" ")
    }

    private func message(for failure: LoginFailure) -> String {
        if input.configuration.copyPolicy == .fixed {
            return "Unable to sign in."
        }
        let vietnamese = input.configuration.localeIdentifier.lowercased().hasPrefix("vi")
        if vietnamese {
            switch failure {
            case .invalidCredentials: return "Email hoặc mật khẩu không đúng."
            case .validation: return "Vui lòng nhập email và mật khẩu hợp lệ."
            case .networkUnavailable: return "Không có kết nối mạng."
            case .serviceUnavailable: return "Dịch vụ hiện không khả dụng."
            case .biometricUnavailable: return "Xác thực sinh trắc học không khả dụng."
            case .unknown: return "Đã xảy ra lỗi. Vui lòng thử lại."
            }
        }
        switch failure {
        case .invalidCredentials: return "The email or password is incorrect."
        case .validation: return "Enter a valid email and password."
        case .networkUnavailable: return "No internet connection."
        case .serviceUnavailable: return "The service is unavailable."
        case .biometricUnavailable: return "Biometric authentication is unavailable."
        case .unknown: return "Something went wrong. Please try again."
        }
    }
}
