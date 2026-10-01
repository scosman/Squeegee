import ApplicationServices
import Engine
import os

/// An `@unchecked Sendable` wrapper for an `AXUIElement`. The element is only
/// accessed on the `AXWindowService` actor; the wrapper exists to satisfy the
/// `Sendable` checker.
struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}

/// Implements `WindowInspecting` and `WindowClosing` through the Accessibility
/// framework, sharing a single element cache.
public actor AXWindowService: WindowInspecting, WindowClosing {
    private static let logger = Logger(
        subsystem: "net.scosman.squeegee",
        category: "AXWindowService"
    )

    public init() {}

    // MARK: - Private bridge

    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Resolved at runtime so a missing symbol degrades instead of crashing.
    /// RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    private static let axGetWindow: AXGetWindowFn? = {
        // swiftlint:disable:next force_unwrapping
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2)!, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXGetWindowFn.self)
    }()

    /// Whether the private window ID bridge is available on this system.
    public static var isBridgeAvailable: Bool {
        axGetWindow != nil
    }

    // MARK: - Element cache

    private var cache: [WindowKey: AXElementBox] = [:]

    /// Bounds of CG windows per pid, for the fallback matching when the private
    /// bridge is unavailable. Updated by `updateBounds(_:)`.
    private var lastBoundsByPID: [Int32: [(windowID: UInt32, bounds: CGRect)]] = [:]

    /// Updates the CG bounds used for the fallback window ID matching.
    /// Called by AppCore after each `listWindows()`.
    public func updateBounds(_ windows: [ObservedWindow]) {
        var grouped: [Int32: [(windowID: UInt32, bounds: CGRect)]] = [:]
        for window in windows {
            grouped[window.key.pid, default: []].append((windowID: window.key.windowID, bounds: window.bounds))
        }
        lastBoundsByPID = grouped
    }

    // MARK: - Inspect

    public func inspect(pid: Int32) async -> InspectionResult {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        var windowsRef: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)

        if let mapped = AXHelpers.mapCopyError(copyResult) {
            return mapped
        }

        guard let windowElements = windowsRef as? [AXUIElement] else {
            return .inspected([:])
        }

        var map: [UInt32: WindowMetadata] = [:]

        for element in windowElements {
            guard let windowID = windowIDForElement(element, pid: pid) else {
                continue
            }

            let metadata = readMetadata(from: element)
            let key = WindowKey(pid: pid, windowID: windowID)
            cache[key] = AXElementBox(element: element)
            map[windowID] = metadata
        }

        return .inspected(map)
    }

    // MARK: - Focused window

    public func focusedWindowID(pid: Int32) async -> UInt32? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard result == .success, let focused = focusedRef else { return nil }

        // The focused element is an AXUIElement
        let element = focused as! AXUIElement // swiftlint:disable:this force_cast
        return windowIDForElement(element, pid: pid)
    }

    // MARK: - Close

    public func close(_ key: WindowKey) async -> CloseAttemptResult {
        // Step 1: Refresh the cache by inspecting the app.
        let listing = await inspect(pid: key.pid)

        let (wasListed, latestMetadata) = extractListingInfo(listing, windowID: key.windowID)
        if case .notTrusted = listing { return .notTrusted }

        // Step 2: Look up the cached element.
        guard let box = cache[key] else {
            return .unreachable
        }

        // Step 3: Read and press the close button.
        return pressCloseButton(on: box.element, key: key, wasListed: wasListed, latestMetadata: latestMetadata)
    }

    private func extractListingInfo(
        _ listing: InspectionResult,
        windowID: UInt32
    ) -> (wasListed: Bool, latest: WindowMetadata?) {
        switch listing {
        case let .inspected(map):
            (map[windowID] != nil, map[windowID])
        case .appUnavailable, .notTrusted:
            (false, nil)
        }
    }

    private func pressCloseButton(
        on element: AXUIElement,
        key: WindowKey,
        wasListed: Bool,
        latestMetadata: WindowMetadata?
    ) -> CloseAttemptResult {
        var closeRef: CFTypeRef?
        let closeResult = AXUIElementCopyAttributeValue(
            element,
            kAXCloseButtonAttribute as CFString,
            &closeRef
        )

        switch closeResult {
        case .success:
            break
        case .noValue, .attributeUnsupported:
            return .noCloseButton
        case .invalidUIElement:
            cache[key] = nil
            return .unreachable
        case .apiDisabled:
            return .notTrusted
        default:
            return .noCloseButton
        }

        let button = closeRef as! AXUIElement // swiftlint:disable:this force_cast
        let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)

        switch pressResult {
        case .success:
            return .pressed(latest: latestMetadata, wasListed: wasListed)
        case .invalidUIElement:
            cache[key] = nil
            return .unreachable
        case .apiDisabled:
            return .notTrusted
        default:
            return .failed(code: pressResult.rawValue)
        }
    }

    // MARK: - Forget

    public func forget(pid: Int32) {
        cache = cache.filter { $0.key.pid != pid }
        lastBoundsByPID[pid] = nil
    }

    // MARK: - Window ID resolution

    private func windowIDForElement(_ element: AXUIElement, pid: Int32) -> UInt32? {
        // Primary: use the private bridge.
        if let getWindowFn = Self.axGetWindow {
            var windowID: CGWindowID = 0
            let result = getWindowFn(element, &windowID)
            if result == .success, windowID != 0 {
                return windowID
            }
        }

        // Fallback: match by bounds.
        return fallbackMatchByBounds(element: element, pid: pid)
    }

    /// Matches an AX element to a CG window ID by comparing position and size
    /// against the latest CG scan data. Returns the ID only when exactly one
    /// CG window matches within 2 pt tolerance.
    func fallbackMatchByBounds(element: AXUIElement, pid: Int32) -> UInt32? {
        guard let cgWindows = lastBoundsByPID[pid], !cgWindows.isEmpty else { return nil }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // AXValue extraction
        guard let posVal = positionRef, CFGetTypeID(posVal) == AXValueGetTypeID(),
              AXValueGetValue(posVal as! AXValue, .cgPoint, &position), // swiftlint:disable:this force_cast
              let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID(),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        else {
            return nil
        }

        return AXHelpers.matchBounds(
            position: position,
            size: size,
            candidates: cgWindows
        )
    }

    // MARK: - Metadata reading

    private func readMetadata(from element: AXUIElement) -> WindowMetadata {
        guard let values = copyMultipleAttributes(from: element) else {
            return WindowMetadata(isStandard: false)
        }
        return parseMetadata(from: values)
    }

    private func copyMultipleAttributes(from element: AXUIElement) -> [Any?]? {
        let attributes = [
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXMinimizedAttribute,
            kAXCloseButtonAttribute,
            kAXDocumentAttribute,
            kAXURLAttribute
        ] as [String]

        var valuesRef: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            [],
            &valuesRef
        )
        guard result == .success, let values = valuesRef as? [Any?] else { return nil }
        return values
    }

    private func parseMetadata(from values: [Any?]) -> WindowMetadata {
        let subrole = safeValue(values, at: 0) as? String
        let title = safeValue(values, at: 1) as? String
        let isMinimized = safeValue(values, at: 2) as? Bool ?? false
        let closeButton = safeValue(values, at: 3)
        let documentAttr = safeValue(values, at: 4) as? String
        let urlAttr = safeValue(values, at: 5)

        let isStandard = subrole == kAXStandardWindowSubrole && closeButton != nil
        let documentURL = AXHelpers.resolveDocumentURL(documentString: documentAttr, urlAttribute: urlAttr)

        return WindowMetadata(
            isStandard: isStandard,
            title: title,
            documentURL: documentURL,
            isMinimized: isMinimized
        )
    }

    /// Safe accessor that handles kAXErrorX sentinel values in multi-attribute results.
    private func safeValue(_ values: [Any?], at index: Int) -> Any? {
        guard index < values.count else { return nil }
        let raw = values[index]
        if raw is NSNull || raw == nil { return nil }
        return raw
    }
}
