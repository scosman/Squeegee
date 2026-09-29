---
status: draft
---

# Phase 1: Scaffolding

## Overview

Set up the entire project skeleton so that `make ci` passes green on an empty codebase. This includes the `WindowCleanerKit` Swift package with all module stubs and test targets, the XcodeGen-based `App/` and `ManualTestApp/` shells, tooling (Makefile, lint/format configs, CI workflow, hooks-mcp, pre-commit hook), the `ManualTestKit` module with the `manual-tests-check` executable (ported from Biscotti), and the `CLAUDE.md` repo guide.

## Steps

1. Create `.gitignore` with all Swift/Xcode/tooling ignores (ported from Biscotti, adapted for WindowCleaner).
2. Create `Packages/WindowCleanerKit/Package.swift` with all module targets (Engine, Presentation, Persistence, SystemBridge, AppCore, SharedUI, MenuBarUI, OnboardingUI, SettingsUI, AppShellUI, ManualTestKit), test targets (EngineTests, PresentationTests, PersistenceTests, SystemBridgeTests, AppCoreTests, ManualTestKitTests), the TestSupport target (plain target in Tests/TestSupport), and the `manual-tests-check` executable. `swift-tools-version: 6.1`, `platforms: [.macOS(.v15)]`, `swiftLanguageModes: [.v6]`, `warningsAsErrors` on every target.
3. Create stub source files for each module (`Sources/<Module>/Placeholder.swift`) and test target (`Tests/<Module>Tests/PlaceholderTests.swift`) so SPM resolves. TestSupport gets `Tests/TestSupport/Placeholder.swift`. `manual-tests-check` gets `Sources/manual-tests-check/main.swift`.
4. Create `ManualTestKit` source files ported from Biscotti: `TestScript.swift`, `TestStep.swift`, `TestResult.swift`, `TestStatus.swift`, `CheckOutcome.swift`, `ResultsStore.swift`, and `Scripts/AllScripts.swift` (with the sb_* scripts from manual_test_app.md).
5. Create `Sources/manual-tests-check/main.swift` (ported from Biscotti).
6. Create `App/project.yml` (XcodeGen) for the thin menu bar app: bundle ID `net.scosman.windowcleaner`, `LSUIElement = YES`, macOS 15.0 deployment target, Swift 6.0, hardened runtime, Developer ID signing, depending on AppShellUI, MenuBarUI, AppCore, SystemBridge, Persistence.
7. Create `App/Sources/WindowCleanerApp.swift` (empty `@main` SwiftUI App with `defaultLaunchBehavior(.suppressed)`), `App/Sources/AppDelegate.swift` (stub), `App/Resources/Info.plist` (LSUIElement), `App/WindowCleaner.entitlements` (empty).
8. Create `ManualTestApp/project.yml` (XcodeGen), `ManualTestApp/Sources/` (app entry, ScriptTabView, ScriptRunnerView, StepView, WiredScripts ported from Biscotti), `ManualTestApp/ManualTestApp.entitlements`, `ManualTestApp/Resources/Info.plist`, `ManualTestApp/Results/manual_test_results.json` (empty `{}`).
9. Create `.swiftlint.yml` and `.swiftformat` (ported from Biscotti, paths changed to `Packages App ManualTestApp`).
10. Create `Brewfile` (xcodegen, node).
11. Create `Makefile` with all targets from architecture.md section 9.1.
12. Create `.githooks/pre-commit` (ported from Biscotti).
13. Create `.mcp.json` and `hooks_mcp.yaml` (adapted from Biscotti).
14. Create `.github/workflows/ci.yml` (3-tier CI from architecture.md section 9.2).
15. Create `CLAUDE.md` (repo guide per architecture.md section 9.4).

## Tests

- ManualTestKitTests: `ResultsStore` round-trip (load/save/record), `unrun` finds missing steps, `markScriptNotRun` resets steps, `recordableStepIDs` excludes instruction steps.
- All other test targets: placeholder tests that pass (to be replaced in later phases).
- `make ci` (lint + test + build) passes green.
