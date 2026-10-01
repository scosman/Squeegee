import AppKit
import Engine

/// Implements `AppTerminating` with a normal terminate request. Never force-quits.
public struct LiveAppTerminator: AppTerminating, Sendable {
    public init() {}

    public func terminate(pid: Int32) async -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}
