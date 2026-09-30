import AppKit
import Presentation

/// Converts a `MenuContent` value tree into an `NSMenu`.
///
/// Pure rendering: no system calls beyond NSWorkspace icon lookup.
/// Each `NSMenuItem` stores its `MenuAction?` in `representedObject`
/// so the caller can dispatch it from a single action selector.
public enum MenuRenderer {
    /// Renders the given content into an NSMenu. Menu items that carry an
    /// action target `target` with the given `action` selector.
    public static func render(
        _ content: MenuContent,
        target: AnyObject,
        action: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for (sectionIndex, section) in content.sections.enumerated() {
            // Separator between sections (not before the first one)
            if sectionIndex > 0 {
                menu.addItem(.separator())
            }

            // Section header
            if let header = section.header {
                menu.addItem(.sectionHeader(title: header))
            }

            // Items
            for item in section.items {
                let nsItem = makeNSMenuItem(
                    from: item, target: target, action: action
                )
                menu.addItem(nsItem)
            }
        }

        return menu
    }

    // MARK: - Private

    private static func makeNSMenuItem(
        from item: MenuItem,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let keyEquiv = item.keyEquivalent ?? ""
        let nsItem = NSMenuItem(
            title: item.title,
            action: item.action != nil ? action : nil,
            keyEquivalent: keyEquiv
        )
        nsItem.target = item.action != nil ? target : nil
        nsItem.representedObject = item.action
        nsItem.isEnabled = item.isEnabled
        nsItem.state = item.isChecked ? .on : .off

        if let subtitle = item.subtitle {
            nsItem.subtitle = subtitle
        }

        if let tooltip = item.tooltip {
            nsItem.toolTip = tooltip
        }

        if let bundleID = item.bundleID {
            nsItem.image = appIcon(bundleID: bundleID, size: 16)
        }

        // Submenu
        if let children = item.submenu {
            let subMenu = NSMenu()
            subMenu.autoenablesItems = false
            for child in children {
                let childItem = makeNSMenuItem(
                    from: child, target: target, action: action
                )
                subMenu.addItem(childItem)
            }
            nsItem.submenu = subMenu
        }

        return nsItem
    }

    /// Looks up an app icon by bundle ID at the given point size.
    private static func appIcon(bundleID: String, size: CGFloat) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
