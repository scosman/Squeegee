import Engine
import Foundation
import Presentation
import Testing

@Suite("TimeFormatting")
struct TimeFormattingTests {
    private let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")! // swiftlint:disable:this force_unwrapping
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    // MARK: - Time left

    @Test func timeLeftLessThanOneMinute() {
        let deadline = now.addingTimeInterval(30)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in <1m")
    }

    @Test func timeLeftExactlyOneMinute() {
        let deadline = now.addingTimeInterval(60)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 1m")
    }

    @Test func timeLeftMinutesOnly() {
        let deadline = now.addingTimeInterval(45 * 60)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 45m")
    }

    @Test func timeLeftHoursAndMinutes() {
        let deadline = now.addingTimeInterval(2 * 3600 + 10 * 60)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 2h 10m")
    }

    @Test func timeLeftExactHours() {
        let deadline = now.addingTimeInterval(6 * 3600)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 6h")
    }

    @Test func timeLeftDaysAndHours() {
        let deadline = now.addingTimeInterval(3 * 86400 + 4 * 3600)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 3d 4h")
    }

    @Test func timeLeftDaysAndMinutes() {
        let deadline = now.addingTimeInterval(86400 + 30 * 60)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 1d 30m")
    }

    @Test func timeLeftExactDays() {
        let deadline = now.addingTimeInterval(2 * 86400)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in 2d")
    }

    @Test func timeLeftPastDeadline() {
        let deadline = now.addingTimeInterval(-100)
        #expect(TimeFormatting.formatTimeLeft(deadline: deadline, now: now) == "in <1m")
    }

    // MARK: - Time ago

    @Test func timeAgoJustNow() {
        let date = now.addingTimeInterval(-30)
        #expect(TimeFormatting.formatTimeAgo(date: date, now: now, calendar: calendar) == "just now")
    }

    @Test func timeAgoMinutes() {
        let date = now.addingTimeInterval(-20 * 60)
        #expect(TimeFormatting.formatTimeAgo(date: date, now: now, calendar: calendar) == "20m ago")
    }

    @Test func timeAgoHours() {
        let date = now.addingTimeInterval(-3 * 3600)
        #expect(TimeFormatting.formatTimeAgo(date: date, now: now, calendar: calendar) == "3h ago")
    }

    @Test func timeAgoYesterday() {
        // Create a date that is definitely yesterday per the calendar
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = startOfToday.addingTimeInterval(-3600)
        #expect(TimeFormatting.formatTimeAgo(date: yesterday, now: now, calendar: calendar) == "yesterday")
    }

    @Test func timeAgoOlderDate() {
        let date = now.addingTimeInterval(-5 * 86400)
        let result = TimeFormatting.formatTimeAgo(date: date, now: now, calendar: calendar)
        // Should be a short date like "Sep 12"
        #expect(result.contains(" "))
        #expect(!result.contains("ago"))
    }

    // MARK: - Paused until

    @Test func pausedUntilSameDay() {
        let until = now.addingTimeInterval(3600)
        let result = TimeFormatting.formatPausedUntil(date: until, now: now, calendar: calendar)
        #expect(result.hasPrefix("Paused until "))
        // With pinned locale, should contain AM/PM format without weekday
        #expect(!result.contains("Mon") && !result.contains("Tue") && !result.contains("Wed")
            && !result.contains("Thu") && !result.contains("Fri") && !result.contains("Sat")
            && !result.contains("Sun"))
    }

    @Test func pausedUntilDifferentDay() {
        let until = now.addingTimeInterval(24 * 3600)
        let result = TimeFormatting.formatPausedUntil(date: until, now: now, calendar: calendar)
        #expect(result.hasPrefix("Paused until "))
        // Different day should include a weekday abbreviation
        let hasWeekday = result.contains("Mon") || result.contains("Tue") || result.contains("Wed")
            || result.contains("Thu") || result.contains("Fri") || result.contains("Sat")
            || result.contains("Sun")
        #expect(hasWeekday)
    }

    // MARK: - Schedule status

    @Test func scheduleStatusScheduled() {
        let deadline = now.addingTimeInterval(2 * 3600 + 10 * 60)
        let result = TimeFormatting.formatScheduleStatus(.scheduled, deadline: deadline, now: now)
        #expect(result == "in 2h 10m")
    }

    @Test func scheduleStatusDueInUse() {
        let result = TimeFormatting.formatScheduleStatus(.dueInUse, deadline: nil, now: now)
        #expect(result == "waiting \u{2014} in use")
    }

    @Test func scheduleStatusDuePaused() {
        let result = TimeFormatting.formatScheduleStatus(.duePaused, deadline: nil, now: now)
        #expect(result == "due now")
    }

    @Test func scheduleStatusDueUnreachable() {
        let result = TimeFormatting.formatScheduleStatus(.dueUnreachable, deadline: nil, now: now)
        #expect(result == "waiting \u{2014} other Space")
    }

    @Test func scheduleStatusClosing() {
        let result = TimeFormatting.formatScheduleStatus(.closing, deadline: nil, now: now)
        #expect(result == "closing\u{2026}")
    }

    @Test func scheduleStatusKeptOpen() {
        let result = TimeFormatting.formatScheduleStatus(.keptOpen, deadline: nil, now: now)
        #expect(result == "kept open by app")
    }

    @Test func scheduleStatusDisabled() {
        let result = TimeFormatting.formatScheduleStatus(.disabled, deadline: nil, now: now)
        #expect(result == "Won\u{2019}t close")
    }
}
