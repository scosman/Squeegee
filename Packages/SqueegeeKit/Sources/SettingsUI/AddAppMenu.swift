import AppCore
import AppKit
import Engine
import SharedUI
import SwiftUI
import UniformTypeIdentifiers

/// The "+" menu button in the sidebar bottom bar. Uses an AppKit NSMenu
/// built on demand so the Running Apps list is always current when the
/// user clicks the button (ui_design section 4.1).
struct AddAppMenu: NSViewRepresentable {
    let core: AppCore
    @Binding var showSuggestions: Bool

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_: NSButton, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: AddAppMenu

        init(parent: AddAppMenu) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            buildMenu(menu)

            // Show the menu below the button
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        }

        private func buildMenu(_ menu: NSMenu) {
            // Running Apps submenu — queried fresh each time
            let runningApps = currentRunningApps()
            let submenu = NSMenu()
            submenu.autoenablesItems = false

            if runningApps.isEmpty {
                let emptyItem = NSMenuItem(title: "No apps without rules", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                submenu.addItem(emptyItem)
            } else {
                for app in runningApps {
                    let item = NSMenuItem(title: app.name, action: #selector(addRunningApp(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = app
                    // Icons load off the main thread; an open menu shows them when ready.
                    let bundleID = app.bundleID
                    Task {
                        item.image = await AppIconView.icon(for: bundleID, pointSize: 16)
                    }
                    submenu.addItem(item)
                }
            }

            let runningItem = NSMenuItem(title: "Running Apps", action: nil, keyEquivalent: "")
            runningItem.submenu = submenu
            menu.addItem(runningItem)

            // Choose App
            let chooseItem = NSMenuItem(
                title: "Choose App\u{2026}",
                action: #selector(chooseApp(_:)),
                keyEquivalent: ""
            )
            chooseItem.target = self
            menu.addItem(chooseItem)

            menu.addItem(.separator())

            // Suggested Rules
            let suggestItem = NSMenuItem(
                title: "Suggested Rules\u{2026}",
                action: #selector(showSuggestions(_:)),
                keyEquivalent: ""
            )
            suggestItem.target = self
            menu.addItem(suggestItem)
        }

        // MARK: - Actions

        @objc private func addRunningApp(_ sender: NSMenuItem) {
            guard let app = sender.representedObject as? RunningAppInfo else { return }
            addApp(bundleID: app.bundleID, name: app.name)
        }

        @objc private func chooseApp(_: NSMenuItem) {
            chooseAppFromPanel()
        }

        @objc private func showSuggestions(_: NSMenuItem) {
            parent.showSuggestions = true
        }

        // MARK: - Running apps

        private func currentRunningApps() -> [RunningAppInfo] {
            let workspace = NSWorkspace.shared
            let existingIDs = Set(parent.core.store.appRules().map(\.bundleID))
            let ownBundleID = Bundle.main.bundleIdentifier ?? ""

            var apps: [RunningAppInfo] = []
            for app in workspace.runningApplications {
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName,
                      app.activationPolicy == .regular,
                      !existingIDs.contains(bundleID),
                      bundleID != ownBundleID
                else { continue }
                apps.append(RunningAppInfo(bundleID: bundleID, name: name))
            }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // MARK: - Choose from picker

        private func chooseAppFromPanel() {
            let panel = NSOpenPanel()
            panel.title = "Choose an Application"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.applicationBundle]

            guard panel.runModal() == .OK, let url = panel.url else { return }

            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier
            else { return }

            let name = FileManager.default.displayName(atPath: url.path)
            addApp(bundleID: bundleID, name: name)
        }

        // MARK: - Add

        private func addApp(bundleID: String, name: String) {
            parent.core.store.addAppRule(bundleID: bundleID, appName: name, rule: .newAppRuleDefault)
            parent.core.store.save()
            parent.core.open(.appRule(bundleID: bundleID))
        }
    }
}

// MARK: - Running app info

/// Lightweight struct identifying a running app without a rule.
@objc private final class RunningAppInfo: NSObject {
    let bundleID: String
    let name: String

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
