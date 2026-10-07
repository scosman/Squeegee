import AppCore
import Engine
import Persistence
import Presentation
import SharedUI
import SwiftUI

/// A read-only list of the managed windows for the current rule, showing each
/// window's title and time-left text. Placed at the bottom of the rule page
/// (ui_design section 4.3).
struct OpenWindowsList: View {
    let core: AppCore
    let selection: SettingsSelection

    private var schedules: [WindowSchedule] {
        core.schedules(for: selection)
    }

    var body: some View {
        Section {
            if schedules.isEmpty {
                Text("No open windows")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schedules) { schedule in
                    windowRow(schedule)
                }
            }
        } header: {
            Text("Open Windows (\(schedules.count))")
        }
    }

    private func windowRow(_ schedule: WindowSchedule) -> some View {
        let title = schedule.title.flatMap { $0.isEmpty ? nil : $0 } ?? schedule.appName
        let statusText = TimeFormatting.formatScheduleStatus(
            schedule.status, deadline: schedule.deadline, now: Date()
        )

        return HStack {
            // For the global rule, show the app icon per row
            if case .globalRule = selection {
                AppIconView(bundleID: schedule.bundleID, size: 16)
            }
            Text(title)
                .lineLimit(1)
            Spacer()
            Text(statusText)
                .foregroundStyle(.secondary)
                .font(.callout)

            // For the global rule, offer a "+" button to create an
            // app-specific rule for this window's app.
            if case .globalRule = selection, !hasAppRule(for: schedule.bundleID) {
                Button {
                    addAppRule(bundleID: schedule.bundleID, appName: schedule.appName)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add rule for \(schedule.appName)")
            }
        }
    }

    // MARK: - Helpers

    private func hasAppRule(for bundleID: String) -> Bool {
        core.store.appRule(bundleID: bundleID) != nil
    }

    private func addAppRule(bundleID: String, appName: String) {
        core.store.addAppRule(bundleID: bundleID, appName: appName, rule: .newAppRuleDefault)
        core.store.save()
        core.open(.appRule(bundleID: bundleID))
    }
}
