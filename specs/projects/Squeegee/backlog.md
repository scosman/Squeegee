# Backlog

- [x] **Finish the hardware checkpoint.** Timer latency and energy steps removed (replaced by the perf benchmark). Login item steps (`sb_login_item_action`, `sb_login_item`) run and passed.
- [x] **Sidebar collapse button removed from Settings.** Fixed by disabling SwiftUI toolbar bridging (`sceneBridgingOptions = []`) and installing an AppKit-owned empty `NSToolbar` with `.unified` style for the visual.
- [ ] **~2 s frozen outline / slow render on Cmd-Tab to the Settings window.** Root cause not found. Not proven to be the `.accessory`→`.regular` policy switch. Needs evidence (`sample` during activation, DEBUG `SelfCheck` timing logs).
- [ ] **Menu bar menu stuck on "Finder – closing…" indefinitely** after Finder windows closed on time; Settings Open Windows correctly shows none. Root cause not found; only a safety net (`resolveStaleCloses`) and retained verification timers were added. Scenario test 49 passes, so the fault is in the live path. Needs the live `[selfcheck]`/log evidence.
- [ ] **Not verified on hardware after the last changes:** Settings comes to the front on the first open from the menu (`NSApp.activate(ignoringOtherApps:)` deferred); the Remove Rule custom sheet has no app icon; Pause State dropdown width; Running Apps current on each "+" click; Open Windows "+" rows; picker subtitles; Cmd-Q closes the window; no crash on second Settings open.
- [ ] **`updateBounds` is never called.** Nothing calls `updateBounds`, so the bounds-match fallback for window ID resolution never works. Discovered during the perf project; not in scope for that work.
