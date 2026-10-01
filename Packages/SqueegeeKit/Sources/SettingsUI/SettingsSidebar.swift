import AppCore
import Engine
import Persistence
import Presentation
import SharedUI
import SwiftUI

/// The sidebar of the Settings NavigationSplitView (ui_design section 4.1).
struct SettingsSidebar: View {
    let core: AppCore
    @Binding var selection: SettingsSelection?
    @State private var showSuggestions = false
    @State private var confirmingRemoval: String?

    var body: some View {
        List(selection: $selection) {
            // General
            Label("General", systemImage: "gearshape")
                .tag(SettingsSelection.general)

            Section("Rules") {
                // All other apps (global rule)
                globalRuleRow

                // Per-app rules
                let rules = core.store.appRules()
                ForEach(rules, id: \.bundleID) { rule in
                    appRuleRow(rule)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            // Delete key: ask for confirmation before removing the selected app rule.
            requestRemovalConfirmation()
        }
        .sheet(isPresented: $showSuggestions) {
            SuggestionsSheet(core: core, isPresented: $showSuggestions)
        }
        .sheet(isPresented: Binding(
            get: { confirmingRemoval != nil },
            set: { if !$0 { confirmingRemoval = nil } }
        )) {
            RemoveRuleSheet(
                appName: confirmingAppName,
                onRemove: {
                    if let bundleID = confirmingRemoval {
                        core.store.removeAppRule(bundleID: bundleID)
                        core.store.save()
                        selection = .general
                    }
                    confirmingRemoval = nil
                },
                onCancel: {
                    confirmingRemoval = nil
                }
            )
        }
    }

    // MARK: - Global rule row

    private var globalRuleRow: some View {
        let settings = core.store.settings
        let summary = globalRuleSummary(settings)
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("All other apps")
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.stack")
                .frame(width: 20)
        }
        .tag(SettingsSelection.globalRule)
    }

    // MARK: - App rule row

    private func appRuleRow(_ record: AppRuleRecord) -> some View {
        let rule = Rule(
            isEnabled: record.isEnabled,
            closeAfter: TimeInterval(record.closeAfterSeconds),
            measureFrom: MeasureFrom(rawValue: record.measureFromRaw) ?? .lastActive,
            quitPolicy: QuitPolicy(rawValue: record.quitPolicyRaw) ?? .never
        )
        let summary = RuleSummary.sidebarSummary(rule: rule)

        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.appName)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            AppIconView(bundleID: record.bundleID, size: 20)
        }
        .tag(SettingsSelection.appRule(bundleID: record.bundleID))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 4) {
            AddAppMenu(core: core, showSuggestions: $showSuggestions)
                .frame(width: 24, height: 20)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Remove

    /// Requests confirmation before removing the selected app rule.
    private func requestRemovalConfirmation() {
        guard let sel = selection, case let .appRule(bundleID) = sel else { return }
        confirmingRemoval = bundleID
    }

    // MARK: - Helpers

    /// The app name for the removal confirmation sheet.
    private var confirmingAppName: String {
        if let bundleID = confirmingRemoval,
           let record = core.store.appRule(bundleID: bundleID)
        {
            return record.appName
        }
        return "this app"
    }

    private func globalRuleSummary(_ settings: AppSettingsRecord) -> String {
        let rule = Rule(
            isEnabled: settings.globalIsEnabled,
            closeAfter: TimeInterval(settings.globalCloseAfterSeconds),
            measureFrom: MeasureFrom(rawValue: settings.globalMeasureFromRaw) ?? .lastActive,
            quitPolicy: .never
        )
        return RuleSummary.sidebarSummary(rule: rule)
    }
}
