import ApplicationServices
import CoreGraphics
import Engine
import Foundation

/// Pure helper functions extracted from `AXWindowService` for testability and
/// to keep the actor body within the lint limit.
public enum AXHelpers {
    // MARK: - Document URL resolution

    /// Resolves a document URL from the `kAXDocumentAttribute` string and
    /// `kAXURLAttribute` value. Only file URLs are accepted.
    public static func resolveDocumentURL(documentString: String?, urlAttribute: Any?) -> URL? {
        if let docURL = documentURLFromString(documentString) {
            return docURL
        }
        return fileURLFromAXURL(urlAttribute)
    }

    /// Parses `kAXDocumentAttribute` (a string) into a file URL, or nil.
    public static func documentURLFromString(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }

    /// Extracts a file URL from `kAXURLAttribute` (a CFURL), or nil.
    public static func fileURLFromAXURL(_ attribute: Any?) -> URL? {
        guard let attribute else { return nil }
        let url: URL
        if let cfURL = attribute as? URL {
            url = cfURL
        } else if CFGetTypeID(attribute as CFTypeRef) == CFURLGetTypeID() {
            url = attribute as! URL // swiftlint:disable:this force_cast
        } else {
            return nil
        }
        return url.isFileURL ? url : nil
    }

    // MARK: - AX error mapping

    /// Maps an `AXError` from `AXUIElementCopyAttributeValue` on the windows
    /// attribute to an `InspectionResult`, or nil for `.success`.
    public static func mapCopyError(_ error: AXError) -> InspectionResult? {
        switch error {
        case .success:
            nil
        case .apiDisabled:
            .notTrusted
        case .cannotComplete, .notImplemented, .invalidUIElement:
            .appUnavailable
        case .noValue:
            .inspected([:])
        default:
            .appUnavailable
        }
    }

    // MARK: - Bounds matching

    /// Pure matching: finds the unique CG window whose bounds match the given
    /// position and size within 2 pt tolerance. Returns nil if zero or multiple
    /// candidates match.
    public static func matchBounds(
        position: CGPoint,
        size: CGSize,
        candidates: [(windowID: UInt32, bounds: CGRect)]
    ) -> UInt32? {
        let tolerance: CGFloat = 2
        let matches = candidates.filter { entry in
            abs(entry.bounds.origin.x - position.x) <= tolerance &&
                abs(entry.bounds.origin.y - position.y) <= tolerance &&
                abs(entry.bounds.width - size.width) <= tolerance &&
                abs(entry.bounds.height - size.height) <= tolerance
        }

        guard matches.count == 1 else { return nil }
        return matches[0].windowID
    }
}
