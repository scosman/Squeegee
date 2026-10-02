import AppCore
import Engine
import Persistence
import Presentation
import SharedUI
import SwiftUI

/// The rule editor page for an app rule or the global rule (ui_design section 4.3).
struct RulePage: View {
    let core: AppCore
    let bundleID: String?

    var body: some View {
        if let id = bundleID, let record = core.store.appRule(bundleID: id) {
            AppRulePageContent(core: core, record: record, bundleID: id)
        } else if bundleID == nil {
            GlobalRulePageContent(core: core)
        } else {
            // Rule was removed; fall back to general
            GeneralPage(core: core)
        }
    }
}

// MARK: - Global rule page

private struct GlobalRulePageContent: View {
    let core: AppCore

    var body: some View {
        Form {
            PermissionBanner(core: core)

            headerSection
            enabledSection
            closeAfterSection
            measureFromSection
            OpenWindowsList(core: core, selection: .globalRule)
        }
        .formStyle(.grouped)
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "square.stack")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All other apps")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Applies to every app that doesn\u{2019}t have its own rule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var enabledSection: some View {
        @Bindable var settings = core.store.settings
        return Section {
            Toggle("Close windows automatically", isOn: $settings.globalIsEnabled)
        }
    }

    private var closeAfterSection: some View {
        let settings = core.store.settings
        return CloseAfterSection(
            seconds: Binding(
                get: { settings.globalCloseAfterSeconds },
                set: { settings.globalCloseAfterSeconds = $0 }
            ),
            isEnabled: settings.globalIsEnabled
        )
    }

    private var measureFromSection: some View {
        @Bindable var settings = core.store.settings
        return MeasureFromSection(rawValue: $settings.globalMeasureFromRaw, isEnabled: settings.globalIsEnabled)
    }
}

// MARK: - App rule page

private struct AppRulePageContent: View {
    let core: AppCore
    @Bindable var record: AppRuleRecord
    let bundleID: String
    @State private var showRemoveConfirmation = false

    var body: some View {
        Form {
            PermissionBanner(core: core)

            headerSection
            enabledSection
            closeAfterSection
            measureFromSection
            if bundleID != "com.apple.finder" {
                quitPolicySection
            }
            OpenWindowsList(core: core, selection: .appRule(bundleID: bundleID))
            removeSection
        }
        .formStyle(.grouped)
        // Notify the Store when any app-rule property changes so that the
        // ruleVersion counter bumps and AppCore's withObservationTracking
        // reliably fires its onChange (see Store.notifyRuleChanged() doc).
        .onChange(of: record.isEnabled) { _, _ in core.store.notifyRuleChanged() }
        .onChange(of: record.closeAfterSeconds) { _, _ in core.store.notifyRuleChanged() }
        .onChange(of: record.measureFromRaw) { _, _ in core.store.notifyRuleChanged() }
        .onChange(of: record.quitPolicyRaw) { _, _ in core.store.notifyRuleChanged() }
        .sheet(isPresented: $showRemoveConfirmation) {
            RemoveRuleSheet(
                appName: record.appName,
                onRemove: {
                    showRemoveConfirmation = false
                    core.store.removeAppRule(bundleID: bundleID)
                    core.store.save()
                    core.open(.general)
                },
                onCancel: {
                    showRemoveConfirmation = false
                }
            )
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                AppIconView(bundleID: bundleID, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.appName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var enabledSection: some View {
        Section {
            Toggle("Close windows automatically", isOn: $record.isEnabled)
        }
    }

    private var closeAfterSection: some View {
        CloseAfterSection(
            seconds: $record.closeAfterSeconds,
            isEnabled: record.isEnabled
        )
    }

    private var measureFromSection: some View {
        MeasureFromSection(rawValue: $record.measureFromRaw, isEnabled: record.isEnabled)
    }

    private var quitPolicySection: some View {
        QuitPolicySection(rawValue: $record.quitPolicyRaw, isEnabled: record.isEnabled)
    }

    private var removeSection: some View {
        Section {
            Button("Remove Rule", role: .destructive) {
                showRemoveConfirmation = true
            }
        }
    }
}

// MARK: - Shared sections

/// Close-after picker with preset durations and a custom option.
/// Uses a separate `isCustom` state to avoid writing sentinel values to the
/// model. All writes to `seconds` are clamped to `Rule.closeAfterRange`.
private struct CloseAfterSection: View {
    @Binding var seconds: Int
    let isEnabled: Bool

    /// Tracks whether the custom row is visible. Initialized from whether
    /// the current value is a preset.
    @State private var isCustom: Bool

    init(seconds: Binding<Int>, isEnabled: Bool) {
        _seconds = seconds
        self.isEnabled = isEnabled
        _isCustom = State(initialValue: !DurationClamping.isPreset(seconds.wrappedValue))
    }

    /// A clamped binding that ensures no out-of-range value reaches the model.
    private var clampedSeconds: Binding<Int> {
        Binding(
            get: { seconds },
            set: { seconds = DurationClamping.clamp($0) }
        )
    }

    /// The picker selection: preset values select directly; "Custom..." is
    /// handled by a separate button-like action so no sentinel is written.
    private var pickerSelection: Binding<Int> {
        Binding(
            get: { isCustom ? 0 : seconds },
            set: { newValue in
                if newValue == 0 {
                    // "Custom..." selected — keep the current value, show custom row
                    isCustom = true
                } else {
                    isCustom = false
                    seconds = DurationClamping.clamp(newValue)
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Close after", selection: pickerSelection) {
                Text("30 minutes").tag(1800)
                Text("1 hour").tag(3600)
                Text("2 hours").tag(7200)
                Text("4 hours").tag(14400)
                Text("6 hours").tag(21600)
                Text("12 hours").tag(43200)
                Text("1 day").tag(86400)
                Text("2 days").tag(172_800)
                Text("1 week").tag(604_800)
                Divider()
                Text("Custom\u{2026}").tag(0)
            }
            .disabled(!isEnabled)

            if isCustom {
                customRow
            }
        }
    }

    private var customRow: some View {
        let clamped = DurationClamping.clamp(seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return HStack {
            Text("Duration")
            Spacer()
            Stepper(
                "\(hours)h \(minutes)m",
                value: clampedSeconds,
                in: Int(Rule.closeAfterRange.lowerBound) ... Int(Rule.closeAfterRange.upperBound),
                step: 300
            )
            .disabled(!isEnabled)
        }
    }
}

/// Measure-from picker with subtitled options in the dropdown.
private struct MeasureFromSection: View {
    @Binding var rawValue: String
    let isEnabled: Bool

    private static let options: [PopUpOption] = [
        PopUpOption(
            value: "lastActive",
            title: "Last active",
            subtitle: "Time since you last used the window (focused for 5 seconds or more)."
        ),
        PopUpOption(
            value: "opened",
            title: "Opened",
            subtitle: "Time since the window opened, or since Squeegee first saw it."
        )
    ]

    var body: some View {
        Section {
            LabeledContent("Measure from") {
                SubtitledPopUpButton(
                    selection: $rawValue,
                    options: Self.options,
                    isEnabled: isEnabled
                )
                .frame(width: 200)
            }
        }
    }
}

/// Quit-policy picker with subtitled options in the dropdown.
/// Hidden for the global rule and Finder.
private struct QuitPolicySection: View {
    @Binding var rawValue: String
    let isEnabled: Bool

    private static let options: [PopUpOption] = [
        PopUpOption(
            value: "never",
            title: "Keep app running",
            subtitle: "The app keeps running after its windows are closed."
        ),
        PopUpOption(
            value: "ifClosedBySqueegee",
            title: "Quit if Squeegee closed it",
            subtitle: "Quits the app after Squeegee closes its last window."
        ),
        PopUpOption(
            value: "always",
            title: "Always quit app",
            subtitle: "Quits the app when it has no windows, even if you closed them yourself."
        )
    ]

    var body: some View {
        Section {
            LabeledContent("When the last window closes") {
                SubtitledPopUpButton(
                    selection: $rawValue,
                    options: Self.options,
                    isEnabled: isEnabled
                )
                .frame(width: 260)
            }
        }
    }
}
