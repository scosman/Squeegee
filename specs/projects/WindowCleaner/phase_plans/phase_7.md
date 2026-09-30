---
status: complete
---

# Phase 7: Menu Bar

## Overview

Build the MenuBarUI module: StatusItemController (owns the NSStatusItem, drives icon state, show/hide), MenuRenderer (converts MenuContent value tree to NSMenu), and wire them into the AppDelegate. Also restructure the MenuContent model and MenuContentBuilder to express the "Pause" submenu explicitly in the value tree (instead of flat items that the renderer must know to group).

## Steps

1. **Add submenu support to MenuContent (Presentation).** Add a `submenu: [MenuItem]?` field to `MenuItem`. When non-nil, the renderer creates a submenu. Restructure `MenuContentBuilder.buildFooterSection` to emit a single "Pause" `MenuItem` with its three options in `submenu`, plus the Settings and Quit items. Add a `hasKeyEquivalent: String?` field for the Cmd+, and Cmd+Q shortcuts.

2. **Update MenuContentBuilder tests (PresentationTests).** Adapt existing footer tests to check the new submenu structure. Add tests: pause submenu item contains three children with correct checkmarks, Settings has key equivalent, Quit has key equivalent.

3. **Implement MenuRenderer (MenuBarUI).** A pure `enum MenuRenderer` with `static func render(_ content: MenuContent, target: AnyObject, action: Selector) -> NSMenu`. Maps sections to NSMenu items: section headers via `NSMenuItem.sectionHeader(title:)`, separators between sections, regular items with title/subtitle/enabled/tooltip/checked, app icons (via NSWorkspace icon for bundleID at 16pt), submenus, and key equivalents. Each NSMenuItem stores its `MenuAction?` in `representedObject`.

4. **Implement StatusItemController (MenuBarUI).** `@MainActor public final class StatusItemController: NSObject, NSMenuDelegate`. Owns an `NSStatusItem`, references `AppCore`. On `init(core:)`, creates the status item, sets the template image, installs itself as the menu delegate. Implements `menuNeedsUpdate(_:)` to call `core.menuContent()` and render. Implements the action selector to dispatch `MenuAction` to `AppCore` calls. Observes `core.menuBarIconState` to update the icon image, and `core.store.settings.showMenuBarIcon` to toggle `statusItem.isVisible`. The three SF Symbol image names follow ui_design section 3.1.

5. **Wire StatusItemController into AppDelegate.** Add a `private var statusItemController: StatusItemController?` property. Create it after AppCore is set up in `applicationDidFinishLaunching`. No other changes to the App target.

6. **Add MenuBarUI test target (Package.swift, MenuBarUITests).** Add a `MenuBarUITests` test target that depends on `MenuBarUI` and `Presentation`. Write MenuRenderer tests: render a full MenuContent and assert NSMenu item count, titles, subtitles, enabled state, tooltips, section headers, key equivalents, submenus, and checkmarks.

## Tests

- `footerPauseSubmenu`: the footer section has a "Pause" item with a submenu containing three options; Settings and Quit are sibling items.
- `pauseSubmenuCheckmarks`: when paused, the correct submenu child has `isChecked == true`.
- `rendererBasicMenu`: render a MenuContent with Up Next and Recently Closed; assert NSMenu item structure.
- `rendererSectionHeaders`: section headers render as `NSMenuItem.sectionHeader`.
- `rendererSubtitles`: items with subtitles have `NSMenuItem.subtitle` set.
- `rendererSubmenu`: a MenuItem with submenu children produces an NSMenuItem with a submenu NSMenu.
- `rendererDisabledItems`: disabled MenuItems produce disabled NSMenuItems.
- `rendererTooltips`: tooltip text propagates to NSMenuItem.toolTip.
- `rendererKeyEquivalents`: Settings gets Cmd+, and Quit gets Cmd+Q.
- `rendererCheckmarks`: checked items have `NSMenuItem.state == .on`.
- `rendererActions`: each NSMenuItem stores the correct MenuAction in representedObject.
