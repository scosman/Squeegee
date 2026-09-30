---
status: draft
---

# Phase 6: App Shell and Settings

## Overview

This phase builds the first runnable end-to-end app. It wires the composition root (AppDelegate), implements window/route/activation-policy handling, and builds the three UI modules that were stubs: SharedUI (AppIconView, SuggestionListView), SettingsUI (sidebar, General page, Rule page with Open Windows, add-app menu, Suggestions sheet), and AppShellUI (MainWindowRootView with route switching). The App target becomes a real menu-bar app that opens its window for onboarding or settings.

## Steps

### 1. SharedUI module

Replace the placeholder with real views:

- `AppIconView`: loads an app icon by bundle ID from `NSWorkspace.shared.icon(forFile:)` via the app URL, with a fallback to a generic app icon. Caches icons by bundle ID. Configurable size.
- `SuggestionListView`: the shared suggestions checklist used in both onboarding step 3 and the Settings "Suggested Rules" sheet. Category headers, checkbox rows with app icon, name, and rule summary. "N selected" count. Empty state text. Binding to a set of selected bundle IDs.

### 2. SettingsUI module

Replace the placeholder with the full settings UI:

- `SettingsRootView`: a `NavigationSplitView` with sidebar and detail.
- `SettingsSidebar`: General row, "All other apps" row, per-app rows (sorted by name, with icon and rule summary), bottom bar with +/- buttons and the add menu.
- `GeneralPage`: grouped Form with Status (Accessibility, Pause), Startup (login toggle), Menu Bar (show icon toggle with footer), About (version).
- `RulePage`: grouped Form with header (icon + name), toggle, Close after picker (presets + custom), Measure from picker, Quit policy picker (hidden for global/Finder), Open Windows list, Remove Rule button.
- `OpenWindowsList`: read-only list of window schedules for the current rule, with title and time-left text. Updates via `core.schedules(for:)`.
- `AddAppMenu`: menu button with Running Apps submenu, Choose App (open panel), Suggested Rules.
- `SuggestionsSheet`: standard sheet wrapping `SuggestionListView` with Cancel / "Add N Rules" buttons. Empty state.
- `PermissionBanner`: yellow warning banner for missing Accessibility, shown on every detail page.

### 3. AppShellUI module

Replace the placeholder with:

- `LaunchState`: an observable class that captures the `OpenWindowAction` from the SwiftUI environment (Biscotti workaround for scene closures not tracking Observation).
- `MainWindowRootContent`: the wrapper view that stores `LaunchState` and provides it to `MainWindowRootView`. This is what the Scene closure instantiates.
- `MainWindowRootView`: switches on `core.route` to show either onboarding or settings content. (Onboarding views are stubs until Phase 8; a placeholder text is shown.)

### 4. App target (composition root)

- `AppDelegate`: build `Store(.onDisk(...))`, create `AppCorePorts` via `LivePorts.make()`, create `AppCore`, create `StatusItemController` placeholder reference, call `core.start()`. Handle `showMainWindow` callback. Observe `NSWindow.willCloseNotification` to switch activation policy. Handle `applicationShouldHandleReopen`. Call `core.prepareForTermination` from `applicationWillTerminate`.
- `WindowCleanerApp.swift`: update the scene to use `MainWindowRootContent(launchState:)`, set `.windowResizability(.contentMinSize)`, `.defaultSize(width: 760, height: 540)`.

### 5. Package.swift updates

- Add `Engine` dependency to `SharedUI` (needed for `Suggestion`, `Rule` types).
- Add `Presentation` dependency if needed for formatting in SettingsUI (already present).

## Tests

No new unit tests in this phase. The UI modules are SwiftUI views that are verified by building and visual inspection. The SettingsUI view models are thin wrappers around `AppCore` and `Store`, which are already tested in AppCoreTests. Tests for MenuRenderer come in Phase 7, onboarding view model tests come in Phase 8.
