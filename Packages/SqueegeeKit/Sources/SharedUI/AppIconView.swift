import AppKit
import SwiftUI
import Synchronization

/// Displays the icon of an app given its bundle ID. Falls back to a generic
/// app icon when the bundle cannot be located.
///
/// Icon lookup and rendering go through LaunchServices and IconServices, which
/// can block when those services are busy. Icons therefore load off the main
/// thread; the view shows an empty frame of the same size until the icon is
/// ready. Icons are cached process-wide by bundle ID as rendered bitmaps.
public struct AppIconView: View {
    let bundleID: String
    let size: CGFloat
    @State private var image: NSImage?

    public init(bundleID: String, size: CGFloat = 20) {
        self.bundleID = bundleID
        self.size = size
        _image = State(initialValue: Self.cachedIcon(for: bundleID))
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: bundleID) {
            if let cached = Self.cachedIcon(for: bundleID) {
                image = cached
                return
            }
            image = nil
            image = await Self.loadIcon(for: bundleID)
        }
    }

    // MARK: - Icon cache

    /// Point size the cached bitmaps are rendered for (the largest size in use),
    /// at 2x for Retina.
    private nonisolated static let renderPointSize: CGFloat = 48
    private nonisolated static let renderScale: CGFloat = 2

    private static let cache = Mutex<[String: NSImage]>([:])

    /// Removes all entries from the icon cache, releasing the cached images.
    /// Called when the main window closes to free memory while in tray-only mode.
    public static func clearCache() {
        cache.withLock { $0.removeAll() }
    }

    /// Returns the icon at `pointSize`, for AppKit menus. On a cache miss the
    /// icon loads off the main thread.
    public static func icon(for bundleID: String, pointSize: CGFloat) async -> NSImage {
        let image = if let cached = cachedIcon(for: bundleID) {
            cached
        } else {
            await loadIcon(for: bundleID)
        }
        guard let sized = image.copy() as? NSImage else { return image }
        sized.size = NSSize(width: pointSize, height: pointSize)
        return sized
    }

    static func cachedIcon(for bundleID: String) -> NSImage? {
        cache.withLock { $0[bundleID] }
    }

    /// Looks up and renders the icon on a detached task, then caches it.
    static func loadIcon(for bundleID: String) async -> NSImage {
        let image = await Task.detached(priority: .userInitiated) {
            renderIcon(for: bundleID)
        }.value
        cache.withLock { $0[bundleID] = image }
        return image
    }

    /// Renders the workspace icon into a fixed bitmap, so that drawing it later
    /// on the main thread does not call into IconServices.
    private nonisolated static func renderIcon(for bundleID: String) -> NSImage {
        let workspace = NSWorkspace.shared
        let source: NSImage = if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            workspace.icon(forFile: url.path)
        } else {
            workspace.icon(for: .applicationBundle)
        }

        let pixels = renderPointSize * renderScale
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        guard let bitmap = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return source
        }
        return NSImage(cgImage: bitmap, size: NSSize(width: renderPointSize, height: renderPointSize))
    }
}
