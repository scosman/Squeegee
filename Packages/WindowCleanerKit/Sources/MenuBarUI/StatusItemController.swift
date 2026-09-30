import AppCore
import AppKit
import Engine
import OSLog
import Presentation

private let logger = Logger(subsystem: "net.scosman.windowcleaner", category: "MenuBarUI")

/// Owns the NSStatusItem and renders the menu bar menu.
///
/// Uses `NSMenuDelegate.menuNeedsUpdate` to build the menu on demand
/// from `AppCore.menuContent()`. The icon image tracks
/// `core.menuBarIconState`, and visibility tracks
/// `core.store.settings.showMenuBarIcon`.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let core: AppCore
    private let statusItem: NSStatusItem

    // Observation tokens for icon state and visibility
    private var iconObservation: (any Sendable)?
    private var visibilityObservation: (any Sendable)?

    // MARK: - Icon SF Symbol names (ui_design section 3.1)

    private static let normalIcon = "macwindow.on.rectangle"
    private static let pausedIcon = "pause.rectangle"
    private static let permissionMissingIcon = "exclamationmark.triangle"

    // MARK: - Init

    public init(core: AppCore) {
        self.core = core
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // Configure the menu
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        // Set initial icon and visibility
        updateIcon(core.menuBarIconState)
        statusItem.isVisible = core.store.settings.showMenuBarIcon

        // Start observing changes
        observeIconState()
        observeVisibility()
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the menu each time it opens (ui_design: "built when it opens").
    /// AppKit calls this on the main thread; the @MainActor class provides isolation.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let content = core.menuContent()
        let rendered = MenuRenderer.render(
            content,
            target: self,
            action: #selector(menuItemClicked(_:))
        )

        menu.removeAllItems()
        for item in rendered.items {
            rendered.removeItem(item)
            menu.addItem(item)
        }
    }

    // MARK: - Action dispatch

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        dispatchAction(action)
    }

    private func dispatchAction(_ action: MenuAction) {
        switch action {
        case .openAccessibilitySettings:
            core.openAccessibilitySettings()

        case .resume:
            core.resume()

        case let .openRule(bundleID, source):
            let selection: SettingsSelection = switch source {
            case .app: .appRule(bundleID: bundleID)
            case .global: .globalRule
            }
            core.open(selection)

        case let .reopen(closure):
            performReopen(closure)

        case .pauseOneHour, .pauseUntilTomorrow, .pauseUntilResumed:
            dispatchPause(action)

        case .openSettings:
            core.open(.general)

        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func dispatchPause(_ action: MenuAction) {
        switch action {
        case .pauseOneHour: core.pause(.oneHour)
        case .pauseUntilTomorrow: core.pause(.untilTomorrow)
        case .pauseUntilResumed: core.pause(.untilResumed)
        default: break
        }
    }

    private func performReopen(_ closure: ClosureValue) {
        Task { @MainActor in
            do {
                try await core.reopen(closure)
            } catch {
                logger.error("Reopen failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Observation

    private func observeIconState() {
        withObservationTracking {
            _ = core.menuBarIconState
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateIcon(self.core.menuBarIconState)
                self.observeIconState()
            }
        }
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = core.store.settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem.isVisible = self.core.store.settings.showMenuBarIcon
                self.observeVisibility()
            }
        }
    }

    // MARK: - Icon

    private func updateIcon(_ state: MenuBarIconState) {
        let symbolName: String = switch state {
        case .normal: Self.normalIcon
        case .paused: Self.pausedIcon
        case .permissionMissing: Self.permissionMissingIcon
        }

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WindowCleaner")
            image?.isTemplate = true
            button.image = image
        }
    }
}
