import AppCore
import Persistence
import Presentation
import SwiftUI

/// The General settings page: status, startup, menu bar, and about
/// (ui_design section 4.2).
struct GeneralPage: View {
    let core: AppCore
    @State private var loginItemError: String?

    var body: some View {
        Form {
            PermissionBanner(core: core)

            statusSection
            startupSection
            menuBarSection
            aboutSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            // Accessibility Permission
            HStack {
                Text("Accessibility Permission")
                Spacer()
                if core.permission == .granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    HStack(spacing: 8) {
                        Text("Not granted")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Button("Open System Settings") {
                            core.openAccessibilitySettings()
                        }
                    }
                }
            }

            // Pause State
            HStack {
                Text("Pause State")
                Spacer()
                if core.isPaused {
                    HStack(spacing: 8) {
                        if let until = core.pausedUntil {
                            Text(pauseText(until: until))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        } else {
                            Text("Paused")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        Button("Resume") {
                            core.resume()
                        }
                    }
                } else {
                    Menu("Pause") {
                        Button("For 1 Hour") {
                            core.pause(.oneHour)
                        }
                        Button("Until Tomorrow") {
                            core.pause(.untilTomorrow)
                        }
                        Button("Until Resumed") {
                            core.pause(.untilResumed)
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at login", isOn: Binding(
                get: { core.launchAtLogin },
                set: { newValue in
                    do {
                        try core.setLaunchAtLogin(newValue)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                    }
                }
            ))
            if let error = loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        Section {
            Toggle("Show menu bar icon", isOn: Binding(
                get: { core.store.settings.showMenuBarIcon },
                set: { newValue in
                    core.store.settings.showMenuBarIcon = newValue
                    core.store.save()
                }
            ))
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("When the icon is hidden, open WindowCleaner again from Finder or Spotlight to show this window.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(versionString)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private func pauseText(until: Date) -> String {
        TimeFormatting.formatPausedUntil(date: until, now: Date())
    }
}
