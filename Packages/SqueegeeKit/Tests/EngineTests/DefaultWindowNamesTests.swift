import Foundation
import Testing
@testable import Engine

@Suite("DefaultWindowNames")
struct DefaultWindowNamesTests {
    // MARK: - title(for:)

    @Test func knownBundleID_returnsDefaultName() {
        #expect(DefaultWindowNames.title(for: "com.apple.systempreferences") == "System Settings")
    }

    @Test func appStore_returnsDefaultName() {
        #expect(DefaultWindowNames.title(for: "com.apple.AppStore") == "App Store")
    }

    @Test func unknownBundleID_returnsNil() {
        #expect(DefaultWindowNames.title(for: "com.unknown.app") == nil)
    }

    // MARK: - effectiveTitle

    @Test func realTitle_winsOverDefault() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: "General",
            bundleID: "com.apple.systempreferences"
        )
        #expect(result == "General")
    }

    @Test func nilTitle_returnsDefault() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: nil,
            bundleID: "com.apple.systempreferences"
        )
        #expect(result == "System Settings")
    }

    @Test func emptyTitle_returnsDefault() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: "",
            bundleID: "com.apple.systempreferences"
        )
        #expect(result == "System Settings")
    }

    @Test func whitespaceOnlyTitle_returnsDefault() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: "   ",
            bundleID: "com.apple.systempreferences"
        )
        #expect(result == "System Settings")
    }

    @Test func nilTitle_unknownApp_returnsNil() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: nil,
            bundleID: "com.unknown.app"
        )
        #expect(result == nil)
    }

    @Test func emptyTitle_unknownApp_returnsNil() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: "",
            bundleID: "com.unknown.app"
        )
        #expect(result == nil)
    }

    @Test func titleWithSurroundingWhitespace_isTrimmed() {
        let result = DefaultWindowNames.effectiveTitle(
            axTitle: "  General  ",
            bundleID: "com.apple.systempreferences"
        )
        #expect(result == "General")
    }
}
