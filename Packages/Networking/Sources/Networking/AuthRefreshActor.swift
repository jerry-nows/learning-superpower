import Foundation

/// Coordinates refresh requests so concurrent unauthorized requests share one
/// server call. The refresh operation is intentionally injected so the
/// networking layer does not own credentials or log token material.
@available(iOS 13, macOS 10.15, *)
public actor AuthRefreshActor<Output: Sendable> {
    public typealias RefreshOperation = @Sendable () async throws -> Output

    private let refreshOperation: RefreshOperation
    private var inFlight: Task<Output, Error>?
    private var generation: UInt = 0

    public init(refreshOperation: @escaping RefreshOperation) {
        self.refreshOperation = refreshOperation
    }

    /// Returns the result of a shared refresh operation.
    ///
    /// Cancellation of a waiter never cancels the operation shared by other
    /// callers. This prevents one request timing out from cancelling refresh
    /// for every request that received the same 401. Callers that need prompt
    /// cancellation should check their task state after this method returns.
    public func refresh() async throws -> Output {
        if let inFlight {
            return try await inFlight.value
        }

        generation &+= 1
        let currentGeneration = generation
        let task = Task { try await refreshOperation() }
        inFlight = task

        defer {
            if generation == currentGeneration {
                inFlight = nil
            }
        }

        return try await task.value
    }
}
