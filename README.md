<div align="center">
<img width="84" height="83" alt="biscotti icon" src="https://github.com/user-attachments/assets/b681fc93-1599-4dbb-9753-b443f0b1ba38" />

### Squeegee

**Clean your MacOS Windows.**

<a href="https://github.com/scosman/Squeegee/releases/latest/download/Squeegee.dmg">
  <img width="165" height="38" alt="Download for macOS" src="https://github.com/user-attachments/assets/a0ff77ed-d9cd-49df-9ba5-b866098d8d67" />
</a>
</div>

A native macOS menu bar app that closes stale windows. Set per-app rules ("close Finder windows 6 hours after I last used them"), and WindowCleaner closes each window when its time is up. It works per **window**, not per process: closing one stale Finder window leaves the other Finder windows open.

## Features

- **Per-window close timers.** Set a duration per app. WindowCleaner closes each window when its timer expires.
- **Measure from last active or opened.** "Last active" (default) tracks the last time you used a window. "Opened" counts from when the window first appeared.
- **Per-app rules + a global default.** Add rules for specific apps, or set a global rule that applies to everything else.
- **Optional quit-when-empty.** An app can quit after WindowCleaner has closed all its windows.
- **Reopen.** Recent closures show in the menu bar with a one-click reopen for documents that had a URL.
- **Suggestions.** A built-in catalog proposes rules for common apps (Finder, Preview, QuickTime, messaging apps, and more).
- **Onboarding.** A 4-step first-launch flow: welcome, Accessibility permission, suggested rules, and completion.
- **Pause.** Pause all closures from the menu bar -- for a duration or until you resume.
- **Menu bar icon.** Shows upcoming and recent closures. The icon can be hidden in Settings.
- **Launch at login.** Toggle in Settings (uses SMAppService).
- **Safe by default.** Nothing closes until you turn it on. Only normal close actions (the same as clicking the red button). Never force-quits.
- **Local and private.** No network, no accounts, no telemetry.

## Requirements

- macOS 15.0 or later
- Accessibility permission (the app prompts for it on first launch)

## Building

### Prerequisites

- Xcode 16+ with command-line tools
- [Homebrew](https://brew.sh)

### Setup

```bash
make bootstrap    # Install XcodeGen, Node (for XcodeBuildMCP), pinned SwiftLint + SwiftFormat
make generate     # Generate Xcode projects from project.yml
```

### Build and Test

```bash
make build        # Build the Swift package (all modules)
make test         # Run the test suite
make lint         # Check formatting and lint rules
make ci           # lint + test + build (what CI runs)
```

### Run

```bash
make run-app      # Build and launch the app (Apple Development signing)
```

The app requires Apple Development signing for local runs because Accessibility grants are bound to the code signature. Ad-hoc builds lose the grant on every rebuild.

## Release

`make release` builds a signed, notarized DMG for distribution.

### What the script does

1. Generates the Xcode project from `project.yml`.
2. Archives the app with Release configuration and Developer ID signing.
3. Exports the archive with `method: developer-id`.
4. Notarizes the app bundle, then staples the ticket.
5. Creates a DMG with the app and an Applications symlink.
6. Signs, notarizes, and staples the DMG.
7. Outputs `build/release/WindowCleaner-<version>.dmg`.

### Required setup

| Item | How to set up |
|---|---|
| Developer ID certificate | Install from Apple Developer portal into your keychain |
| Notarytool keychain profile | `xcrun notarytool store-credentials "notarytool-password-scosman" --apple-id <email> --team-id B5L5M4B62J --password <app-specific-password>` |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `NOTARYTOOL_PROFILE` | `notarytool-password-scosman` | Keychain profile name for `notarytool` |

## Architecture

All logic lives in the `Packages/WindowCleanerKit` Swift package. The app target (`App/`) is the composition root.

### Module DAG

```
L0  Engine            Pure domain: value types, port protocols, TrackerReducer, Planner
L0  Presentation      Formatters, rule summaries, MenuContentBuilder
L1  Persistence       SwiftData schema and Store
L1  SystemBridge      Live ports (CG, AX, NSWorkspace, SMAppService)
L2  AppCore           Orchestrator: event pump, executor, timer, pause, permissions
L3  SharedUI          AppIconView, SuggestionListView
L3  MenuBarUI         NSStatusItem + NSMenu rendering
L3  OnboardingUI      4-step first-launch flow
L3  SettingsUI        Sidebar settings with per-app rule editor
L3b AppShellUI        Main window root (onboarding vs. settings)
```

`AppCore` depends on port protocols in `Engine`, not on `SystemBridge`. The app target wires the live implementations.

### Key conventions

- Swift 6, strict concurrency, warnings-as-errors.
- No third-party dependencies.
- Tests use Swift Testing (`import Testing`), not XCTest.
- `os.Logger` with subsystem `net.scosman.windowcleaner`.

## Development

### Makefile targets

| Target | Description |
|---|---|
| `make bootstrap` | Install dev tools |
| `make generate` | Generate Xcode projects |
| `make build` | Build the SPM package |
| `make test` | Run package tests |
| `make lint` | Check formatting + lint |
| `make format` | Auto-format |
| `make precommit-checks` | format + lint + test |
| `make build-app` | Build both apps via xcodebuild (ad-hoc) |
| `make run-app` | Build and run the app |
| `make run-manual-tests` | Build and run ManualTestApp |
| `make release` | Archive, notarize, and package a release DMG |
| `make ci` | lint + test + build |
| `make hooks` | Enable pre-commit hook |
| `make clean` | Remove build artifacts |

### Pre-commit hook

```bash
make hooks        # Enable the opt-in hook
```

The hook runs `make precommit-checks` (format + lint + test) before each commit.

### CI

CI runs on GitHub Actions (`macos-15` runner):

- **package-tier** (gating): `make ci`
- **app-tier** (non-gating): `make build-app`
- **manual-tests-check** (non-gating): `make manual-tests-check`
