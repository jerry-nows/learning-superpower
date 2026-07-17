import Core
import Testing

@Suite("ConnectivityMonitor")
struct ConnectivityMonitorTests {
    @Test("stream emits initial and changed state")
    func emitsStates() async {
        let monitor = ConnectivityMonitor(initialStatus: .offline)
        var iterator = monitor.updates().makeAsyncIterator()
        #expect(await iterator.next() == .offline)
        monitor.update(.online)
        #expect(await iterator.next() == .online)
    }

    @Test("duplicate state does not emit another transition")
    func ignoresDuplicate() async {
        let monitor = ConnectivityMonitor(initialStatus: .online)
        var iterator = monitor.updates().makeAsyncIterator()
        #expect(await iterator.next() == .online)
        monitor.update(.online)
        let task = Task { await iterator.next() }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        #expect(await task.value == nil)
    }
}
