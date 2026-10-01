import Engine
import Foundation

/// Pure time formatting functions. No clock reads; `now` is always a parameter.
public enum TimeFormatting {
    // MARK: - Time left

    /// Formats the time remaining until a deadline as a compact string.
    ///
    /// Examples: "in 2h 10m", "in 45m", "in 3d 4h", "in <1m"
    public static func formatTimeLeft(deadline: Date, now: Date) -> String {
        let seconds = deadline.timeIntervalSince(now)
        guard seconds >= 60 else {
            return "in <1m"
        }

        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "in \(days)d \(hours)h"
            }
            if minutes > 0 {
                return "in \(days)d \(minutes)m"
            }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 {
                return "in \(hours)h \(minutes)m"
            }
            return "in \(hours)h"
        }
        return "in \(minutes)m"
    }

    // MARK: - Time ago

    /// Formats a past time as a compact relative string.
    ///
    /// Examples: "just now", "20m ago", "3h ago", "yesterday", "Sep 12"
    public static func formatTimeAgo(date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 {
            return "just now"
        }

        let totalMinutes = Int(seconds) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m ago"
        }

        // Check yesterday before the 24-hour boundary. A date at 11 PM yesterday
        // is only ~1 hour ago at midnight, but should still read "yesterday"
        // once it crosses the calendar-day boundary.
        // Note: Calendar.isDateInYesterday compares against the real clock, so
        // we compute it manually relative to `now` for testability.
        let startOfToday = calendar.startOfDay(for: now)
        if let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
           date >= startOfYesterday, date < startOfToday
        {
            return "yesterday"
        }

        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            return "\(totalHours)h ago"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        return formatter.string(from: date)
    }

    // MARK: - Paused until

    /// Formats a pause end time. Same day: "Paused until 3:40 PM".
    /// Different day: "Paused until Tue 6:00 AM".
    public static func formatPausedUntil(date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current

        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "EEE h:mm a"
        }

        return "Paused until \(formatter.string(from: date))"
    }

    // MARK: - Schedule status text

    /// Produces the display text for a window's schedule status.
    ///
    /// Used in Closing Next (menu) and Open Windows (rule page).
    public static func formatScheduleStatus(
        _ status: ScheduleStatus,
        deadline: Date?,
        now: Date
    ) -> String {
        switch status {
        case .scheduled:
            if let deadline {
                return formatTimeLeft(deadline: deadline, now: now)
            }
            return "in <1m"
        case .dueInUse:
            return "waiting \u{2014} in use"
        case .duePaused:
            return "due now"
        case .dueUnreachable:
            return "waiting \u{2014} other Space"
        case .closing:
            return "closing\u{2026}"
        case .keptOpen:
            return "kept open by app"
        case .disabled:
            return "Won\u{2019}t close"
        }
    }
}
