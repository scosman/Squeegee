import AppKit
import Engine
import MenuBarUI
import Presentation
import Testing

/// A dummy target for NSMenuItem actions.
@MainActor
private final class ActionTarget: NSObject {
    @objc func handleAction(_: NSMenuItem) {}
}

@Suite("MenuRenderer")
@MainActor
struct MenuRendererTests {
    private let target = ActionTarget()
    private var action: Selector {
        #selector(ActionTarget.handleAction(_:))
    }

    // MARK: - Helpers

    private func makeContent(sections: [MenuSection]) -> MenuContent {
        MenuContent(sections: sections)
    }

    /// Collects all non-separator items from an NSMenu (flattened, no submenus).
    private func visibleItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isSeparatorItem }
    }

    // MARK: - Basic rendering

    @Test func rendererBasicMenu() {
        let content = makeContent(sections: [
            MenuSection(header: "Up Next", items: [
                MenuItem(
                    title: "Downloads",
                    subtitle: "Finder \u{00B7} in 2h 10m",
                    bundleID: "com.apple.finder",
                    action: .openRule(bundleID: "com.apple.finder", source: .app)
                )
            ]),
            MenuSection(header: "Recently Closed", items: [
                MenuItem(title: "Nothing closed yet", isEnabled: false)
            ]),
            MenuSection(items: [
                MenuItem(title: "Pause", submenu: [
                    MenuItem(title: "For 1 Hour", action: .pauseOneHour),
                    MenuItem(title: "Until Tomorrow", action: .pauseUntilTomorrow),
                    MenuItem(title: "Until Resumed", action: .pauseUntilResumed)
                ]),
                MenuItem(title: "Settings\u{2026}", action: .openSettings, keyEquivalent: ","),
                MenuItem(title: "Quit WindowCleaner", action: .quit, keyEquivalent: "q")
            ])
        ])

        let menu = MenuRenderer.render(content, target: target, action: action)
        // 3 sections means 2 separators. Items: header+1 | sep | header+1 | sep | 3
        // Section 1: header + Downloads = 2
        // Separator
        // Section 2: header + "Nothing closed yet" = 2
        // Separator
        // Section 3: Pause, Settings, Quit = 3
        #expect(menu.items.count == 9)
    }

    // MARK: - Section headers

    @Test func rendererSectionHeaders() {
        let content = makeContent(sections: [
            MenuSection(header: "Up Next", items: [
                MenuItem(title: "Test", isEnabled: false)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        // First visible item should be the section header
        #expect(items[0].title == "Up Next")
        // Section header has no action (not interactive)
        #expect(items[0].action == nil)
    }

    // MARK: - Subtitles

    @Test func rendererSubtitles() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Downloads", subtitle: "Finder \u{00B7} in 2h")
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].subtitle == "Finder \u{00B7} in 2h")
    }

    @Test func rendererNoSubtitle() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Resume", action: .resume)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].subtitle == nil)
    }

    // MARK: - Submenus

    @Test func rendererSubmenu() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Pause", submenu: [
                    MenuItem(title: "For 1 Hour", action: .pauseOneHour),
                    MenuItem(title: "Until Tomorrow", action: .pauseUntilTomorrow)
                ])
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].title == "Pause")
        let subMenu = items[0].submenu
        #expect(subMenu != nil)
        #expect(subMenu?.items.count == 2)
        #expect(subMenu?.items[0].title == "For 1 Hour")
        #expect(subMenu?.items[1].title == "Until Tomorrow")
    }

    // MARK: - Disabled items

    @Test func rendererDisabledItems() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Nothing closed yet", isEnabled: false)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].isEnabled == false)
    }

    // MARK: - Tooltips

    @Test func rendererTooltips() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(
                    title: "Report.pdf",
                    action: .reopen(ClosureValue(
                        bundleID: "com.apple.Preview",
                        appName: "Preview",
                        windowTitle: "Report.pdf",
                        documentURL: URL(string: "file:///Users/test/Report.pdf"),
                        kind: .windowClosed,
                        closedAt: Date()
                    )),
                    tooltip: "Reopen Report.pdf in Preview"
                )
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].toolTip == "Reopen Report.pdf in Preview")
    }

    @Test func rendererNoTooltip() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Resume", action: .resume)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].toolTip == nil)
    }

    // MARK: - Key equivalents

    @Test func rendererKeyEquivalents() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Settings\u{2026}", action: .openSettings, keyEquivalent: ","),
                MenuItem(title: "Quit WindowCleaner", action: .quit, keyEquivalent: "q")
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].keyEquivalent == ",")
        #expect(items[1].keyEquivalent == "q")
    }

    @Test func rendererNoKeyEquivalent() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Resume", action: .resume)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].keyEquivalent == "")
    }

    // MARK: - Checkmarks

    @Test func rendererCheckmarks() throws {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Pause", submenu: [
                    MenuItem(title: "For 1 Hour", action: .pauseOneHour, isChecked: true),
                    MenuItem(title: "Until Tomorrow", action: .pauseUntilTomorrow, isChecked: false)
                ])
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let pauseItem = visibleItems(menu)[0]
        let sub = try #require(pauseItem.submenu?.items)
        #expect(sub[0].state == .on)
        #expect(sub[1].state == .off)
    }

    // MARK: - Actions stored in representedObject

    @Test func rendererActions() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Resume", action: .resume),
                MenuItem(title: "Settings\u{2026}", action: .openSettings, keyEquivalent: ",")
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        let action0 = items[0].representedObject as? MenuAction
        #expect(action0 == .resume)
        let action1 = items[1].representedObject as? MenuAction
        #expect(action1 == .openSettings)
    }

    @Test func rendererDisabledItemHasNoAction() {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Nothing closed yet", isEnabled: false)
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let items = visibleItems(menu)
        #expect(items[0].action == nil)
        #expect(items[0].target == nil)
    }

    // MARK: - Separators between sections

    @Test func rendererSeparatorsBetweenSections() {
        let content = makeContent(sections: [
            MenuSection(items: [MenuItem(title: "A")]),
            MenuSection(items: [MenuItem(title: "B")]),
            MenuSection(items: [MenuItem(title: "C")])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        // A | sep | B | sep | C = 5
        #expect(menu.items.count == 5)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[3].isSeparatorItem)
    }

    // MARK: - Submenu action targets

    @Test func rendererSubmenuActionsHaveTarget() throws {
        let content = makeContent(sections: [
            MenuSection(items: [
                MenuItem(title: "Pause", submenu: [
                    MenuItem(title: "For 1 Hour", action: .pauseOneHour)
                ])
            ])
        ])
        let menu = MenuRenderer.render(content, target: target, action: action)
        let pauseItem = visibleItems(menu)[0]
        let child = try #require(pauseItem.submenu?.items[0])
        #expect(child.target != nil)
        let childAction = child.representedObject as? MenuAction
        #expect(childAction == .pauseOneHour)
    }
}
