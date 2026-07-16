import Core
import MenuData
import Testing

@Test("failed read waits for connectivity and retries once")
func failedReadResumes() async throws {
    let monitor = ConnectivityMonitor(initialStatus: .offline)
    let coordinator = ProductResumeCoordinator(monitor: monitor)
    let attempts = LockBox(0)
    let task = Task {
        try await coordinator.executeRead {
            attempts.increment()
            if attempts.value == 1 { throw ProductRemoteDataSourceError.transport }
            return "loaded"
        }
    }
    try? await Task.sleep(for: .milliseconds(20))
    monitor.update(.online)
    #expect(try await task.value == "loaded")
    #expect(attempts.value == 2)
}

@Test("mutations are not retried while offline")
func mutationNotRetried() async {
    let monitor = ConnectivityMonitor(initialStatus: .offline)
    let coordinator = ProductResumeCoordinator(monitor: monitor)
    let attempts = LockBox(0)
    do {
        _ = try await coordinator.executeMutation {
            attempts.increment()
            throw ProductRemoteDataSourceError.transport
        }
        Issue.record("expected failure")
    } catch { }
    #expect(attempts.value == 1)
}

@Test("payments are not retried while offline")
func paymentNotRetried() async {
    let monitor = ConnectivityMonitor(initialStatus: .offline)
    let coordinator = ProductResumeCoordinator(monitor: monitor)
    let attempts = LockBox(0)
    do {
        _ = try await coordinator.executePayment {
            attempts.increment()
            throw ProductRemoteDataSourceError.transport
        }
        Issue.record("expected failure")
    } catch { }
    #expect(attempts.value == 1)
}

@Test("cancelled read resume returns without connectivity")
func cancelledReadResume() async {
    let monitor = ConnectivityMonitor(initialStatus: .offline)
    let coordinator = ProductResumeCoordinator(monitor: monitor)
    let task = Task {
        try await coordinator.executeRead {
            throw ProductRemoteDataSourceError.transport
        }
    }
    try? await Task.sleep(for: .milliseconds(20))
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("expected cancellation")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

private final class LockBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    func increment() where Value == Int { lock.lock(); storage += 1; lock.unlock() }
}
