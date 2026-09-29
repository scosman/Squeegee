import ManualTestKit

enum WiredScripts {
    /// Returns wired copies of all canonical scripts, ready for the runner.
    /// Phase 2 replaces placeholder closures with real SystemBridge calls.
    static func all() -> [TestScript] {
        allScripts
    }
}
