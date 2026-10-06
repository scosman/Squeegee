<div align="center">
<img width="84" height="83" alt="Squeegee icon" src="https://github.com/user-attachments/assets/b681fc93-1599-4dbb-9753-b443f0b1ba38" />

### Squeegee: A MacOS app to close old windows

Set rules like: auto-close Finder windows idle for 4+ hours

<a href="https://github.com/scosman/Squeegee/releases/latest/download/Squeegee.dmg">
  <img width="165" height="38" alt="Download for macOS" src="https://github.com/user-attachments/assets/a0ff77ed-d9cd-49df-9ba5-b866098d8d67" />
</a>
</div>

---

**Clean you Windows:** Squeegee is a native macOS app that closes stale windows. Set per-app rules ("close Finder windows 6 hours after I last used them"), and Squeegee closes each window when its time is up. It works per **window**, not per app: closing a stale Finder window leaves your active Finder windows open.

<div align="center">
:zap: <strong>Lightweight</strong> near zero resource usage &middot; 🦾 <strong>Powerful</strong> configure each app independently
</div>

<div align="center">
<img width="420" height="273" alt="Squeegee Demo" src="https://github.com/user-attachments/assets/abc2113f-7100-4365-a042-207bb883c146" />
</div>

## Features

- **Per-window close timers** -- Set a duration per app. Squeegee closes each window individually when its timer expires.
- **Last active or opened** -- "Last active" (default) tracks the last time you used a window. "Opened" counts from when the window first appeared.
- **Per-app rules + a global default** -- Add rules for specific apps, or set one global rule that applies to everything else.
- **Quit app when last window closes** -- Optionally quit an app after the last window closes. For annoying apps like Quicktime and TextEdit that keep running in dock, even with no windows.
- **Reopen History** -- Recent closures appear in the menu bar with one-click reopen.
- **Suggestions** -- A built-in catalog proposes rules for common apps (Finder, Preview, QuickTime, messaging apps, and more).
- **Pause** -- Pause all closures from the menu bar: for an hour, until tomorrow, or until you resume.
- **Menu bar app** -- See upcoming and recent closures at a glance. The icon can be hidden in Settings.
- **Safe by default** -- Squeegee sends a normal close (the same as clicking the red button), never force-quits anything. Never overrides "Do you want to save?"
- **Local and private** -- No network access, no accounts, no telemetry. Data never leave your Mac.

## How It Works

1. **Add a rule** -- Pick an app and choose how long a window can sit idle before Squeegee closes it.
2. **Squeegee watches** -- It tracks each window's last-active time (or opened time) in the background.
3. **Stale windows close automatically** -- When a window passes its deadline, Squeegee closes it, just like clicking the red close button.

Rules are setup per app, and applied per window.

## Permissions

Squeegee needs the **Accessibility** permission to see and close windows of other apps. The app prompts for it on first launch. Nothing leaves your Mac -- the permission is used only to close windows locally.

Optionally needs permission to control Finder. With it, you can re-launch Finder windows to the exact path they were on when they were closed. Without it, it launches to the default directory.

## Requirements

- macOS 15.0 (Sequoia) or later

## Install

1. Download [`Squeegee.dmg`](https://github.com/scosman/Squeegee/releases/latest/download/Squeegee.dmg).
2. Open the DMG and drag **Squeegee.app** to your Applications folder.
3. Open Squeegee and follow the onboarding to grant Accessibility access and pick your first rules.

## Contributing & Build Instructions

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for build instructions, architecture, and development workflow.

## License

[MIT License](LICENSE)

<img width="500" height="649" alt="b2u4a4" src="https://github.com/user-attachments/assets/69856c18-6968-4c96-9ffa-87f756df6277" />

