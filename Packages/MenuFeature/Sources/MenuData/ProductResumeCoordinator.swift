import Core
import Foundation

/// Request classes that are safe to distinguish at the data boundary.
public enum ProductRequestKind: Sendable, Equatable {
    case read
    case mutation
    case payment
}

/// Resumes a failed read once connectivity returns. Mutations and payments
/// are deliberately never retained or retried automatically.
public final class ProductResumeCoordinator: @unchecked Sendable {
    private let monitor: ConnectivityMonitor

    public init(monitor: ConnectivityMonitor) {
        self.monitor = monitor
    }

    public func executeRead<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch {
            guard monitor.currentStatus == .offline else { throw error }
            try await waitUntilOnline()
            return try await operation()
        }
    }

    public func executeMutation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await operation()
    }

    public func executePayment<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await operation()
    }

    public func execute<Value: Sendable>(
        kind: ProductRequestKind,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        switch kind {
        case .read: try await executeRead(operation)
        case .mutation: try await executeMutation(operation)
        case .payment: try await executePayment(operation)
        }
    }

    private func waitUntilOnline() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [monitor] in
                for await status in monitor.updates() where status == .online {
                    return
                }
                throw CancellationError()
            }
            // AsyncStream does not necessarily wake an iterator when its
            // parent task is cancelled. This sibling gives cancellation a
            // bounded wake-up path even when no connectivity event arrives.
            group.addTask {
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
