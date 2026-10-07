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

    // MARK: - displayTitle

    @Test func displayTitle_usesWindowTitle() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "My Document",
            bundleID: "com.example.app",
            appName: "Example"
        )
        #expect(result == "My Document")
    }

    @Test func displayTitle_trimsWindowTitle() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "  My Document  ",
            bundleID: "com.example.app",
            appName: "Example"
        )
        #expect(result == "My Document")
    }

    @Test func displayTitle_nilTitle_fallsToBundleDefault() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: nil,
            bundleID: "com.apple.systempreferences",
            appName: "System Preferences"
        )
        #expect(result == "System Settings")
    }

    @Test func displayTitle_emptyTitle_fallsToBundleDefault() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "",
            bundleID: "com.apple.systempreferences",
            appName: "System Preferences"
        )
        #expect(result == "System Settings")
    }

    @Test func displayTitle_whitespaceTitle_fallsToBundleDefault() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "   ",
            bundleID: "com.apple.AppStore",
            appName: "App Store"
        )
        #expect(result == "App Store")
    }

    @Test func displayTitle_nilTitle_unknownBundle_fallsToAppName() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: nil,
            bundleID: "com.example.app",
            appName: "Example"
        )
        #expect(result == "Example")
    }

    @Test func displayTitle_emptyTitle_unknownBundle_fallsToAppName() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "",
            bundleID: "com.example.app",
            appName: "Example"
        )
        #expect(result == "Example")
    }

    @Test func displayTitle_trimsAppName() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: nil,
            bundleID: "com.example.app",
            appName: "  Example  "
        )
        #expect(result == "Example")
    }

    @Test func displayTitle_emptyAppName_returnsOpenWindow() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: nil,
            bundleID: "com.example.app",
            appName: ""
        )
        #expect(result == "Open Window")
    }

    @Test func displayTitle_whitespaceAppName_returnsOpenWindow() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: nil,
            bundleID: "com.example.app",
            appName: "   "
        )
        #expect(result == "Open Window")
    }

    @Test func displayTitle_allEmpty_returnsOpenWindow() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "",
            bundleID: "com.unknown.app",
            appName: ""
        )
        #expect(result == "Open Window")
    }

    @Test func displayTitle_allNilOrWhitespace_returnsOpenWindow() {
        let result = DefaultWindowNames.displayTitle(
            windowTitle: "   ",
            bundleID: "com.unknown.app",
            appName: "   "
        )
        #expect(result == "Open Window")
    }
}
