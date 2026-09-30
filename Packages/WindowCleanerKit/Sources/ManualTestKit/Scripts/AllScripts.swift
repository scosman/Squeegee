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
            text: "Before you start, run this command in Terminal:\n"
                + "tccutil reset Accessibility net.scosman.windowcleaner.manualtest\n"
                + "This removes any saved Accessibility permission so the prompt tests work. "
                + "Write the macOS version number in the notes of the next step."
        ),
        .autoCheck(
            id: "sb_bridge_available",
            label: "Check that the system window API is available on this macOS version"
        ) {
            // Placeholder — wired by ManualTestApp with real AXWindowService check
            CheckOutcome(passed: false, detail: "Not wired")
        },
        .action(
            id: "sb_permission_prompt_action",
            label: "Open the Accessibility permission dialog"
        ) { _ in
            // Placeholder — wired by ManualTestApp with real requestPrompt() call
        },
        .humanQuestion(
            id: "sb_permission_prompt",
            prompt: "Did a system dialog appear asking for Accessibility access? "
                + "Did System Settings open to the Accessibility page?"
        ),
        .humanQuestion(
            id: "sb_permission_notification",
            prompt: "Switch away from this app, then turn the ManualTestApp toggle ON in "
                + "System Settings > Privacy & Security > Accessibility. Without switching "
                + "back to this app: does the event log (Live Inspector tab) show a "
                + "'permission changed' entry, and does the toolbar show 'Granted'?"
        ),
        .humanQuestion(
            id: "sb_permission_revoke",
            prompt: "Turn the ManualTestApp toggle OFF in System Settings. "
                + "Did the toolbar status change to 'Denied' within 2 seconds?"
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
                + "Go to the Live Inspector tab. Does the window list show exactly these "
                + "windows with a 'standard' badge, plus other apps' real windows? "
                + "Panels, helpers, and menu bar items should NOT appear."
        ),
        .humanQuestion(
            id: "sb_enum_minimized",
            prompt: "Minimize a Finder window to the Dock. Does it still appear in the "
                + "Live Inspector window list with a 'minimized' badge and the same window ID?"
        ),
        .humanQuestion(
            id: "sb_enum_other_space",
            prompt: "Move a TextEdit window to Space 2 and come back to Space 1. "
                + "Is the TextEdit window still shown in the window list with the same ID? "
                + "(It may lose its title or metadata — that is expected for windows on "
                + "another Space.)"
        ),
        .humanQuestion(
            id: "sb_enum_fullscreen",
            prompt: "Make a Preview window full screen (green button), then swipe back to "
                + "the desktop. Is it still shown in the window list with the same ID? "
                + "Note any extra window IDs that appear for the same app."
        ),
        .humanQuestion(
            id: "sb_enum_titles",
            prompt: "Are window titles shown for windows on the current Space? "
                + "Did macOS prompt you for Screen Recording permission? (It should NOT.)"
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
                + "For each click: did the event log show 'focusMayHaveChanged', and did "
                + "the 'Focused' window ID in the toolbar match the window you clicked?"
        ),
        .humanQuestion(
            id: "sb_focus_app_switch",
            prompt: "Use Cmd-Tab to switch between apps. Does every switch show "
                + "'appActivated' in the event log, followed by the focused window ID "
                + "of the new app in the toolbar?"
        ),
        .humanQuestion(
            id: "sb_focus_new_window",
            prompt: "Press Cmd-N in Finder to open a new window. Did 'windowCreated' "
                + "appear in the event log? Did the new window appear in the window list "
                + "within 1 second?"
        ),
        .humanQuestion(
            id: "sb_focus_launching_app",
            prompt: "Quit an app (e.g. Calculator), then relaunch it and click its window "
                + "immediately. Did the event log show the observer registered (possibly "
                + "after a retry), and was the focused window ID reported?"
        ),
        .humanQuestion(
            id: "sb_focus_sleep",
            prompt: "Put the displays to sleep (Ctrl-Shift-Eject or a hot corner), wait "
                + "10 seconds, and wake them. Did the event log show 'displaysSlept' "
                + "and 'displaysWoke'?"
        )
    ]
)

private let closeScript = TestScript(
    id: "sb_close",
    title: "Closing",
    steps: [
        .action(
            id: "sb_close_standard_action",
            label: "Close one Finder window (open a Finder window first, then click Run)"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_close_standard",
            prompt: "Did only that one Finder window close? Does the 'Last close' line "
                + "show 'pressed' with 'wasListed: true'?"
        ),
        .humanQuestion(
            id: "sb_close_unsaved",
            prompt: "Open TextEdit and type some text (do not save). Select that TextEdit "
                + "window in the Live Inspector and click Close. Did a save dialog appear? "
                + "Did the window stay open? Does the result still show 'pressed'?"
        ),
        .humanQuestion(
            id: "sb_close_minimized",
            prompt: "Minimize a Preview window to the Dock. Select it in the Live Inspector "
                + "and click Close. Did it close without restoring from the Dock first?"
        ),
        .humanQuestion(
            id: "sb_close_other_space",
            prompt: "Open a TextEdit window on Space 1 so the Live Inspector sees it. "
                + "Move that window to Space 2, come back to Space 1, and click Close "
                + "in the inspector. Did the window close on Space 2? "
                + "Record the 'wasListed' value from the result line."
        ),
        .humanQuestion(
            id: "sb_close_fullscreen",
            prompt: "Make a Preview window full screen. Run this test twice:\n"
                + "1) From another Space: select the full-screen window in the inspector "
                + "and click 'Close in 5 s', then swipe to a different Space before the "
                + "5 seconds elapse. Record the result.\n"
                + "2) From the window's own Space: select the full-screen window in the "
                + "inspector and click 'Close in 5 s', then swipe to the full-screen "
                + "window's Space before the 5 seconds elapse. Record the result.\n"
                + "Write both outcomes in the notes."
        ),
        .humanQuestion(
            id: "sb_close_tabs",
            prompt: "Open a Finder window with 3 tabs (Cmd-T to add tabs). In the Live "
                + "Inspector, each tab appears as its own window row. Select one tab's row "
                + "and click Close. Did only that one tab close, leaving the other tabs open?"
        ),
        .humanQuestion(
            id: "sb_close_hung_app",
            prompt: "Open TextEdit. Note its pid shown in the Live Inspector. In Terminal, "
                + "run: kill -STOP <pid> (this freezes TextEdit). Select the TextEdit window "
                + "in the inspector and click Close. Did the close return within about 1 second "
                + "with 'failed' or 'unreachable'? Did the ManualTestApp stay responsive? "
                + "Then run: kill -CONT <pid> to unfreeze TextEdit."
        ),
        .humanQuestion(
            id: "sb_close_no_button",
            prompt: "Open a panel window (e.g. Cmd-T in TextEdit opens the Font panel). "
                + "Is the panel absent from the window list, or marked 'non-standard'?"
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
                + "QuickTime Player, and a file in TextEdit. In the Live Inspector, which "
                + "windows show a file path (blue text) below the title? Record which apps "
                + "do and do not show a URL."
        ),
        .action(
            id: "sb_reopen_action",
            label: "Reopen documents captured from previously closed windows"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_reopen",
            prompt: "Did each document reopen in the correct app?"
        )
    ]
)

private let quitScript = TestScript(
    id: "sb_quit",
    title: "Quit",
    steps: [
        .action(
            id: "sb_quit_normal_action",
            label: "Send a Quit command to QuickTime Player (launch it first with no open windows)"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_quit_normal",
            prompt: "Did QuickTime Player quit normally? (If it was not running, click Run "
                + "above — it will launch QuickTime Player. Wait a moment, then click Run "
                + "again to send the quit command.)"
        ),
        .humanQuestion(
            id: "sb_quit_unsaved",
            prompt: "Open TextEdit with unsaved text. Right-click TextEdit in the Dock and "
                + "choose Quit. Did TextEdit show its save dialog instead of force-quitting?"
        )
    ]
)

private let runtimeScript = TestScript(
    id: "sb_runtime",
    title: "Timers and Energy",
    steps: [
        .action(
            id: "sb_timer_latency_action",
            label: "Start 5 countdown timers at +2, +5, +10, +20, and +30 minutes"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_timer_latency",
            prompt: "Hide the ManualTestApp (Cmd-H) and leave the Mac awake and idle. "
                + "After 30 minutes, come back to this tab. It shows how late each timer "
                + "fired. Were all timers late by less than 60 seconds?"
        ),
        .humanQuestion(
            id: "sb_energy",
            prompt: "First, go to the Live Inspector tab and set the scan interval to 60 s "
                + "(this is the production cadence — the 1 s default is for debugging only). "
                + "Turn the Monitor on, hide the ManualTestApp (Cmd-H), and use the Mac "
                + "normally for 10 minutes. Then check Activity Monitor > Energy. "
                + "Is 'Avg Energy Impact' near 0 and CPU near 0%?"
        ),
        .action(
            id: "sb_login_item_action",
            label: "Register this app as a Login Item (opens at login)"
        ) { _ in
            // Placeholder — wired by ManualTestApp
        },
        .humanQuestion(
            id: "sb_login_item",
            prompt: "Did the ManualTestApp appear in System Settings > General > Login Items? "
                + "Turn it off there — did it disappear?"
        )
    ]
)

private let scanScript = TestScript(
    id: "sb_scan",
    title: "Installed Apps",
    steps: [
        .autoCheck(
            id: "sb_installed_apps_check",
            label: "Scan for installed apps and verify Finder and Preview are found"
        ) {
            // Placeholder — wired by ManualTestApp
            CheckOutcome(passed: false, detail: "Not wired")
        },
        .humanQuestion(
            id: "sb_installed_apps",
            prompt: "Review the app list shown above after running the check. "
                + "Do you see your third-party apps from /Applications? Spot-check at least 3."
        )
    ]
)
