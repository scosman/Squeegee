import Engine
import Foundation
import Presentation
import Testing

// Shared helpers for MenuContentBuilder tests
private let testNow = Date(timeIntervalSinceReferenceDate: 700_000_000)
private let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")! // swiftlint:disable:this force_unwrapping
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
}()

private func defaultInput(
    schedules: [WindowSchedule] = [],
    closures: [ClosureValue] = [],
    fileExistsByURL: [URL: Bool] = [:],
    isPaused: Bool = false,
    pauseMode: PauseMode = .none,
    pausedUntil: Date? = nil,
    hasPermission: Bool = true
) -> MenuContentInput {
    MenuContentInput(
        schedules: schedules,
        recentClosures: closures,
        fileExistsByURL: fileExistsByURL,
        isPaused: isPaused,
        pauseMode: pauseMode,
        pausedUntil: pausedUntil,
        hasPermission: hasPermission,
        now: testNow,
        calendar: testCalendar
    )
}

private func makeSchedule(
    bundleID: String = "com.test.app",
    appName: String = "TestApp",
    title: String? = "Window",
    status: ScheduleStatus = .scheduled,
    deadline: Date? = nil
) -> WindowSchedule {
    WindowSchedule(
        key: WindowKey(pid: 100, windowID: UInt32.random(in: 1 ... 10000)),
        bundleID: bundleID,
        appName: appName,
        title: title,
        ruleSource: .app,
        deadline: deadline ?? testNow.addingTimeInterval(3600),
        status: status
    )
}

// MARK: - Closing Next & Recently Closed

@Suite("MenuContentBuilder — Sections")
struct MenuContentBuilderSectionTests {
    // MARK: - Closing Next

    @Test func upNextWithSchedules() throws {
        let schedules = [
            makeSchedule(appName: "Finder", title: "Downloads", deadline: testNow.addingTimeInterval(2 * 3600 + 10 * 60)),
            makeSchedule(appName: "QuickTime", title: "trailer.mov", deadline: testNow.addingTimeInterval(3 * 3600 + 5 * 60))
        ]
        let content = MenuContentBuilder.build(input: defaultInput(schedules: schedules))
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        #expect(upNext.items.count == 2)
        #expect(upNext.items[0].title == "Downloads")
        #expect(upNext.items[0].subtitle?.contains("in 2h 10m") == true)
        #expect(upNext.items[1].title == "trailer.mov")
    }

    @Test func upNextEmpty() throws {
        let content = MenuContentBuilder.build(input: defaultInput())
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        #expect(upNext.items.count == 1)
        #expect(upNext.items[0].title == "No windows scheduled to close")
        #expect(upNext.items[0].subtitle == "Add rules in Settings")
        #expect(upNext.items[0].isEnabled == false)
    }

    @Test func upNextMoreThanEight() throws {
        let schedules = (0 ..< 10).map { idx in
            makeSchedule(appName: "App\(idx)", title: "W\(idx)", deadline: testNow.addingTimeInterval(TimeInterval(idx) * 60 + 60))
        }
        let content = MenuContentBuilder.build(input: defaultInput(schedules: schedules))
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        // 8 windows + "2 more" row
        #expect(upNext.items.count == 9)
        #expect(upNext.items.last?.title == "2 more")
        #expect(upNext.items.last?.isEnabled == false)
    }

    @Test func upNextExcludesDisabledAndKeptOpen() throws {
        let schedules = [
            makeSchedule(title: "Visible", status: .scheduled),
            makeSchedule(title: "Off", status: .disabled),
            makeSchedule(title: "Kept", status: .keptOpen)
        ]
        let content = MenuContentBuilder.build(input: defaultInput(schedules: schedules))
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        #expect(upNext.items.count == 1)
        #expect(upNext.items[0].title == "Visible")
    }

    @Test func upNextClickOpensRule() throws {
        let schedules = [
            makeSchedule(bundleID: "com.apple.finder", status: .scheduled)
        ]
        let content = MenuContentBuilder.build(input: defaultInput(schedules: schedules))
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        if case let .openRule(bundleID, _) = upNext.items[0].action {
            #expect(bundleID == "com.apple.finder")
        } else {
            Issue.record("Expected openRule action")
        }
    }

    // MARK: - Recently Closed

    @Test func recentlyClosedWithURL() throws {
        let url = try #require(URL(string: "file:///Users/test/Report.pdf"))
        let closure = ClosureValue(
            bundleID: "com.apple.Preview", appName: "Preview",
            windowTitle: "Report.pdf", documentURL: url,
            kind: .windowClosed, closedAt: testNow.addingTimeInterval(-20 * 60)
        )
        let content = MenuContentBuilder.build(input: defaultInput(
            closures: [closure], fileExistsByURL: [url: true]
        ))
        let section = try #require(content.sections.first(where: { $0.header == "Recently Closed" }))
        #expect(section.items[0].title == "Report.pdf")
        #expect(section.items[0].subtitle?.contains("20m ago") == true)
        #expect(section.items[0].tooltip?.contains("Reopen") == true)
        #expect(section.items[0].isEnabled == true)
    }

    @Test func recentlyClosedFileNotFound() throws {
        let url = try #require(URL(string: "file:///Users/test/Gone.pdf"))
        let closure = ClosureValue(
            bundleID: "com.apple.Preview", appName: "Preview",
            windowTitle: "Gone.pdf", documentURL: url,
            kind: .windowClosed, closedAt: testNow.addingTimeInterval(-60)
        )
        let content = MenuContentBuilder.build(input: defaultInput(
            closures: [closure], fileExistsByURL: [url: false]
        ))
        let section = try #require(content.sections.first(where: { $0.header == "Recently Closed" }))
        #expect(section.items[0].subtitle?.contains("File not found") == true)
        #expect(section.items[0].isEnabled == false)
    }

    @Test func recentlyClosedNoURL() throws {
        let closure = ClosureValue(
            bundleID: "com.apple.finder", appName: "Finder",
            windowTitle: "Downloads", documentURL: nil,
            kind: .windowClosed, closedAt: testNow.addingTimeInterval(-3600)
        )
        let content = MenuContentBuilder.build(input: defaultInput(closures: [closure]))
        let section = try #require(content.sections.first(where: { $0.header == "Recently Closed" }))
        #expect(section.items[0].tooltip?.contains("Open Finder") == true)
        #expect(section.items[0].isEnabled == true)
    }

    @Test func recentlyClosedAppQuit() throws {
        let closure = ClosureValue(
            bundleID: "com.apple.QuickTimePlayerX", appName: "QuickTime Player",
            windowTitle: nil, documentURL: nil,
            kind: .appQuit, closedAt: testNow.addingTimeInterval(-2 * 3600)
        )
        let content = MenuContentBuilder.build(input: defaultInput(closures: [closure]))
        let section = try #require(content.sections.first(where: { $0.header == "Recently Closed" }))
        #expect(section.items[0].title == "QuickTime Player")
        #expect(section.items[0].subtitle?.contains("Quit") == true)
    }

    @Test func recentlyClosedEmpty() throws {
        let content = MenuContentBuilder.build(input: defaultInput())
        let section = try #require(content.sections.first(where: { $0.header == "Recently Closed" }))
        #expect(section.items[0].title == "Nothing closed yet")
        #expect(section.items[0].isEnabled == false)
    }
}

// MARK: - Banners & Footer

@Suite("MenuContentBuilder — Banners and Footer")
struct MenuContentBuilderBannerFooterTests {
    // MARK: - Permission missing

    @Test func permissionMissingBanner() {
        let content = MenuContentBuilder.build(input: defaultInput(hasPermission: false))
        let bannerSection = content.sections[0]
        #expect(bannerSection.items[0].title.contains("Accessibility"))
        if case .openAccessibilitySettings = bannerSection.items[0].action {
            // OK
        } else {
            Issue.record("Expected openAccessibilitySettings action")
        }
    }

    @Test func permissionMissingClosingNextPaused() throws {
        let content = MenuContentBuilder.build(input: defaultInput(hasPermission: false))
        let upNext = try #require(content.sections.first(where: { $0.header == "Closing Next" }))
        #expect(upNext.items[0].title.contains("needs Accessibility"))
    }

    // MARK: - Paused

    @Test func pausedBanner() {
        let until = testNow.addingTimeInterval(3600)
        let content = MenuContentBuilder.build(input: defaultInput(
            isPaused: true, pauseMode: .untilDate(.oneHour), pausedUntil: until
        ))
        let bannerSection = content.sections[0]
        #expect(bannerSection.items[0].title.contains("Paused until"))
        #expect(bannerSection.items[0].isEnabled == false)
        #expect(bannerSection.items[1].title == "Resume")
        if case .resume = bannerSection.items[1].action {
            // OK
        } else {
            Issue.record("Expected resume action")
        }
    }

    @Test func pausedUntilResumedBanner() {
        let content = MenuContentBuilder.build(input: defaultInput(
            isPaused: true, pauseMode: .untilResumed, pausedUntil: nil
        ))
        let bannerSection = content.sections[0]
        #expect(bannerSection.items[0].title == "Paused")
    }

    // MARK: - Footer

    @Test func footerContainsPauseSubmenuAndSettings() throws {
        let content = MenuContentBuilder.build(input: defaultInput())
        let footer = try #require(content.sections.last)
        let titles = footer.items.map(\.title)
        #expect(titles.contains("Pause"))
        #expect(titles.contains("Settings\u{2026}"))
        #expect(titles.contains("Quit Squeegee"))
        // Pause options are inside the submenu, not flat
        #expect(!titles.contains("For 1 Hour"))
    }

    @Test func footerPauseSubmenuHasThreeOptions() throws {
        let content = MenuContentBuilder.build(input: defaultInput())
        let footer = try #require(content.sections.last)
        let pause = try #require(footer.items.first(where: { $0.title == "Pause" }))
        let children = try #require(pause.submenu)
        #expect(children.count == 3)
        #expect(children[0].title == "For 1 Hour")
        #expect(children[1].title == "Until Tomorrow")
        #expect(children[2].title == "Until Resumed")
    }

    @Test func footerKeyEquivalents() throws {
        let content = MenuContentBuilder.build(input: defaultInput())
        let footer = try #require(content.sections.last)
        let settings = try #require(footer.items.first(where: { $0.title == "Settings\u{2026}" }))
        #expect(settings.keyEquivalent == ",")
        let quit = try #require(footer.items.first(where: { $0.title == "Quit Squeegee" }))
        #expect(quit.keyEquivalent == "q")
    }

    @Test func footerPauseCheckedWhenUntilResumed() throws {
        let content = MenuContentBuilder.build(input: defaultInput(
            isPaused: true, pauseMode: .untilResumed, pausedUntil: nil
        ))
        let footer = try #require(content.sections.last)
        let pause = try #require(footer.items.first(where: { $0.title == "Pause" }))
        let children = try #require(pause.submenu)
        let untilResumed = children.first(where: { $0.title == "Until Resumed" })
        #expect(untilResumed?.isChecked == true)
        let forOneHour = children.first(where: { $0.title == "For 1 Hour" })
        #expect(forOneHour?.isChecked == false)
        let untilTomorrow = children.first(where: { $0.title == "Until Tomorrow" })
        #expect(untilTomorrow?.isChecked == false)
    }

    @Test func footerPauseCheckedWhenOneHour() throws {
        let content = MenuContentBuilder.build(input: defaultInput(
            isPaused: true, pauseMode: .untilDate(.oneHour), pausedUntil: testNow.addingTimeInterval(3600)
        ))
        let footer = try #require(content.sections.last)
        let pause = try #require(footer.items.first(where: { $0.title == "Pause" }))
        let children = try #require(pause.submenu)
        let forOneHour = children.first(where: { $0.title == "For 1 Hour" })
        #expect(forOneHour?.isChecked == true)
        let untilTomorrow = children.first(where: { $0.title == "Until Tomorrow" })
        #expect(untilTomorrow?.isChecked == false)
        let untilResumed = children.first(where: { $0.title == "Until Resumed" })
        #expect(untilResumed?.isChecked == false)
    }

    @Test func footerPauseCheckedWhenUntilTomorrow() throws {
        let content = MenuContentBuilder.build(input: defaultInput(
            isPaused: true, pauseMode: .untilDate(.untilTomorrow), pausedUntil: testNow.addingTimeInterval(12 * 3600)
        ))
        let footer = try #require(content.sections.last)
        let pause = try #require(footer.items.first(where: { $0.title == "Pause" }))
        let children = try #require(pause.submenu)
        let untilTomorrow = children.first(where: { $0.title == "Until Tomorrow" })
        #expect(untilTomorrow?.isChecked == true)
        let forOneHour = children.first(where: { $0.title == "For 1 Hour" })
        #expect(forOneHour?.isChecked == false)
        let untilResumed = children.first(where: { $0.title == "Until Resumed" })
        #expect(untilResumed?.isChecked == false)
    }
}

// MARK: - MenuAction.logLabel

@Suite("MenuAction — logLabel")
struct MenuActionLogLabelTests {
    @Test func logLabelOmitsPrivateData() {
        // reopen carries a ClosureValue with a window title — logLabel must not leak it.
        let closure = ClosureValue(
            bundleID: "com.example.app",
            appName: "Example",
            windowTitle: "SECRET_TITLE",
            documentURL: URL(string: "file:///Users/test/secret.txt"),
            kind: .windowClosed,
            closedAt: Date()
        )
        let label = MenuAction.reopen(closure).logLabel
        #expect(label == "reopen")
        #expect(!label.contains("SECRET_TITLE"))
    }

    @Test func logLabelIncludesBundleIDForOpenRule() {
        let label = MenuAction.openRule(bundleID: "com.apple.finder", source: .app).logLabel
        #expect(label.contains("com.apple.finder"))
    }

    @Test func logLabelSimpleCases() {
        #expect(MenuAction.resume.logLabel == "resume")
        #expect(MenuAction.quit.logLabel == "quit")
        #expect(MenuAction.openSettings.logLabel == "openSettings")
        #expect(MenuAction.pauseOneHour.logLabel == "pauseOneHour")
    }
}
