// TestSupport — fakes and fixtures for test targets
// Main code is in FakeScheduler.swift and FakePorts.swift

/// Yields enough times for pending Tasks to process. The executor and event
/// handlers spawn Tasks that need multiple run-loop turns.
@MainActor
public func settle(rounds: Int = 10) async {
    for _ in 0 ..< rounds {
        await Task.yield()
    }
}
