# Window Enumeration, Identity, and Closing

## Bottom Line

Squeegee can list all windows (including minimized, hidden, and other-Space windows) using `CGWindowListCopyWindowInfo(.optionAll, ...)` with no special permission. Each window gets a `CGWindowID` that is stable for the window's entire lifetime -- suitable as an identity key over hours. To close a specific window, use the Accessibility API: get the window's `kAXCloseButtonAttribute` and perform `AXPressAction` on it -- this is equivalent to the user clicking the red close button, triggers normal save dialogs, and does not quit the app. Bridging between CGWindowID and AXUIElement requires the private `_AXUIElementGetWindow` function, which is used by every major macOS window manager (AltTab, Hammerspoon, Rectangle) and has been stable across all macOS versions through macOS 26. No API provides window creation time; the best approach is to record "first seen" timestamps via periodic polling plus `kAXWindowCreatedNotification`.

## Key Findings

- **CGWindowListCopyWindowInfo needs no permission for enumeration** -- window ID, bounds, owner PID/name, layer, and on-screen status are all available without Screen Recording. Only `kCGWindowName` (title) and `kCGWindowSharingState` require Screen Recording permission. Since macOS 15 Sequoia, Screen Recording re-prompts monthly, making it a significant UX burden to avoid. [Apple docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)), [Ryan Thomson analysis](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess)

- **CGWindowID is stable for window lifetime** -- it does not change across moves, resizes, Space changes, full-screen, minimize, or hide. Reuse is theoretically possible (uint32_t counter) but practically negligible within a session. [Peekaboo docs](https://peekaboo.sh/focus.html), [CGWindow.h header](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h)

- **Closing a window via Accessibility works reliably** -- `kAXCloseButtonAttribute` + `AXPressAction` on the close button is equivalent to user clicking the red button. Apps with unsaved changes show their normal save dialog. The app keeps running. Requires Accessibility permission (one-time, no re-prompt). [Apple docs](https://developer.apple.com/documentation/applicationservices/kaxclosebuttonattribute), [t8r.tech analysis](https://t8r.tech/t/macos-accessibility-ui-tree)

- **`_AXUIElementGetWindow` bridges CGWindowID and AXUIElement** -- private API, declared as `extern AXError _AXUIElementGetWindow(AXUIElementRef, CGWindowID*)`. Used by AltTab, Hammerspoon, and every major window manager. Stable across macOS 10.5 through 26. Risk: cannot be used in Mac App Store apps (but irrelevant for Developer ID distribution). [Hammerspoon #1469](https://github.com/Hammerspoon/hammerspoon/issues/1469), [withfig/challenge-window-events](https://github.com/withfig/challenge-window-events)

- **No window creation time API exists** -- confirmed by exhaustive review of CGWindowList keys and AXUIElement attributes. Infer "opened at" via first-observation polling plus `kAXWindowCreatedNotification` for new windows. `NSRunningApplication.launchDate` provides app launch time as a rough proxy. [CGWindow.h keys](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h)

- **Tabs are not separate windows** -- in `CGWindowListCopyWindowInfo`, a Safari window with 50 tabs is one window. Xcode exposes tab-like helper windows but these are not standard. AltTab's tab detection uses complex AX notification heuristics and is unreliable. Squeegee should operate at the window level, not the tab level. [AltTab #1540](https://github.com/lwouis/alt-tab-macos/issues/1540), [SO: dummy windows](https://stackoverflow.com/questions/58453011)

- **Close (window) vs. Quit (app) are separate operations** -- `AXPress` on close button closes one window; `NSRunningApplication.terminate()` quits the whole app gracefully (save dialogs); `.forceTerminate()` kills without dialogs. AppleScript `close window` works but requires per-app Automation permission prompts, making it impractical. [close-vs-quit.md](./close-vs-quit.md)

## Details

- [cgwindowlist-enumeration.md](./cgwindowlist-enumeration.md) -- CGWindowListCopyWindowInfo fields, options, what requires Screen Recording permission, macOS 15 re-prompt changes. Read this for the full list of available window metadata.
- [accessibility-api-windows.md](./accessibility-api-windows.md) -- AXUIElement window listing, close button mechanics, `_AXUIElementGetWindow` bridge with code examples and risk assessment. Read this for the close-window implementation approach.
- [window-identity-lifecycle.md](./window-identity-lifecycle.md) -- CGWindowID stability, reuse, behavior with tabs/Spaces/full-screen/minimized/hidden, and approaches for inferring window creation time. Read this for identity tracking design decisions.
- [close-vs-quit.md](./close-vs-quit.md) -- Comparison of all close/quit methods (AXPress, NSRunningApplication, AppleScript, kill signals) with permission implications and recommendation. Read this for the close-action design decision.

## Open Questions / Gaps

- **CGWindowID reuse policy is undocumented.** I could not find an Apple source confirming whether/when IDs are reused. Practical observation and the uint32_t counter space strongly suggest reuse is negligible within a session, but there is no guarantee.
- **`_AXUIElementGetWindow` on macOS 26 (Tahoe):** I confirmed it is used by current (2025-2026) tools and no breakage has been reported, but I did not find a source that tested it specifically on macOS 26. The risk is low but non-zero.
- **AXPress behavior when the app is unresponsive:** If the target app hangs, `AXUIElementPerformAction` will time out (default 10 seconds, configurable via `AXUIElementSetMessagingTimeout`). What the user sees in that case needs testing.

## Sources

- [Apple: CGWindowListCopyWindowInfo documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) -- authoritative for function signature and available dictionary keys (macOS 10.5+)
- [Apple: AXUIElement.h documentation](https://developer.apple.com/documentation/applicationservices/axuielement_h) -- authoritative for accessibility API functions (macOS 10.2+)
- [Apple: kAXCloseButtonAttribute](https://developer.apple.com/documentation/applicationservices/kaxclosebuttonattribute) -- authoritative for close button attribute
- [CGWindow.h header (MacOSX SDK)](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h) -- primary source for all window list keys and CGWindowID definition
- [Ryan Thomson: Screen Recording Permissions in Catalina are a Mess](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess) -- best analysis of what is redacted without Screen Recording (2019)
- [TidBITS: Sequoia Screen Recording Prompts](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts) -- macOS 15 monthly re-prompt details (Sep 2024)
- [iDownloadBlog: macOS Sequoia 15.1 fewer prompts](https://www.idownloadblog.com/2024/10/09/macos-sequoia-15-1-macos-screen-recording-prompts-frequency-reduced) -- 15.1 reduced frequency (Oct 2024)
- [Peekaboo focus docs](https://peekaboo.sh/focus.html) -- confirms CGWindowID stability for window lifetime
- [Hammerspoon issue #1469](https://github.com/Hammerspoon/hammerspoon/issues/1469) -- _AXUIElementGetWindow extern declaration
- [withfig/challenge-window-events](https://github.com/withfig/challenge-window-events) -- _AXUIElementGetWindow usage and risk notes
- [AltTab issue #1540](https://github.com/lwouis/alt-tab-macos/issues/1540) -- tab detection complexity
- [SO: CGWindowListCopyWindowInfo and AXUIElement](https://stackoverflow.com/questions/11251700) -- no public API to bridge CGWindowID and AXUIElement
- [SO: Separating real and dummy windows](https://stackoverflow.com/questions/58453011) -- filtering real windows from CGWindowList
- [SO: Detecting screen recording on Catalina](https://stackoverflow.com/questions/56597221) -- kCGWindowName omission without permission
- [Skilly: Enable screen recording on macOS](https://tryskilly.app/learn/enable-screen-recording-permission-macos) -- macOS Tahoe 26 weekly re-prompt (verified Apr 2026)
- [t8r.tech: macOS accessibility UI tree automation](https://t8r.tech/t/macos-accessibility-ui-tree) -- AXPress reliability and close button best practices
- [The Robservatory: app launch time](https://robservatory.com/see-the-launch-date-and-time-for-any-app-or-process) -- NSRunningApplication.launchDate and lsappinfo
- [objc2-app-kit: NSRunningApplication](https://docs.rs/objc2-app-kit/latest/x86_64-unknown-linux-gnu/objc2_app_kit/struct.NSRunningApplication.html) -- terminate() and forceTerminate() behavior
- [Scripting OS X: Avoiding AppleScript Security](https://scriptingosx.com/2020/09/avoiding-applescript-security-and-privacy-requests) -- per-app Automation permission prompts
