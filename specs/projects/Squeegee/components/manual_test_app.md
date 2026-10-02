---
status: complete
---

# Component: ManualTestApp and ManualTestKit

This is a human-run harness for behavior that unit tests cannot cover: real windows, real Accessibility, real TCC. It copies Biscotti's design (architecture.md §10). Its results are committed to the repo. A non-gating CI job goes red until every recordable step has a result.

## 1. ManualTestKit (package module, pure, unit-tested)

This is a copy of Biscotti's `ManualTestKit`, adapted to this project:

- `TestScript { id, title, steps: [TestStep] }`.
- `TestStep`:
  - `.instruction(id:text:)` (not recorded)
  - `.action(id:label:run:)`
  - `.humanQuestion(id:prompt:)`
  - `.autoCheck(id:label:check:)`
- `TestStatus` (`pass | fail | not-run`), `TestResult { stepID, status, note?, timestamp? }` (Codable).
- `ResultsStore(fileURL:)`: `load`, `save` (pretty-printed, sorted keys, ISO 8601 dates), `record`, `markScriptNotRun`, `recordableStepIDs`, and `unrun(in:)`.
- `allScripts: [TestScript]` is the canonical registry for the app tabs and the gate.
- The executable target `manual-tests-check <results.json>` exits 0 if every recordable step has `pass` or `fail`, 1 if any are missing or `not-run`, and 2 on a usage or read error.

Action and auto-check closures in the scripts are placeholders. `ManualTestApp/Sources/WiredScripts.swift` replaces them with real `SystemBridge` calls, so ManualTestKit stays free of system dependencies (Biscotti pattern).

## 2. ManualTestApp (XcodeGen app)

- Bundle ID `net.scosman.squeegee.manualtest`. It is not sandboxed and uses hardened runtime.
- **Signing:** Apple Development (team `B5L5M4B62J`) for `make run-manual-tests`, so the Accessibility grant survives rebuilds. CI builds it ad-hoc (`make build-app`).
- Its scheme passes `SRCROOT` as an env var. The app writes `$SRCROOT/Results/manual_test_results.json` (Biscotti resolution order: `MANUAL_TEST_RESULTS_PATH`, then `$SRCROOT/Results/…`, then `~/Documents`).
- **UI:** a `TabView` with one tab per script (`ScriptRunnerView` and `StepView`, as in Biscotti). There is also a **Live Inspector** tab (not recorded): a table of the current `CGWindowLister` output joined with `AXWindowService.inspect` metadata, the frontmost app, the focused window ID, and a log of `FocusSignal` and `WorkspaceEvent` events with timestamps. This is the main debugging view for the system layer. It has a **Monitor** toggle that runs a small stand-alone loop built only from `SystemBridge` ports: a 60 s `CGWindowLister` scan (stopped while displays sleep), the `FrontmostFocusObserver` moved on each app activation, and an inspect of the previous app on each activation. It has the same shape as the `AppCore` event pump, but no engine logic, so the harness can run before `AppCore` exists (implementation plan Phase 2).
- It depends on `SystemBridge`, `Engine`, and `ManualTestKit`. It uses the real live ports, never copies.

## 3. Scripts

Step ID prefix `sb_` (SystemBridge). **Staleness rule:** any change to `Packages/SqueegeeKit/Sources/SystemBridge` sets all `sb_*` steps to `not-run` (hand-edit, or `ResultsStore.markScriptNotRun`).

### 3.1 `sb_setup` — Permissions and bridge

| Step | Type | Content |
|---|---|---|
| `sb_setup_intro` | instruction | "Run `tccutil reset Accessibility net.scosman.squeegee.manualtest` first. Note the macOS version in the notes of the next step." |
| `sb_bridge_available` | autoCheck | `AXWindowService.isBridgeAvailable == true`; the detail shows the macOS version |
| `sb_permission_prompt` | action + humanQuestion | Call `requestPrompt()`. "Did the system prompt appear, and did System Settings open at Accessibility?" |
| `sb_permission_notification` | humanQuestion | "Turn the ManualTestApp on in Accessibility while this app is in the background. Did the event log show a `permission changed` entry, and does the status show Granted, **without** switching back to this app?" |
| `sb_permission_revoke` | humanQuestion | "Turn it off. Did the status change to Denied within 2 s?" |

### 3.2 `sb_enum` — Enumeration and identity

| Step | Type | Content |
|---|---|---|
| `sb_enum_matches` | humanQuestion | "Open 2 Finder windows, 1 Preview document, and 1 TextEdit document. Does the Live Inspector list exactly these as standard windows, plus other apps' real windows, and no panels or helpers?" |
| `sb_enum_minimized` | humanQuestion | "Minimize a Finder window. Is it still listed, with `isMinimized = true` and the same window ID?" |
| `sb_enum_other_space` | humanQuestion | "Move a TextEdit window to Space 2 and come back to Space 1. Is it still listed by the CG scan with the same ID? Is it absent from a fresh AX inspect of TextEdit?" (This confirms the research claim about the Space limit.) |
| `sb_enum_fullscreen` | humanQuestion | "Make a Preview window full screen, then return to the desktop. Is it listed with the same ID?" |
| `sb_enum_titles` | humanQuestion | "Are the titles shown for current-Space windows, with **no** Screen Recording prompt?" |

### 3.3 `sb_focus` — Focus events

| Step | Type | Content |
|---|---|---|
| `sb_focus_events` | humanQuestion | "Click between 2 Finder windows, then 2 Preview windows, then 2 Safari windows, then 2 windows of an Electron app (Slack, VS Code, or similar). Did each click log `focusMayHaveChanged`, and did the resolved focused window ID match the clicked window every time?" |
| `sb_focus_app_switch` | humanQuestion | "Cmd-Tab between apps. Does every switch log `appActivated`, then the focused window of the new app?" |
| `sb_focus_new_window` | humanQuestion | "Press Cmd-N in Finder. Was `windowCreated` logged, and did the new window appear in the inspector within 1 s?" |
| `sb_focus_launching_app` | humanQuestion | "Launch an app that is not running (e.g. Calculator), and click into its window at once. Was the observer registered (possibly after a retry, shown in the log), and was focus reported?" |
| `sb_focus_sleep` | humanQuestion | "Put the displays to sleep (Ctrl-Shift-Eject, or the hot corner), wait 10 s, and wake them. Were `displaysSlept` and `displaysWoke` logged?" |

### 3.4 `sb_close` — Closing

| Step | Type | Content |
|---|---|---|
| `sb_close_standard` | action + humanQuestion | Select a Finder window in the inspector and press **Close**. "Did only that window close, and did the result show `pressed(wasListed: true)`?" |
| `sb_close_unsaved` | humanQuestion | "Type text in a new TextEdit document (unsaved) and close it from the inspector. Did the save sheet appear, did the window stay open, and did the result still show `pressed`?" |
| `sb_close_minimized` | humanQuestion | "Close a minimized Preview window from the inspector. Did it close without restoring first?" |
| `sb_close_other_space` | humanQuestion | "Inspect a TextEdit window while it is on Space 1 (so its element is cached). Move it to Space 2, return to Space 1, and close it from the inspector. Did it close? Record `wasListed` in the notes." (**This decides design option A.** Either outcome is handled by the engine; the result is recorded for the docs.) |
| `sb_close_fullscreen` | humanQuestion | "Close a full-screen Preview window from the inspector (while you are on another Space, and then while on its Space). Record the outcomes." |
| `sb_close_tabs` | humanQuestion | "Open a Finder window with 3 tabs and close it from the inspector. What happened (all tabs closed / one tab / a prompt)? Record it in the notes." |
| `sb_close_hung_app` | humanQuestion | "Open TextEdit, run `kill -STOP <pid>` (the pid is shown in the inspector), and close its window from the inspector. Did the call return within about 1 s, with `failed` or `unreachable`, and did the ManualTestApp UI stay responsive? Then run `kill -CONT <pid>`." |
| `sb_close_no_button` | humanQuestion | "Open a panel window (for example Font panel via Cmd-T in TextEdit). Is it absent from the standard windows (or marked non-standard)?" |

### 3.5 `sb_urls` — Document URLs (for Reopen)

| Step | Type | Content |
|---|---|---|
| `sb_document_urls` | humanQuestion | "Open a Finder window at ~/Downloads, a PDF in Preview, a movie in QuickTime Player, and a file in TextEdit. Record which ones show a file URL in the inspector." |
| `sb_reopen` | action + humanQuestion | Close each window from the inspector, then call `LiveAppOpener.open(documentURL:withBundleID:)` with the captured URLs. "Did each reopen in the correct app (Finder in a new window)?" |

### 3.6 `sb_quit` — Quit

| Step | Type | Content |
|---|---|---|
| `sb_quit_normal` | action + humanQuestion | Terminate QuickTime Player (no windows open) through `LiveAppTerminator`. "Did it quit normally?" |
| `sb_quit_unsaved` | humanQuestion | "Terminate TextEdit that has an unsaved document. Did it show its save prompt (not force-quit)?" |

### 3.7 `sb_login_item_script` — Login Item

| Step | Type | Content |
|---|---|---|
| `sb_login_item` | action + humanQuestion | `LiveLoginItem.setEnabled(true)` on the ManualTestApp. "Did it appear in System Settings → General → Login Items? Then disable it: did it go away?" |

### 3.8 `sb_scan` — Installed apps

| Step | Type | Content |
|---|---|---|
| `sb_installed_apps` | autoCheck + humanQuestion | Run `LiveInstalledAppScanner`, then check that `com.apple.finder` and `com.apple.Preview` are present. "Does the list include your third-party apps from /Applications (spot-check 3)?" |

## 4. After the hardware pass

The hardware pass is a **checkpoint** between implementation Phase 2 and Phase 3. Nothing after Phase 2 starts until it is done.

The person who runs the tests records the results and notes. The notes of the decision steps (`sb_close_other_space`, `sb_close_tabs`, `sb_document_urls`, `sb_focus_events`) are copied into a short `specs/projects/Squeegee/hardware_findings.md` in the same PR. If a finding changes the design (for example, the close-on-another-Space behavior, focus events, or document URLs), update engine.md / system_layer.md **before** Phase 3 starts. If a contingency is triggered (architecture.md §11), add it to the plan before Phase 3.
