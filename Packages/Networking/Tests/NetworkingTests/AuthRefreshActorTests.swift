import Foundation
import Testing
@testable import Networking

private enum RefreshTestError: Error, Equatable, Sendable {
    case unavailable
}

private actor RefreshProbe {
    private(set) var invocationCount = 0

    func invoke() async throws -> String {
        invocationCount += 1
        try await Task.sleep(for: .milliseconds(30))
        return "refreshed"
    }

    func fail() async throws -> String {
        invocationCount += 1
        try await Task.sleep(for: .milliseconds(30))
        throw RefreshTestError.unavailable
    }
}

@available(iOS 13, macOS 10.15, *)
@Test("concurrent refresh callers share one operation")
func concurrentRefreshIsSingleFlight() async throws {
    let probe = RefreshProbe()
    let actor = AuthRefreshActor<String>(refreshOperation: { try await probe.invoke() })

    let results = await withTaskGroup(of: Result<String, Error>.self, returning: [Result<String, Error>].self) { group in
        for _ in 0..<16 {
            group.addTask {
                do { return .success(try await actor.refresh()) }
                catch { return .failure(error) }
            }
        }

        var collected: [Result<String, Error>] = []
        for await result in group { collected.append(result) }
        return collected
    }

    #expect(results.count == 16)
    #expect(results.compactMap { try? $0.get() } == Array(repeating: "refreshed", count: 16))
    #expect(await probe.invocationCount == 1)
}

@available(iOS 13, macOS 10.15, *)
@Test("refresh failure is shared and a later call can retry")
func refreshFailureIsSharedAndClearsFlight() async throws {
    let probe = RefreshProbe()
    let actor = AuthRefreshActor<String>(refreshOperation: { try await probe.fail() })

    let results = await withTaskGroup(of: Result<String, Error>.self, returning: [Result<String, Error>].self) { group in
        for _ in 0..<4 {
            group.addTask {
                do { return .success(try await actor.refresh()) }
                catch { return .failure(error) }
            }
        }
        var collected: [Result<String, Error>] = []
        for await result in group { collected.append(result) }
        return collected
    }

    #expect(results.count == 4)
    #expect(results.allSatisfy {
        guard case let .failure(error) = $0 else { return false }
        return (error as? RefreshTestError) == .unavailable
    })
    #expect(await probe.invocationCount == 1)

    do {
        _ = try await actor.refresh()
        Issue.record("expected the retry to fail")
    } catch let error as RefreshTestError {
        #expect(error == .unavailable)
    }
    #expect(await probe.invocationCount == 2)
}

@available(iOS 13, macOS 10.15, *)
@Test("cancelling one waiter does not cancel the shared refresh")
func cancelledWaiterDoesNotCancelOperation() async throws {
    let probe = RefreshProbe()
    let actor = AuthRefreshActor<String>(refreshOperation: { try await probe.invoke() })
    let cancelled = Task { try await actor.refresh() }
    cancelled.cancel()

    let result = try await actor.refresh()
    #expect(result == "refreshed")
    #expect(await probe.invocationCount == 1)
    _ = try? await cancelled.value
}
