import Engine
import Presentation
import Testing

@Suite("RuleSummary")
struct RuleSummaryTests {
    // MARK: - Sidebar summary

    @Test func sidebarSummaryDisabled() {
        let rule = Rule(isEnabled: false, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "Off")
    }

    @Test func sidebarSummaryLastActive() {
        let rule = Rule(isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "6h \u{00B7} last active")
    }

    @Test func sidebarSummaryOpened() {
        let rule = Rule(isEnabled: true, closeAfter: 2 * 3600, measureFrom: .opened, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "2h \u{00B7} opened")
    }

    @Test func sidebarSummaryWithQuit() {
        let rule = Rule(isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .always)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "2h \u{00B7} last active \u{00B7} quits")
    }

    @Test func sidebarSummaryIfClosedByWindowCleaner() {
        let rule = Rule(isEnabled: true, closeAfter: 1 * 3600, measureFrom: .lastActive, quitPolicy: .ifClosedByWindowCleaner)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "1h \u{00B7} last active \u{00B7} quits")
    }

    @Test func sidebarSummaryMinutes() {
        let rule = Rule(isEnabled: true, closeAfter: 30 * 60, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "30m \u{00B7} last active")
    }

    @Test func sidebarSummaryDays() {
        let rule = Rule(isEnabled: true, closeAfter: 2 * 86400, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "2d \u{00B7} last active")
    }

    @Test func sidebarSummaryWeek() {
        let rule = Rule(isEnabled: true, closeAfter: 7 * 86400, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "1w \u{00B7} last active")
    }

    @Test func sidebarSummaryDaysWithMinutes() {
        // 24h 30m = 1 day + 30 minutes (no hours). Should not silently drop the 30 minutes.
        let rule = Rule(isEnabled: true, closeAfter: 86400 + 1800, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "1d 30m \u{00B7} last active")
    }

    @Test func sidebarSummaryDaysWithHoursAndMinutes() {
        // 1d 2h 15m — shows the two largest components: "1d 2h"
        let rule = Rule(isEnabled: true, closeAfter: 86400 + 2 * 3600 + 15 * 60, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "1d 2h \u{00B7} last active")
    }

    @Test func sidebarSummaryHoursWithMinutes() {
        let rule = Rule(isEnabled: true, closeAfter: 3600 + 30 * 60, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.sidebarSummary(rule: rule) == "1h 30m \u{00B7} last active")
    }

    // MARK: - Suggestion summary

    @Test func suggestionSummaryLastUse() {
        let rule = Rule(isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never)
        #expect(RuleSummary.suggestionSummary(rule: rule) == "Close windows 6h after last use")
    }

    @Test func suggestionSummaryOpening() {
        let rule = Rule(isEnabled: true, closeAfter: 12 * 3600, measureFrom: .opened, quitPolicy: .never)
        #expect(RuleSummary.suggestionSummary(rule: rule) == "Close windows 12h after opening")
    }

    @Test func suggestionSummaryWithQuit() {
        let rule = Rule(isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .always)
        #expect(RuleSummary.suggestionSummary(rule: rule) == "Close windows 2h after last use, then quit")
    }
}
