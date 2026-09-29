// The canonical registry of all manual test scripts. ManualTestApp's WiredScripts
// replaces the placeholder closures with real SystemBridge calls.

/// All manual test scripts. The CI gate and the ManualTestApp both use this list.
public let allScripts: [TestScript] = [
    setupScript,
    enumScript,
    focusScript,
    closeScript,
    urlsScript,
    quitScript,
    runtimeScript,
    scanScript
]

private let setupScript = TestScript(
    id: "sb_setup",
    title: "Setup",
    steps: [
        .instruction(
            id: "sb_setup_intro",
            text: "Run `tccutil reset Accessibility net.scosman.windowcleaner.manualtest` first. "
                + "Note the macOS version in the notes of the next step."
        ),
        .autoCheck(
            id: "sb_bridge_available",
            label: "Check that the private window ID bridge is available"
        ) {
            // Placeholder — wired by ManualTestApp with real AXWindowService check
            CheckOutcome(passed: false, detail: "Not wired")
        },
        .action(
            id: "sb_permission_prompt_action",
            label: "Request Accessibility permission prompt"
        ) { _ in
            // Placeholder — wired by ManualTestApp with real requestPrompt() call
        },
        .humanQuestion(
            id: "sb_permission_prompt",
            prompt: "Did the system prompt appear, and did System Settings open at Accessibility?"
        ),
        .humanQuestion(
            id: "sb_permission_notification",
            prompt: "Turn the ManualTestApp on in Accessibility while this app is in the background. "
                + "Did the event log show a `permission changed` entry, and does the status show "
                + "Granted, without switching back to this app?"
        ),
        .humanQuestion(
            id: "sb_permission_revoke",
            prompt: "Turn it off. Did the status change to Denied within 2 s?"
        )
    ]
)

private let enumScript = TestScript(
    id: "sb_enum",
    title: "Enumeration",
    steps: [
        .humanQuestion(
            id: "sb_enum_matches",
            prompt: "Open 2 Finder windows, 1 Preview document, and 1 TextEdit document. "
                + "Does the Live Inspector list exactly these as standard windows, plus other "
                + "apps' real windows, and no panels or helpers?"
        ),
        .humanQuestion(
            id: "sb_enum_minimized",
            prompt: "Minimize a Finder window. Is it still listed, with `isMinimized = true` "
                + "and the same window ID?"
        ),
        .humanQuestion(
            id: "sb_enum_other_space",
            prompt: "Move a TextEdit window to Space 2 and come back to Space 1. Is it still "
                + "listed by the CG scan with the same ID? Is it absent from a fresh AX inspect "
                + "of TextEdit?"
        ),
        .humanQuestion(
            id: "sb_enum_fullscreen",
            prompt: "Make a Preview window full screen, then return to the desktop. Is it listed "
                + "with the same ID?"
        ),
        .humanQuestion(
            id: "sb_enum_titles",
            prompt: "Are the titles shown for current-Space windows, with no Screen Recording prompt?"
        )
    ]
)

private let focusScript = TestScript(
    id: "sb_focus",
    title: "Focus Events",
    steps: [
        .humanQuestion(
            id: "sb_focus_events",
            prompt: "Click between 2 Finder windows, then 2 Preview windows, then 2 Safari "
                + "windows, then 2 windows of an Electron app (Slack, VS Code, or similar). "
                + "Did each click log `focusMayHaveChanged`, and did the resolved focused "
                + "window ID match the clicked window every time?"
        ),
        .humanQuestion(
            id: "sb_focus_app_switch",
            prompt: "Cmd-Tab between apps. Does every switch log `appActivated`, then the "
                + "focused window of the new app?"
        ),
        .humanQuestion(
            id: "sb_focus_new_window",
            prompt: "Press Cmd-N in Finder. Was `windowCreated` logged, and did the new "
                + "window appear in the inspector within 1 s?"
        ),
        .humanQuestion(
            id: "sb_focus_launching_app",
            prompt: "Launch an app that is not running (e.g. Calculator), and click into its "
                + "window at once. Was the observer registered (possibly after a retry, shown "
                + "in the log), and was focus reported?"
        ),
        .humanQuestion(
            id: "sb_focus_sleep",
            prompt: "Put the displays to sleep (Ctrl-Shift-Eject, or the hot corner), wait "
                + "10 s, and wake them. Were `displaysSlept` and `displaysWoke` logged?"
        )
    ]
)

private let closeScript = TestScript(
    id: "sb_close",
    title: "Closing",
    steps: [
        .action(
            id: "sb_close_standard_action",
            label: "Select a Finder window in the inspector and press Close"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_close_standard",
            prompt: "Did only that window close, and did the result show "
                + "`pressed(wasListed: true)`?"
        ),
        .humanQuestion(
            id: "sb_close_unsaved",
            prompt: "Type text in a new TextEdit document (unsaved) and close it from the "
                + "inspector. Did the save sheet appear, did the window stay open, and did "
                + "the result still show `pressed`?"
        ),
        .humanQuestion(
            id: "sb_close_minimized",
            prompt: "Close a minimized Preview window from the inspector. Did it close "
                + "without restoring first?"
        ),
        .humanQuestion(
            id: "sb_close_other_space",
            prompt: "Inspect a TextEdit window while it is on Space 1 (so its element is "
                + "cached). Move it to Space 2, return to Space 1, and close it from the "
                + "inspector. Did it close? Record `wasListed` in the notes."
        ),
        .humanQuestion(
            id: "sb_close_fullscreen",
            prompt: "Close a full-screen Preview window from the inspector (while you are "
                + "on another Space, and then while on its Space). Record the outcomes."
        ),
        .humanQuestion(
            id: "sb_close_tabs",
            prompt: "Open a Finder window with 3 tabs and close it from the inspector. "
                + "What happened (all tabs closed / one tab / a prompt)? Record it in the notes."
        ),
        .humanQuestion(
            id: "sb_close_hung_app",
            prompt: "Open TextEdit, run `kill -STOP <pid>` (the pid is shown in the inspector), "
                + "and close its window from the inspector. Did the call return within about 1 s, "
                + "with `failed` or `unreachable`, and did the ManualTestApp UI stay responsive? "
                + "Then run `kill -CONT <pid>`."
        ),
        .humanQuestion(
            id: "sb_close_no_button",
            prompt: "Open a panel window (for example Font panel via Cmd-T in TextEdit). "
                + "Is it absent from the standard windows (or marked non-standard)?"
        )
    ]
)

private let urlsScript = TestScript(
    id: "sb_urls",
    title: "Document URLs",
    steps: [
        .humanQuestion(
            id: "sb_document_urls",
            prompt: "Open a Finder window at ~/Downloads, a PDF in Preview, a movie in "
                + "QuickTime Player, and a file in TextEdit. Record which ones show a file "
                + "URL in the inspector."
        ),
        .action(
            id: "sb_reopen_action",
            label: "Call LiveAppOpener.open(documentURL:withBundleID:) with the captured URLs"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_reopen",
            prompt: "Did each window reopen in the correct app (Finder in a new window)?"
        )
    ]
)

private let quitScript = TestScript(
    id: "sb_quit",
    title: "Quit",
    steps: [
        .action(
            id: "sb_quit_normal_action",
            label: "Terminate QuickTime Player (no windows open) through LiveAppTerminator"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_quit_normal",
            prompt: "Did QuickTime Player quit normally?"
        ),
        .humanQuestion(
            id: "sb_quit_unsaved",
            prompt: "Terminate TextEdit that has an unsaved document. Did it show its save "
                + "prompt (not force-quit)?"
        )
    ]
)

private let runtimeScript = TestScript(
    id: "sb_runtime",
    title: "Timers and Energy",
    steps: [
        .action(
            id: "sb_timer_latency_action",
            label: "Arm 5 one-shot LiveAppScheduler timers at +2, +5, +10, +20, and +30 min"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_timer_latency",
            prompt: "Hide the ManualTestApp (Cmd-H) and leave the Mac awake and idle. After "
                + "30 min, the tab shows the lateness of each timer. Were all timers late by "
                + "less than 60 s?"
        ),
        .humanQuestion(
            id: "sb_energy",
            prompt: "With the Live Inspector Monitor on and the app hidden for 10 min (use "
                + "the Mac normally during this time), does Activity Monitor -> Energy show "
                + "'Avg Energy Impact' near 0 and CPU near 0%?"
        ),
        .action(
            id: "sb_login_item_action",
            label: "Call LiveLoginItem.setEnabled(true) on the ManualTestApp"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_login_item",
            prompt: "Did it appear in System Settings -> General -> Login Items? "
                + "Then disable it: did it go away?"
        )
    ]
)

private let scanScript = TestScript(
    id: "sb_scan",
    title: "Installed Apps",
    steps: [
        .autoCheck(
            id: "sb_installed_apps_check",
            label: "Run LiveInstalledAppScanner and verify com.apple.finder and com.apple.Preview are present"
        ) {
            // Placeholder — wired by ManualTestApp
            CheckOutcome(passed: false, detail: "Not wired")
        },
        .humanQuestion(
            id: "sb_installed_apps",
            prompt: "Does the list include your third-party apps from /Applications (spot-check 3)?"
        )
    ]
)
