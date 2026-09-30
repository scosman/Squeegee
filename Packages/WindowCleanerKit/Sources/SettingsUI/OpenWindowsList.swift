import AppCore
import Engine
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
        let title = schedule.title ?? schedule.appName
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
        }
    }
}
