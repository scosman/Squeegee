import AppKit
import SwiftUI

/// Displays the icon of an app given its bundle ID. Falls back to a generic
/// app icon when the bundle cannot be located. Icons are cached process-wide
/// by bundle ID at their original size; the SwiftUI view handles sizing.
public struct AppIconView: View {
    let bundleID: String
    let size: CGFloat

    public init(bundleID: String, size: CGFloat = 20) {
        self.bundleID = bundleID
        self.size = size
    }

    public var body: some View {
        Image(nsImage: Self.icon(for: bundleID))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    // MARK: - Icon cache

    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]

    /// Returns the cached icon for a bundle ID, loading it on first access.
    /// The image is stored at its original size; callers resize via SwiftUI.
    static func icon(for bundleID: String) -> NSImage {
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image: NSImage = if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.icon(forFile: url.path)
        } else {
            NSWorkspace.shared.icon(for: .applicationBundle)
        }

        lock.lock()
        cache[bundleID] = image
        lock.unlock()
        return image
    }
}
