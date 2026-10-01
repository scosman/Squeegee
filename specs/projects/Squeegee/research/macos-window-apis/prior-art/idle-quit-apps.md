# Idle-Quit and Auto-Close Apps for macOS

Deep reference on existing macOS apps that quit, hide, or close idle apps/windows. For each app: what it does, how, permissions, distribution, and problems.

---

## 1. Quitter (Marco Arment)

**What it does:** Menu bar utility that hides or quits apps after a user-configured period of inactivity. Works at the **app level** only -- no per-window control. Each monitored app gets a rule: "hide after N minutes" or "quit after N minutes." Default inactivity threshold is 10 minutes.

**How it measures inactivity:** Tracks which app is frontmost via `NSWorkspace.shared.frontmostApplication` and/or `NSWorkspace.didActivateApplicationNotification`. When a monitored app loses focus, a timer starts. If the app does not return to the foreground before the threshold, Quitter calls `NSRunningApplication.hide()` or `NSRunningApplication.terminate()`. Source is closed, but this is reliably inferred from behavior and from a [developer who rewrote it](https://medium.com/@solaris18/rewriting-quitter-for-the-modern-age-3b27d41709f2).

**Permissions:** Cannot be sandboxed -- `NSRunningApplication.terminate()` on other apps is not allowed in the App Sandbox. No Accessibility permission needed (frontmost-app tracking and terminate/hide use public AppKit/NSWorkspace APIs). No Screen Recording permission needed.

**Distribution:** Free download from [marco.org/apps](https://marco.org/apps). Not on the Mac App Store (cannot sandbox). Available via Homebrew (`brew install --cask quitter`). Version 1.0 Build 108 (last meaningful update ~2021). Universal Binary, requires macOS 10.10+.

**Current status (as of 2026):** Still works on macOS 15 Sequoia per user reports ([AppAddict review](https://appaddict.app/post/quitter-a-free-utility-that-works)). Marco has not actively maintained it; he re-signed it for code signing at some point but no feature development. Users on [Mac Power Users forum](https://talk.macpowerusers.com/t/alternative-to-quitter-app/22055) debated whether to keep using it vs. find an alternative, and most stuck with it.

**Known problems:**
- App-level only. If you have 15 Finder windows, Quitter can quit Finder (losing all windows) but cannot close one window.
- No notification before quitting -- users sometimes Cmd-Tab looking for an app that Quitter already closed.
- No "since opened" mode -- only "since last in foreground."
- One user reported it stopped hiding windows properly after a macOS update (possible TCC change, unconfirmed).
- Raycast added an "auto-quit" feature as an alternative, but users report it does not work reliably.

**Sources:**
- [Marco.org announcement (2016-05-02)](https://marco.org/2016/05/02/quitter)
- [How-To Geek walkthrough](https://www.howtogeek.com/268963/automatically-close-or-hide-idle-applications-on-your-mac-with-quitter/)
- [MPU Talk alternative thread](https://talk.macpowerusers.com/t/alternative-to-quitter-app/22055)
- [Homebrew formula](https://formulae.brew.sh/cask/quitter)

---

## 2. AutoQuit (treelazy888)

**What it does:** Menu bar app that automatically quits idle apps after a configurable timeout (default 8 hours, range 30 min to 48 hours). Per-app rules. Shows live countdown timer and per-app memory usage in a popover.

**How it measures inactivity:** Tracks when each app last lost focus. A `RunningAppsManager` checks the running app list approximately once per second. Skips apps that are playing media, downloading, or holding a Mac wake lock. Skips system apps, menu bar utilities, and background helpers.

**Quit mechanism:** Graceful quit by default, with a 60-second notification grace period offering "Keep" and "Quit now" buttons. Also has a "Force close" option.

**Permissions:** Not explicitly documented, but likely uses `NSWorkspace.didActivateApplicationNotification` for focus tracking (no special permission) and `NSRunningApplication.terminate()` for quitting (no sandbox allowed).

**Distribution:** Open source, GPL-3.0, on [GitHub](https://github.com/treelazy888/AutoQuit). Swift 5, SwiftUI. Requires macOS 13+. Actively maintained (v1.4.3 as of 2026). No dependencies, no telemetry.

**Strengths relative to Quitter:**
- Notification before quitting (grace period)
- Live countdown visible in the UI
- Skips busy apps (media, downloads, wake locks)
- Memory usage display
- Actively maintained

**Known problems:**
- Still app-level only -- no per-window control
- No "since opened" mode
- No "close window" option (only quit or nothing)

**Sources:**
- [GitHub repo](https://github.com/treelazy888/AutoQuit)
- [Release v1.4.3](https://github.com/treelazy888/AutoQuit/releases/tag/v1.4.3)

---

## 3. SwiftQuit (onebadidea)

**What it does:** Quits macOS apps when the user closes their last window (clicking the red close button or Cmd-W). Not idle-based -- it is event-based, triggering on window closure.

**How it detects window closure:** Uses Accessibility APIs to monitor window close events. Tracks the number of open windows per app and quits the app when the count reaches zero.

**Permissions:** Requires Accessibility permission. Not sandboxed.

**Distribution:** Open source, GPL-3.0, on [GitHub](https://github.com/onebadidea/swiftquit). Also at [swiftquit.com](https://swiftquit.com/). Available via Homebrew (`brew install --cask swift-quit`). Last official release v1.5 (March 2023). Several community forks exist.

**Known problems:**
- Apps that temporarily close their main window (e.g., Excel loading a file) get insta-quit ([issue #3](https://github.com/onebadidea/swiftquit/issues/3)). A delay-before-quitting feature was requested.
- Some apps retain hidden controller windows after their user-facing window closes, causing false negatives (app not quit). A fork checks the WindowServer for visible windows instead of relying on the AX client's cached list.
- After macOS 27 update, some apps (VSCode, Chrome) stopped closing properly ([issue #63](https://github.com/onebadidea/swiftquit/issues/63)).
- 27 open issues total, indicating maintenance gaps.
- "Some users have reported issues with unwanted closing of windows or other problems so use at your own risk" -- from README.

**Relevance to Squeegee:** Different goal (close-on-window-close vs. close-after-idle), but the Accessibility-based window-count tracking and the edge cases (hidden windows, temporary window closures) are instructive.

**Sources:**
- [GitHub repo](https://github.com/onebadidea/swiftquit)
- [Issue #3: delay before quitting](https://github.com/onebadidea/swiftquit/issues/3)
- [Issue #63: macOS 27 breakage](https://github.com/onebadidea/swiftquit/issues/63)

---

## 4. MacQuit

**What it does:** Menu bar utility. Primary feature is "quit all running apps" with one click. Also has auto-quit idle apps, CPU/memory monitoring, force quit for frozen apps, and app protection (exclude list, auto-protect music apps).

**How it measures idle time:** Uses an "AIR" (App Idle Recognition) algorithm. Apps exceeding an idle threshold (no user interaction) are automatically terminated using `NSRunningApplication` methods. Details of the AIR algorithm are not publicly documented.

**Permissions:** Not documented in search results. Likely Accessibility and/or `NSWorkspace` APIs.

**Distribution:** One-time purchase $4.99 on the Mac App Store (with free trial). Closed source.

**Known problems:** Limited public information. No open issues or user complaints found.

**Relevance to Squeegee:** The auto-quit feature is closest to Quitter's, but at app level only. The CPU/memory monitoring is a nice touch but not relevant to Squeegee's goals.

**Sources:**
- [Product Hunt page](https://www.producthunt.com/products/macquit)
- [AwesomeMacApp listing](https://www.awesomemacapp.com/app/macquit)

---

## 5. SmartQuit (luizcamargo)

**What it does:** Two combined features: (1) quit when last window closes (like SwiftQuit), and (2) auto-quit after inactivity timeout with per-app overrides. Quick Quit panel shows running apps with inactivity timer, CPU, and RAM.

**How it measures idle time:** Per-app inactivity timeout (global default, per-app overrides, disable with timeout=0). Mechanism not documented but likely frontmost-app tracking.

**Permissions:** Requires Accessibility permission to monitor app windows.

**Distribution:** $4 on [Gumroad](https://luizcamargo.gumroad.com/l/smartquit). Closed source.

**Relevance to Squeegee:** The closest existing combination of idle-quit and last-window-quit features. Still app-level only.

**Sources:**
- [Gumroad page](https://luizcamargo.gumroad.com/l/smartquit)

---

## 6. Hocus Focus (Nial Giacomelli)

**What it does:** Automatically hides application windows after a configurable inactivity period (0 to 10 minutes, in 15-second increments). Does not quit apps -- only hides them. Supports multiple profiles.

**How it measures inactivity:** Tracks when each app was last in the foreground. When the timer expires, calls the equivalent of `NSRunningApplication.hide()`.

**Permissions:** Not explicitly documented. Likely no Accessibility needed (hide is a public API). Not sandboxed (not on App Store).

**Distribution:** Free, direct download. **Discontinued** -- latest version 1.3. Originally called Houdini (2011), rewritten and renamed to Hocus Focus.

**Known problems:**
- Discontinued, no longer maintained.
- Maximum timer only 10 minutes.
- Hide-only, no quit option.

**Sources:**
- [Official site (archived)](http://hocusfoc.us/)
- [Softpedia page](https://mac.softpedia.com/get/Utilities/Hocus-Focus.shtml)
- [AlternativeTo listing](https://alternativeto.net/software/hocus-focus/)

---

## 7. HazeOver

**What it does:** Dims all non-active windows with a configurable overlay, making the frontmost window visually pop. Does not close, quit, or hide anything -- purely visual focus aid.

**How it works:** Applies a colored overlay (default black, customizable) to all background windows. Adjustable intensity and animation speed.

**Permissions:** Accessibility permission for accurate window tracking.

**Distribution:** Mac App Store ($4.99). Actively maintained, compatible through macOS 27 Golden Gate. [John Gruber endorsement](https://daringfireball.net/2026/03/hazeover).

**Relevance to Squeegee:** Not a competitor (visual only), but confirms that Accessibility permission is sufficient for tracking which window is frontmost. The visual dimming approach is interesting as a complementary feature but not a substitute for Squeegee's close/quit behavior.

**Sources:**
- [Official site](https://hazeover.com/)
- [Mac App Store listing](https://apps.apple.com/us/app/hazeover-distraction-dimmer/id430798174)
- [Daring Fireball review](https://daringfireball.net/2026/03/hazeover)

---

## 8. Other Tools

### one-click-quits (beyluta)
C++ utility. Polls CGWindowID validity periodically -- when an app's window ID becomes invalid, the app is terminated. Skips `modeOnlyBackground` apps. Requires macOS 13.4+. Limited -- cannot handle apps with background processes. [GitHub](https://github.com/beyluta/one-click-quits).

### Last Window Quits
Free utility similar to SwiftQuit. Quits apps when their last window closes. Detects any closure method (red button, Cmd-W, etc.). 

### RedQuits
Changes the red close button to quit the app instead of just closing the window. All programs quit on red-button click.

### QuitAll / OneClick QuitAll
Manual "quit everything" utilities. No idle detection.

### MiddleQuit (LoopyDev)
Middle-click a Dock item to quit. Compatible with macOS 27 Tahoe. $1.50 on [Gumroad](https://loopydev.gumroad.com/l/rmmvgk).
