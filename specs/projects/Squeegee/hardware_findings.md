# Hardware Findings

Results of the hardware checkpoint (manual_test_app.md §4). Raw results: `ManualTestApp/Results/manual_test_results.json`.

- **Machine:** macOS 15.6.1 (24G90).
- **Date:** 2026-09-29.
- **Harness:** ManualTestApp at `539c6ad`.
- **Coverage:** All recordable steps have results. The one fail (`sb_document_urls`) is a finding, not a defect.

## Confirmed (no design change)

| Area | Steps | Result |
|---|---|---|
| Permission | `sb_bridge_available`, `sb_permission_*` | `_AXUIElementGetWindow` resolves. The prompt opens System Settings. Grant and revoke are detected while the app is in the background. |
| Enumeration | `sb_enum_matches`, `sb_enum_minimized`, `sb_enum_other_space`, `sb_enum_titles`, `sb_close_no_button` | The CG + AX filter lists exactly the real windows. Panels are excluded. Minimized and other-Space windows keep their IDs. Titles show with **no** Screen Recording prompt. |
| Focus | `sb_focus_*` (all 5) | Focus events are correct for AppKit, Safari, and Electron windows, app switches, new windows, launching apps (with retry), and display sleep/wake. The event-driven design holds. |
| Close | `sb_close_standard`, `sb_close_unsaved`, `sb_close_minimized`, `sb_close_hung_app` | Close presses the button. An unsaved document shows its save sheet and stays open. A minimized window closes without restore. A stopped (`SIGSTOP`) app does not block the call or the UI. |
| Close on another Space | `sb_close_other_space` | **Closes** through the kept element. Design option A works. (`wasListed` was not recorded.) |
| Close full screen | `sb_close_fullscreen` | Closes from another Space **and** from its own Space. |
| Reopen | `sb_reopen` | Captured document URLs reopen in the correct app. |
| Quit | `sb_quit_normal`, `sb_quit_unsaved` | Terminate quits normally. An app with an unsaved document shows its save prompt (no force quit). |
| Installed apps | `sb_installed_apps*` | 259 apps found, including Finder, Preview, and third-party apps. |

## Findings that change the spec

1. **Finder exposes no document URL** (`sb_document_urls`). Finder windows have a title but no URL. Preview and QuickTime Player have a URL. This is the planned contingency (architecture §11): Finder closures get no folder Reopen. As for any closure with no URL, Reopen launches the app (engine test 47). Updated: functional_spec §9 and §11 (Finder row), §15.
2. **Each native tab is its own window** (`sb_close_tabs`). A Finder window with 3 tabs shows as 3 window rows, and Close closes only that tab. So each tab has its own timer and is closed on its own. Updated: functional_spec §5.2.
3. **Full screen adds a window and hides metadata** (`sb_enum_fullscreen`). A window that goes full screen keeps its window ID. While the user is not on its Space, AX returns no title or URL for it (the Space limit). A second window ID also appears. No engine change:
   - The engine keeps the last known metadata for windows that AX omits (engine.md reducer rule "keep their old metadata").
   - The extra window stays at `metadata == nil` until AX lists it, so it gets no schedule and is never closed. Until then it counts as "present" for its app, which can only delay an "Always" quit. That is the safe direction.
   Updated: functional_spec §13 (full-screen row) and system_layer.md §2.

## Removed steps

The timer latency (`sb_timer_latency`) and energy (`sb_energy`) manual steps were removed. The perf benchmark (`make bench`) replaces them with deterministic, repeatable measurements.

Login item (`sb_login_item_action`, `sb_login_item`) was run and passed on 2026-10-02.
