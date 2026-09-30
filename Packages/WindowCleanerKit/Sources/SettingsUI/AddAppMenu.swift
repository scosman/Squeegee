import AppCore
import AppKit
import Engine
import SharedUI
import SwiftUI
import UniformTypeIdentifiers

/// The "+" menu button in the sidebar bottom bar: Running Apps submenu,
/// Choose App, and Suggested Rules (ui_design section 4.1).
struct AddAppMenu: View {
    let core: AppCore
    @Binding var showSuggestions: Bool

    @State private var runningApps: [RunningAppInfo] = []
    /// Incremented to force running-apps refresh each time the menu opens.
    @State private var refreshToken = 0

    var body: some View {
        Menu {
            // Running Apps submenu
            Menu("Running Apps") {
                if runningApps.isEmpty {
                    Text("No apps without rules")
                } else {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(app.name) {
                            addApp(bundleID: app.bundleID, name: app.name)
                        }
                    }
                }
            }

            Button("Choose App\u{2026}") {
                chooseAppFromPanel()
            }

            Divider()

            Button("Suggested Rules\u{2026}") {
                showSuggestions = true
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .onAppear {
            refreshRunningApps()
        }
        .onChange(of: refreshToken) {
            refreshRunningApps()
        }
        .simultaneousGesture(TapGesture().onEnded {
            // Refresh each time the menu is about to open
            refreshToken += 1
        })
    }

    // MARK: - Running apps

    private struct RunningAppInfo {
        let bundleID: String
        let name: String
    }

    private func refreshRunningApps() {
        let workspace = NSWorkspace.shared
        let existingIDs = Set(core.store.appRules().map(\.bundleID))
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
        runningApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Add from picker

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
        core.store.addAppRule(bundleID: bundleID, appName: name, rule: .newAppRuleDefault)
        core.store.save()
        core.open(.appRule(bundleID: bundleID))
    }
}
