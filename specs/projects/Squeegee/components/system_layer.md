---
status: complete
---

# Component: System Layer (ports + `SystemBridge`)

This covers everything that touches macOS window, accessibility, and workspace APIs. The **ports** (protocols and their value types) live in `Engine/Ports/` (Foundation only). The **live implementations** live in the `SystemBridge` module. `AppCore` sees only the ports.

Research: [window enumeration](../research/macos-window-apis/window-enumeration-identity-closing/summary.md), [activity signals](../research/macos-window-apis/activity-signals/summary.md), [permissions](../research/macos-window-apis/permissions-sandbox-distribution/summary.md).

## 1. Ports (in `Engine`)

```swift
// MARK: Values
public struct ObservedApp: Sendable, Equatable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let launchDate: Date?
}

public struct ObservedWindow: Sendable, Equatable {       // from the CG scan
    public let key: WindowKey
    public let app: ObservedApp
    public let bounds: CGRect
    public let isOnScreen: Bool
}

public struct WindowMetadata: Sendable, Equatable {       // from Accessibility
    public var isStandard: Bool          // subrole == AXStandardWindow AND has a close button
    public var title: String?
    public var documentURL: URL?         // file URL only
    public var isMinimized: Bool
}

public enum InspectionResult: Sendable, Equatable {
    case inspected([UInt32: WindowMetadata])   // windows AX can see now (current Space + minimized), by CGWindowID
    case appUnavailable                        // AX timeout / cannot complete / app gone
    case notTrusted                            // kAXErrorAPIDisabled
}

public enum CloseAttemptResult: Sendable, Equatable {
    case pressed(latest: WindowMetadata?, wasListed: Bool)  // AXPress delivered; wasListed = window was in the app's AX window list at that moment
    case unreachable                                        // no AX element for this window (other Space, never seen)
    case noCloseButton
    case failed(code: Int32)                                // other AXError
    case notTrusted
}

public enum WorkspaceEvent: Sendable, Equatable {
    case appActivated(ObservedApp)
    case appDeactivated(pid: Int32)
    case appLaunched(ObservedApp)
    case appTerminated(pid: Int32)
    case activeSpaceChanged
    case displaysSlept, displaysWoke
    case sessionResigned, sessionBecameActive               // fast user switching; treated like sleep/wake
    case ownAppBecameActive                                 // Squeegee itself became active
}

public struct FocusSignal: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case focusMayHaveChanged, windowCreated }
    public let pid: Int32
    public let kind: Kind
    public let at: Date                                     // timestamp taken inside the AX callback
}

public struct InstalledApp: Sendable, Equatable { public let bundleID: String; public let name: String; public let url: URL }

// MARK: Ports
public protocol WindowListing: Sendable { func listWindows() async -> [ObservedWindow] }

public protocol WindowInspecting: Sendable {
    func inspect(pid: Int32) async -> InspectionResult
    func focusedWindowID(pid: Int32) async -> UInt32?
    func forget(pid: Int32) async
}

public protocol WindowClosing: Sendable { func close(_ key: WindowKey) async -> CloseAttemptResult }

public protocol AppTerminating: Sendable { func terminate(pid: Int32) async -> Bool }   // true = request delivered

public protocol WorkspaceEventSource: Sendable {
    func events() -> AsyncStream<WorkspaceEvent>
    func frontmostApp() -> ObservedApp?
    func areDisplaysAsleep() -> Bool
}

public protocol FocusObserving: Sendable {
    func signals() -> AsyncStream<FocusSignal>
    func observe(pid: Int32?) async          // moves the single observer; nil = observe nothing
}

public protocol AccessibilityPermissionPort: Sendable {
    func isTrusted() -> Bool
    func requestPrompt()                     // system prompt + opens System Settings
    func openSystemSettings()
    func changes() -> AsyncStream<Void>      // fires when the system AX trust list may have changed
}

public protocol LoginItemPort: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

public protocol InstalledAppScanning: Sendable { func installedApps() async -> [InstalledApp] }

public protocol AppOpening: Sendable {
    func open(documentURL: URL, withBundleID: String) async throws
    func launch(bundleID: String) async throws                // activate if running
    func fileExists(_ url: URL) -> Bool
}

public protocol AppScheduler: Sendable {                      // clock + timers; see engine.md §6.2
    func now() -> Date
    @MainActor func schedule(at date: Date, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
    @MainActor func schedule(every interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
}
public protocol Cancellable: Sendable { func cancel() }

public struct AppCorePorts: Sendable {                         // one bag, passed to AppCore
    public var windowLister: any WindowListing
    public var windowInspector: any WindowInspecting
    public var windowCloser: any WindowClosing
    public var appTerminator: any AppTerminating
    public var workspace: any WorkspaceEventSource
    public var focus: any FocusObserving
    public var permission: any AccessibilityPermissionPort
    public var loginItem: any LoginItemPort
    public var installedApps: any InstalledAppScanning
    public var opener: any AppOpening
    public var scheduler: any AppScheduler
}
```

`SystemBridge` exposes `public enum LivePorts { @MainActor public static func make() -> AppCorePorts }`. One `AXWindowService` instance implements `WindowInspecting` and `WindowClosing`, so both share the element cache.

## 2. `CGWindowLister` (implements `WindowListing`)

- Call: `CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)` from a detached task (never on main).
- Parsing is a pure static function, unit-tested with fixture dictionaries:

```swift
static func parse(_ infos: [[String: Any]], ownPID: Int32, appLookup: (Int32) -> ObservedApp?) -> [ObservedWindow]
```

Keep an entry only when **all** of these are true:
1. `kCGWindowLayer == 0`.
2. `kCGWindowAlpha > 0`.
3. `kCGWindowOwnerPID != ownPID`.
4. Bounds width ≥ 40 and height ≥ 40 (this drops helper and tracking windows).
5. `appLookup(pid)` returns an app (via `NSRunningApplication(processIdentifier:)`) with a bundle ID, and `activationPolicy != .prohibited`.
6. The bundle ID is not in `SystemBridge.excludedBundleIDs`: `com.apple.dock`, `com.apple.WindowManager`, `com.apple.controlcenter`, `com.apple.notificationcenterui`, `com.apple.systemuiserver`, `com.apple.loginwindow`, `com.apple.Spotlight`, `com.apple.screencaptureui`, `com.apple.ScreenContinuity`, and any bundle ID with prefix `net.scosman.squeegee`.

- `isOnScreen` = `kCGWindowIsOnscreen as? Bool ?? false`. It is informational only. The engine does not depend on it (because of the macOS 14/15 bug from the research).
- `kCGWindowName` is never read (it needs Screen Recording).
- `appLookup` caches `ObservedApp` per pid for the duration of one call.
- **Hardware findings** (hardware_findings.md): each native tab is its own CG window. A full-screen window keeps its ID, and macOS adds a second window for it. AX gives no metadata for either while the user is not on that Space, so the extra window stays at `metadata == nil` (unmanaged) until AX lists it.

## 3. `AXWindowService` (actor; implements `WindowInspecting` + `WindowClosing`)

### 3.1 Private bridge

Resolve it at runtime so that a missing symbol degrades the feature instead of breaking the launch:

```swift
typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
static let axGetWindow: AXGetWindowFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil } // RTLD_DEFAULT
    return unsafeBitCast(sym, to: AXGetWindowFn.self)
}()
```

`static var isBridgeAvailable: Bool` is exposed to the ManualTestApp and logged at startup.

### 3.2 Element cache

- `private var cache: [WindowKey: AXElementBox]`, where `struct AXElementBox: @unchecked Sendable { let element: AXUIElement }`. The box never leaves the actor.
- Every `inspect(pid:)` refreshes the cache entries for the windows it finds. Entries for windows it does not find are **kept**. They may be on another Space, and they are the "kept element" of design option A.
- `forget(pid:)` drops all entries for that pid (called on app terminate).
- The cache has no size limit; it is bounded by the number of live windows.

### 3.3 `inspect(pid:)`

1. `let app = AXUIElementCreateApplication(pid)` and `AXUIElementSetMessagingTimeout(app, 0.5)`.
2. Copy `kAXWindowsAttribute`. Map errors:
   - `.apiDisabled` → `.notTrusted`.
   - `.cannotComplete`, `.notImplemented`, `.invalidUIElement`, and a timeout → `.appUnavailable`.
   - `.noValue` → `.inspected([:])`.
3. For each window element, in one IPC call: `AXUIElementCopyMultipleAttributeValues(window, [kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, kAXCloseButtonAttribute, kAXDocumentAttribute, kAXURLAttribute], [], &values)`.
4. The window ID comes from `axGetWindow`. **Fallback when the bridge is missing:** match `kAXPositionAttribute` + `kAXSizeAttribute` to the CG bounds of that pid's windows from the latest scan, with a tolerance of 2 pt. If zero or more than one CG window matches, skip the window. The actor keeps `lastBoundsByPID` from the most recent `listWindows()` result; `AppCore` passes it with `updateBounds(_:)`, which is internal and used only in fallback mode.
5. `isStandard = subrole == kAXStandardWindowSubrole && closeButton != nil`.
6. `documentURL`:
   - `kAXDocumentAttribute` is a string. Use `URL(string:)`, and accept it only if `isFileURL`.
   - Otherwise, if `kAXURLAttribute` is a `CFURL`, accept it only if it is a file URL.
   - Otherwise `nil`.
   - Both mapping functions are pure static functions with unit tests.
7. Return `.inspected(map)` and update the cache.

### 3.4 `focusedWindowID(pid:)`

App element (timeout 0.5 s) → `kAXFocusedWindowAttribute` → `axGetWindow` (or the fallback match). Any error → `nil`.

### 3.5 `close(_ key:)`

1. `let listing = await inspect(pid: key.pid)`. This refreshes the cache and gets the latest title and URL. `wasListed = listing` contains `key.windowID`.
2. `element = cache[key]`. If it is nil → return `.unreachable`. If the listing was `.notTrusted` → return `.notTrusted`.
3. Read `kAXCloseButtonAttribute` from `element`:
   - missing → `.noCloseButton`.
   - `.invalidUIElement` → drop the cache entry, return `.unreachable`.
4. `AXUIElementPerformAction(button, kAXPressAction)`:
   - `.success` → `.pressed(latest: listing[key.windowID], wasListed:)`.
   - `.invalidUIElement` → drop the entry, return `.unreachable`.
   - `.apiDisabled` → `.notTrusted`.
   - other → `.failed(code:)`.

This never presses anything other than the close button, and never interacts with dialogs (functional spec §5.2).

Why `wasListed` matters: if AX delivers a press to a kept element of a window on another Space, and the window does not close, the engine must treat this as "unreachable, retry later" and not as "the app declined". See engine.md §4 (verification).

## 4. `FrontmostFocusObserver` (`@MainActor final class`; implements `FocusObserving`)

It holds **one** `AXObserver`, attached only to the frontmost app. This avoids the AltTab problems (focus events from background apps, and many registrations to manage).

- `observe(pid:)`:
  - If `pid` equals the current pid → no-op.
  - Otherwise remove the old observer: `CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)`, then release it.
  - If `pid == nil` → stop.
  - Otherwise `AXObserverCreate(pid, callback, &observer)`. On the app element, add `kAXFocusedWindowChangedNotification`, `kAXMainWindowChangedNotification`, and `kAXWindowCreatedNotification`, with `refcon = Unmanaged.passUnretained(self)`. Add the run loop source to the main run loop in `.defaultMode`.
- **Registration retry:** if `AXObserverAddNotification` returns `.cannotComplete` or `.notImplemented` (the app is still launching), retry the whole registration after 0.5, 1, 2, and 4 s, only while `pid` is still the target. `.notificationUnsupported` for one notification is accepted (the others stay). After the last retry, log and rely on the 60 s reconciliation (engine.md §5).
- **Callback:** a `@convention(c)` function. It takes `Date()` **first**, then yields `FocusSignal(pid:, kind:, at:)` into the stream:
  - focused-window-changed and main-window-changed → `.focusMayHaveChanged`.
  - window-created → `.windowCreated`.

  It makes no AX calls on the main thread. `AppCore` asks `AXWindowService.focusedWindowID(pid:)` off-main.
- `signals()` returns one `AsyncStream` (`bufferingPolicy: .bufferingNewest(64)`), created in `init`.

## 5. `LiveWorkspaceEvents` (implements `WorkspaceEventSource`)

It observes `NSWorkspace.shared.notificationCenter` and maps to `WorkspaceEvent`:

| Notification | Event |
|---|---|
| `didActivateApplicationNotification` | `.appActivated(app)` (the app from `NSWorkspace.applicationUserInfoKey`) |
| `didDeactivateApplicationNotification` | `.appDeactivated(pid:)` |
| `didLaunchApplicationNotification` | `.appLaunched(app)` |
| `didTerminateApplicationNotification` | `.appTerminated(pid:)` |
| `activeSpaceDidChangeNotification` | `.activeSpaceChanged` |
| `screensDidSleepNotification` / `screensDidWakeNotification` | `.displaysSlept` / `.displaysWoke` |
| `sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` | `.sessionResigned` / `.sessionBecameActive` |
| `NSApplication.didBecomeActiveNotification` (default center) | `.ownAppBecameActive` |

- `frontmostApp()` returns `NSWorkspace.shared.frontmostApplication` mapped to `ObservedApp` (nil if it has no bundle ID).
- `areDisplaysAsleep()` returns `CGDisplayIsAsleep(CGMainDisplayID()) != 0`.

## 6. `LiveAccessibilityPermission` (implements `AccessibilityPermissionPort`)

- `isTrusted()` → `AXIsProcessTrusted()`.
- `requestPrompt()` → `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)`, then `openSystemSettings()`.
- `openSystemSettings()` → open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- `changes()` → `DistributedNotificationCenter.default()` observer for `"com.apple.accessibility.api"`. It yields after 0.25 s (the trust state can lag the notification). `AppCore` re-checks at yield time and again after 1.5 s.

This is not a documented notification. It is verified by the ManualTestApp (`sb_permission_notification`). The fallback, a re-check on `.ownAppBecameActive`, is always active. The user comes back to Squeegee after they change System Settings, so the re-check covers onboarding even without the notification.

## 7. Other live ports

- **`LiveLoginItem`:** `SMAppService.mainApp`. `isEnabled()` is `status == .enabled`. `setEnabled` calls `register()` / `unregister()` (errors are rethrown).
- **`LiveInstalledAppScanner`:**
  - Enumerate `.app` bundles in `/Applications` (depth 2, which covers `/Applications/Utilities` and vendor folders), `/System/Applications` (depth 2), and `~/Applications` (depth 2).
  - Add the `bundleURL` of the running apps.
  - For each: `Bundle(url:)?.bundleIdentifier`, and the name from `FileManager.default.displayName(atPath:)` with `.app` removed.
  - Deduplicate by bundle ID; the first found wins, in the order `/Applications`, `/System/Applications`, `~/Applications`, running.
  - It runs off-main.
- **`LiveAppOpener`:**
  - `open(documentURL:withBundleID:)` → `NSWorkspace.shared.open([url], withApplicationAt: appURL(for: bundleID), configuration: .init())`. `configuration.activates = true`. (Finder exposes no document URL, so Finder closures are never reopened this way.)
  - `launch(bundleID:)` → `openApplication(at:configuration:)`.
  - `fileExists` → `FileManager.default.fileExists(atPath: url.path)`.
- **`LiveAppScheduler`:** implements `AppScheduler` with `DispatchSource` timers on the main queue (details in engine.md §6.2).
- **`LiveAppTerminator`:** `NSRunningApplication(processIdentifier:)?.terminate() ?? false`. It never calls `forceTerminate()`.

## 8. Energy budget (steady state, displays awake)

| Work | Frequency | Cost |
|---|---|---|
| CG scan | every 60 s (+ app events) | about 3 ms |
| AX focused-window query | per focus change (event) + every 60 s | < 1 ms per call |
| AX inspect (one app) | on app deactivate, window created, Space change, new unknown windows | about 1–10 ms per app |
| Deadline timer | once per deadline | negligible |

While the displays sleep, only the deadline timer and a close's verification scans run. The target is idle CPU of about 0.0% and "Low" energy impact in Activity Monitor. The perf benchmark (`make bench`) verifies this.

## 9. Unit tests (SystemBridge)

Only pure helpers are unit-tested here: `CGWindowLister.parse` (every filter rule, missing keys, the excluded list, and the own pid), document/URL mapping, AX error → result mapping (a table function `static func map(_ error: AXError) -> InspectionResult?`), and the fallback bounds matching (unique / none / ambiguous). Everything else is covered by the ManualTestApp.
