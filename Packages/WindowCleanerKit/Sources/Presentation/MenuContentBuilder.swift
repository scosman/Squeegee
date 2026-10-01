import Engine
import Foundation

/// Which pause mode is active, matching AppCore.PauseOption values stored in
/// AppSettingsRecord.pauseModeRaw. The builder needs this to checkmark the
/// correct pause menu item (engine.md section 6.6).
public enum PauseMode: Sendable, Equatable {
    /// Not paused.
    case none
    /// Paused with an end date ("untilDate" in settings).
    /// `option` distinguishes "For 1 Hour" from "Until Tomorrow".
    case untilDate(PauseDateOption)
    /// Paused indefinitely ("untilResumed" in settings).
    case untilResumed

    /// Which timed pause option was selected.
    public enum PauseDateOption: Sendable, Equatable {
        case oneHour
        case untilTomorrow
    }
}

/// Input for building the menu content.
public struct MenuContentInput: Sendable {
    public let schedules: [WindowSchedule]
    public let recentClosures: [ClosureValue]
    /// For each closure with a documentURL, whether the file still exists.
    public let fileExistsByURL: [URL: Bool]
    public let isPaused: Bool
    public let pauseMode: PauseMode
    public let pausedUntil: Date?
    public let hasPermission: Bool
    public let now: Date
    public let calendar: Calendar

    public init(
        schedules: [WindowSchedule],
        recentClosures: [ClosureValue],
        fileExistsByURL: [URL: Bool] = [:],
        isPaused: Bool,
        pauseMode: PauseMode = .none,
        pausedUntil: Date?,
        hasPermission: Bool,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.schedules = schedules
        self.recentClosures = recentClosures
        self.fileExistsByURL = fileExistsByURL
        self.isPaused = isPaused
        self.pauseMode = pauseMode
        self.pausedUntil = pausedUntil
        self.hasPermission = hasPermission
        self.now = now
        self.calendar = calendar
    }
}

/// Builds a `MenuContent` value tree from the current app state.
/// Pure function: no side effects or system calls.
public enum MenuContentBuilder {
    /// Maximum items shown in Closing Next.
    static let maxClosingNext = 8
    /// Maximum items shown in Recently Closed.
    static let maxRecentlyClosed = 8

    public static func build(input: MenuContentInput) -> MenuContent {
        var sections: [MenuSection] = []

        // Banner section (permission or pause)
        let bannerItems = buildBannerItems(input: input)
        if !bannerItems.isEmpty {
            sections.append(MenuSection(items: bannerItems))
        }

        // Closing Next
        sections.append(buildClosingNextSection(input: input))

        // Recently Closed
        sections.append(buildRecentlyClosedSection(input: input))

        // Footer
        sections.append(buildFooterSection(input: input))

        return MenuContent(sections: sections)
    }

    // MARK: - Banner

    private static func buildBannerItems(input: MenuContentInput) -> [MenuItem] {
        var items: [MenuItem] = []

        if !input.hasPermission {
            items.append(MenuItem(
                title: "Accessibility Access Needed\u{2026}",
                action: .openAccessibilitySettings
            ))
        }

        if input.isPaused {
            if let until = input.pausedUntil, until > input.now {
                let text = TimeFormatting.formatPausedUntil(
                    date: until, now: input.now, calendar: input.calendar
                )
                items.append(MenuItem(title: text, isEnabled: false))
            } else {
                items.append(MenuItem(title: "Paused", isEnabled: false))
            }
            items.append(MenuItem(title: "Resume", action: .resume))
        }

        return items
    }

    // MARK: - Closing Next

    private static func buildClosingNextSection(input: MenuContentInput) -> MenuSection {
        // Filter to active statuses only
        let activeStatuses: Set<ScheduleStatus> = [.scheduled, .dueInUse, .duePaused, .dueUnreachable, .closing]
        let visible = input.schedules.filter { activeStatuses.contains($0.status) }

        if !input.hasPermission {
            return MenuSection(header: "Closing Next", items: [
                MenuItem(
                    title: "Paused \u{2014} needs Accessibility access",
                    isEnabled: false
                )
            ])
        }

        guard !visible.isEmpty else {
            return MenuSection(header: "Closing Next", items: [
                MenuItem(
                    title: "No windows scheduled to close",
                    subtitle: "Add rules in Settings",
                    isEnabled: false
                )
            ])
        }

        let shown = Array(visible.prefix(maxClosingNext))
        var items = shown.map { schedule -> MenuItem in
            let title = schedule.title ?? schedule.appName
            let statusText = TimeFormatting.formatScheduleStatus(
                schedule.status, deadline: schedule.deadline, now: input.now
            )
            let subtitle = "\(schedule.appName) \u{00B7} \(statusText)"
            let action: MenuAction = .openRule(
                bundleID: schedule.bundleID,
                source: schedule.ruleSource
            )
            return MenuItem(
                title: title,
                subtitle: subtitle,
                bundleID: schedule.bundleID,
                action: action
            )
        }

        let remaining = visible.count - maxClosingNext
        if remaining > 0 {
            items.append(MenuItem(
                title: "\(remaining) more",
                isEnabled: false
            ))
        }

        return MenuSection(header: "Closing Next", items: items)
    }

    // MARK: - Recently Closed

    private static func buildRecentlyClosedSection(input: MenuContentInput) -> MenuSection {
        guard !input.recentClosures.isEmpty else {
            return MenuSection(header: "Recently Closed", items: [
                MenuItem(title: "Nothing closed yet", isEnabled: false)
            ])
        }

        let shown = Array(input.recentClosures.prefix(maxRecentlyClosed))
        let items = shown.map { closure -> MenuItem in
            buildClosureItem(closure: closure, input: input)
        }

        return MenuSection(header: "Recently Closed", items: items)
    }

    private static func buildClosureItem(closure: ClosureValue, input: MenuContentInput) -> MenuItem {
        let timeAgo = TimeFormatting.formatTimeAgo(
            date: closure.closedAt, now: input.now, calendar: input.calendar
        )

        if closure.kind == .appQuit {
            // App quit row
            return MenuItem(
                title: closure.appName,
                subtitle: "Quit \u{00B7} \(timeAgo)",
                bundleID: closure.bundleID,
                action: .reopen(closure),
                tooltip: "Open \(closure.appName)"
            )
        }

        let title = closure.windowTitle ?? closure.appName

        if let url = closure.documentURL {
            let fileExists = input.fileExistsByURL[url] ?? true
            if fileExists {
                let fileName = url.lastPathComponent
                return MenuItem(
                    title: title,
                    subtitle: "\(closure.appName) \u{00B7} \(timeAgo)",
                    bundleID: closure.bundleID,
                    action: .reopen(closure),
                    tooltip: "Reopen \(fileName) in \(closure.appName)"
                )
            }
            // File not found
            return MenuItem(
                title: title,
                subtitle: "\(closure.appName) \u{00B7} File not found",
                bundleID: closure.bundleID,
                isEnabled: false
            )
        }

        // No URL — open the app
        return MenuItem(
            title: title,
            subtitle: "\(closure.appName) \u{00B7} \(timeAgo)",
            bundleID: closure.bundleID,
            action: .reopen(closure),
            tooltip: "Open \(closure.appName)"
        )
    }

    // MARK: - Footer

    private static func buildFooterSection(input: MenuContentInput) -> MenuSection {
        var items: [MenuItem] = []

        // Pause submenu (ui_design section 3.2: "Pause ▸" with three options)
        let pauseChildren = [
            MenuItem(
                title: "For 1 Hour",
                action: .pauseOneHour,
                isChecked: input.pauseMode == .untilDate(.oneHour)
            ),
            MenuItem(
                title: "Until Tomorrow",
                action: .pauseUntilTomorrow,
                isChecked: input.pauseMode == .untilDate(.untilTomorrow)
            ),
            MenuItem(
                title: "Until Resumed",
                action: .pauseUntilResumed,
                isChecked: input.pauseMode == .untilResumed
            )
        ]
        items.append(MenuItem(title: "Pause", submenu: pauseChildren))

        items.append(MenuItem(title: "Settings\u{2026}", action: .openSettings, keyEquivalent: ","))
        items.append(MenuItem(title: "Quit WindowCleaner", action: .quit, keyEquivalent: "q"))

        return MenuSection(items: items)
    }
}
