import AppKit

/// Loads app icons for the menu off the main thread.
///
/// LaunchServices and IconServices calls can block when those services are
/// busy, so lookup and rendering run on a detached task. The result is a
/// fixed bitmap, so drawing it on the main thread does not call IconServices.
enum MenuIconLoader {
    static let pointSize: CGFloat = 16
    private static let scale: CGFloat = 2

    /// Returns the icon for `bundleID`, or nil when no app has that bundle ID.
    static func load(bundleID: String) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            render(bundleID: bundleID)
        }.value
    }

    private static func render(bundleID: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let source = workspace.icon(forFile: url.path)
        let size = NSSize(width: pointSize, height: pointSize)
        var rect = CGRect(x: 0, y: 0, width: pointSize * scale, height: pointSize * scale)
        guard let bitmap = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            source.size = size
            return source
        }
        return NSImage(cgImage: bitmap, size: size)
    }
}
