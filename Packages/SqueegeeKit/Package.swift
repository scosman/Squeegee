// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SqueegeeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Presentation", targets: ["Presentation"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "SystemBridge", targets: ["SystemBridge"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "SharedUI", targets: ["SharedUI"]),
        .library(name: "MenuBarUI", targets: ["MenuBarUI"]),
        .library(name: "OnboardingUI", targets: ["OnboardingUI"]),
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
        .library(name: "AppShellUI", targets: ["AppShellUI"]),
        .library(name: "ManualTestKit", targets: ["ManualTestKit"])
    ],
    targets: [
        // L0: Engine (Foundation only; pure)
        .target(
            name: "Engine",
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "EngineTests",
            dependencies: ["Engine"],
            swiftSettings: warningsAsErrors
        ),

        // L0: Presentation (Foundation; depends Engine)
        .target(
            name: "Presentation",
            dependencies: ["Engine"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: ["Presentation"],
            swiftSettings: warningsAsErrors
        ),

        // L1: Persistence (SwiftData; depends Engine)
        .target(
            name: "Persistence",
            dependencies: ["Engine"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            swiftSettings: warningsAsErrors
        ),

        // L1: SystemBridge (AppKit, ApplicationServices, CoreGraphics, ServiceManagement; depends Engine)
        .target(
            name: "SystemBridge",
            dependencies: ["Engine"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "SystemBridgeTests",
            dependencies: ["SystemBridge"],
            swiftSettings: warningsAsErrors
        ),

        // L2: AppCore (depends Engine, Presentation, Persistence)
        .target(
            name: "AppCore",
            dependencies: ["Engine", "Presentation", "Persistence"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "TestSupport"],
            swiftSettings: warningsAsErrors
        ),

        // L3: SharedUI (SwiftUI; depends Presentation, AppCore)
        .target(
            name: "SharedUI",
            dependencies: ["Presentation", "AppCore"],
            swiftSettings: warningsAsErrors
        ),

        // L3: MenuBarUI (AppKit; depends Presentation, AppCore)
        .target(
            name: "MenuBarUI",
            dependencies: ["Presentation", "AppCore"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "MenuBarUITests",
            dependencies: ["MenuBarUI", "Presentation"],
            swiftSettings: warningsAsErrors
        ),

        // L3: OnboardingUI (SwiftUI; depends SharedUI, AppCore)
        .target(
            name: "OnboardingUI",
            dependencies: ["SharedUI", "AppCore"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "OnboardingUITests",
            dependencies: ["OnboardingUI", "AppCore", "TestSupport"],
            swiftSettings: warningsAsErrors
        ),

        // L3: SettingsUI (SwiftUI; depends SharedUI, AppCore, Persistence)
        .target(
            name: "SettingsUI",
            dependencies: ["SharedUI", "AppCore", "Persistence"],
            swiftSettings: warningsAsErrors
        ),

        // L3b: AppShellUI (SwiftUI; depends OnboardingUI, SettingsUI, AppCore)
        .target(
            name: "AppShellUI",
            dependencies: ["OnboardingUI", "SettingsUI", "AppCore"],
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "AppShellUITests",
            dependencies: ["AppShellUI"],
            swiftSettings: warningsAsErrors
        ),

        // ManualTestKit (Foundation; pure)
        .target(
            name: "ManualTestKit",
            swiftSettings: warningsAsErrors
        ),
        .testTarget(
            name: "ManualTestKitTests",
            dependencies: ["ManualTestKit"],
            swiftSettings: warningsAsErrors
        ),

        // TestSupport (test-only target at Tests/TestSupport; not a product)
        .target(
            name: "TestSupport",
            dependencies: ["AppCore", "Engine"],
            path: "Tests/TestSupport",
            swiftSettings: warningsAsErrors
        ),

        // perf-bench CLI — deterministic benchmark for AppCore CPU
        .executableTarget(
            name: "perf-bench",
            dependencies: ["AppCore", "Persistence", "Engine", "TestSupport"],
            path: "Sources/PerfBench",
            swiftSettings: warningsAsErrors
        ),

        // manual-tests-check CLI
        .executableTarget(
            name: "manual-tests-check",
            dependencies: ["ManualTestKit"],
            swiftSettings: warningsAsErrors
        )
    ],
    swiftLanguageModes: [.v6]
)

/// Applied to every target so the whole package is held to the strict bar.
let warningsAsErrors: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]
