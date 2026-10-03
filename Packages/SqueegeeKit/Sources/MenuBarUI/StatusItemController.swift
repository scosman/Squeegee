import AppCore
import AppKit
import Engine
import OSLog
import Presentation

private let logger = Logger(subsystem: "net.scosman.squeegee", category: "MenuBarUI")

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

    // MARK: - Icon configuration (ui_design section 3.1)

    /// Menu bar icon height in points. macOS status bar is 22pt; 18pt leaves 2pt padding per side.
    private static let menuBarIconSize: CGFloat = 18
    private static let pausedIcon = "pause.rectangle"
    private static let permissionMissingIcon = "exclamationmark.triangle"

    // MARK: - Init

    public init(core: AppCore) {
        self.core = core
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        logger.info("StatusItemController initialized")

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
    /// Items are added directly into the status menu — no intermediate NSMenu,
    /// which avoids menu-tracking session conflicts from moving items between menus.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let content = core.menuContent()
        MenuRenderer.populate(
            menu,
            with: content,
            target: self,
            action: #selector(menuItemClicked(_:))
        )
    }

    // MARK: - Action dispatch

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        dispatchAction(action)
    }

    private func dispatchAction(_ action: MenuAction) {
        // Log the action kind only — ClosureValue may contain window titles (privacy: .private).
        logger.info("Menu action dispatched: \(action.logLabel, privacy: .public)")
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
        let image: NSImage? = switch state {
        case .normal: Self.squeegeeImage()
        case .paused: NSImage(systemSymbolName: Self.pausedIcon, accessibilityDescription: "Squeegee – Paused")
        case .permissionMissing:
            NSImage(
                systemSymbolName: Self.permissionMissingIcon,
                accessibilityDescription: "Squeegee – Permission Required"
            )
        }

        if let button = statusItem.button {
            image?.isTemplate = true
            button.image = image
        }
    }

    /// Loads the squeegee icon from the module asset catalog, sized for the menu bar.
    private static func squeegeeImage() -> NSImage? {
        guard let image = Bundle.module.image(forResource: "squeegee") else {
            logger.error("Failed to load squeegee icon from asset catalog")
            return NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Squeegee")
        }
        image.size = NSSize(width: menuBarIconSize, height: menuBarIconSize)
        image.accessibilityDescription = "Squeegee"
        return image
    }
}
