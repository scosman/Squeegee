import AppKit
import Presentation

/// Converts a `MenuContent` value tree into an `NSMenu`.
///
/// Pure rendering: no system calls. App icons come from the caller's `icon`
/// lookup, which must not block.
/// Each `NSMenuItem` stores its `MenuAction?` in `representedObject`
/// so the caller can dispatch it from a single action selector.
public enum MenuRenderer {
    /// An item that shows an app icon which was not ready when the menu was built.
    public struct PendingIcon {
        public let item: NSMenuItem
        public let bundleID: String
    }

    /// Populates the given menu in place with items from the content tree.
    /// Removes all existing items first, then adds sections, headers, and
    /// items directly — no intermediate NSMenu, no item-move between menus.
    ///
    /// `icon` returns the ready icon for a bundle ID, or nil when it is not
    /// loaded. Returns the items that got no icon, so the caller can set the
    /// image when the icon loads.
    @discardableResult
    public static func populate(
        _ menu: NSMenu,
        with content: MenuContent,
        target: AnyObject,
        action: Selector,
        icon: (String) -> NSImage? = { _ in nil }
    ) -> [PendingIcon] {
        menu.removeAllItems()
        var pending: [PendingIcon] = []

        for (sectionIndex, section) in content.sections.enumerated() {
            if sectionIndex > 0 {
                menu.addItem(.separator())
            }

            if let header = section.header {
                menu.addItem(.sectionHeader(title: header))
            }

            for item in section.items {
                let nsItem = makeNSMenuItem(
                    from: item, target: target, action: action, icon: icon, pending: &pending
                )
                menu.addItem(nsItem)
            }
        }
        return pending
    }

    /// Renders the given content into a new NSMenu. Menu items that carry an
    /// action target `target` with the given `action` selector.
    public static func render(
        _ content: MenuContent,
        target: AnyObject,
        action: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        populate(menu, with: content, target: target, action: action)
        return menu
    }

    // MARK: - Private

    private static func makeNSMenuItem(
        from item: MenuItem,
        target: AnyObject,
        action: Selector,
        icon: (String) -> NSImage?,
        pending: inout [PendingIcon]
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
            if let image = icon(bundleID) {
                nsItem.image = image
            } else {
                pending.append(PendingIcon(item: nsItem, bundleID: bundleID))
            }
        }

        // Submenu
        if let children = item.submenu {
            let subMenu = NSMenu()
            subMenu.autoenablesItems = false
            for child in children {
                let childItem = makeNSMenuItem(
                    from: child, target: target, action: action, icon: icon, pending: &pending
                )
                subMenu.addItem(childItem)
            }
            nsItem.submenu = subMenu
        }

        return nsItem
    }
}
