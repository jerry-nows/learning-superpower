import Foundation

#if canImport(Network)
import Network
#endif

/// The reachability state used by read flows to decide whether a failed
/// request can be resumed. It intentionally contains no HTTP semantics.
public enum ConnectivityStatus: Sendable, Equatable {
    case online
    case offline
}

/// Small, testable wrapper around the system path monitor. Consumers receive
/// the current value immediately and then every subsequent transition.
public final class ConnectivityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ConnectivityStatus
    private var continuations: [UUID: AsyncStream<ConnectivityStatus>.Continuation] = [:]

    #if canImport(Network)
    private var pathMonitor: NWPathMonitor?
    private var monitorQueue: DispatchQueue?
    #endif

    public init(initialStatus: ConnectivityStatus = .online, startMonitoring: Bool = false) {
        state = initialStatus
        #if canImport(Network)
        pathMonitor = nil
        monitorQueue = nil
        if startMonitoring {
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "commerce.connectivity-monitor")
            monitor.pathUpdateHandler = { [weak self] path in
                self?.update(path.status == .satisfied ? .online : .offline)
            }
            monitor.start(queue: queue)
            self.pathMonitor = monitor
            self.monitorQueue = queue
        }
        #endif
    }

    deinit {
        #if canImport(Network)
        pathMonitor?.cancel()
        #endif
    }

    public var currentStatus: ConnectivityStatus {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    /// Returns an async stream that starts with the current state.
    public func updates() -> AsyncStream<ConnectivityStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuation.yield(state)
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.remove(id: id) }
        }
    }

    /// Injectable for deterministic tests and useful for app lifecycle hooks.
    public func update(_ newState: ConnectivityStatus) {
        lock.lock()
        guard state != newState else { lock.unlock(); return }
        state = newState
        let listeners = Array(continuations.values)
        lock.unlock()
        listeners.forEach { _ = $0.yield(newState) }
    }

    private func remove(id: UUID) {
        lock.lock(); continuations.removeValue(forKey: id); lock.unlock()
    }
}
