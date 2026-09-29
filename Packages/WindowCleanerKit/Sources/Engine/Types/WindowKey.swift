import Foundation

/// A unique identifier for a window within a running process. The pair of
/// process ID and Core Graphics window ID is unique at any moment, but
/// a pid can be reused after the process exits.
public struct WindowKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let pid: Int32
    public let windowID: UInt32

    public init(pid: Int32, windowID: UInt32) {
        self.pid = pid
        self.windowID = windowID
    }

    public var description: String {
        "WindowKey(pid: \(pid), windowID: \(windowID))"
    }
}
