<div align="center">
<img width="84" height="83" alt="Squeegee icon" src="https://github.com/user-attachments/assets/b681fc93-1599-4dbb-9753-b443f0b1ba38" />

### Squeegee

**Clean your MacOS Windows.**

<a href="https://github.com/scosman/Squeegee/releases/latest/download/Squeegee.dmg">
  <img width="165" height="38" alt="Download for macOS" src="https://github.com/user-attachments/assets/a0ff77ed-d9cd-49df-9ba5-b866098d8d67" />
</a>
</div>

---

**Squeegee** is a native macOS menu bar app that closes stale windows. Set per-app rules ("close Finder windows 6 hours after I last used them"), and Squeegee closes each window when its time is up. It works per **window**, not per process: closing one stale Finder window leaves your other Finder windows open.

<div align="center">
:lock: <strong>Private</strong> runs locally on your Mac  &middot;  :zap: <strong>Lightweight</strong> native macOS app, no Electron
</div>

<!-- TODO: Add a screenshot or short video of the app in action -->

## Features

- **Per-window close timers** -- Set a duration per app. Squeegee closes each window individually when its timer expires.
- **Last active or opened** -- "Last active" (default) tracks the last time you used a window. "Opened" counts from when the window first appeared.
- **Per-app rules + a global default** -- Add rules for specific apps, or set one global rule that applies to everything else.
- **Quit when empty** -- Optionally quit an app after Squeegee closes all its windows.
- **Reopen** -- Recent closures appear in the menu bar with one-click reopen for documents.
- **Suggestions** -- A built-in catalog proposes rules for common apps (Finder, Preview, QuickTime, messaging apps, and more).
- **Pause** -- Pause all closures from the menu bar: for an hour, until tomorrow, or until you resume.
- **Menu bar icon** -- See upcoming and recent closures at a glance. The icon can be hidden in Settings.
- **Launch at login** -- Toggle in Settings so Squeegee starts when your Mac starts.
- **Safe by default** -- Nothing closes until you turn it on. Squeegee sends a normal close (the same as clicking the red button) and never force-quits anything.
- **Local and private** -- No network access, no accounts, no telemetry. Window titles and data never leave your Mac.

## How It Works

1. **Add a rule** -- Pick an app and choose how long a window can sit idle before Squeegee closes it.
2. **Squeegee watches** -- It tracks each window's last-active time (or opened time) in the background.
3. **Stale windows close** -- When a window passes its deadline, Squeegee closes it, just like clicking the red close button.

Rules apply per app, not per window. You set them once and Squeegee handles the rest.

## Accessibility Permission

Squeegee needs the **Accessibility** permission to see and close windows of other apps. The app prompts for it on first launch. Nothing leaves your Mac -- the permission is used only to close windows locally.

## Requirements

- macOS 15.0 (Sequoia) or later

## Install

1. Download [`Squeegee.dmg`](https://github.com/scosman/Squeegee/releases/latest/download/Squeegee.dmg).
2. Open the DMG and drag **Squeegee.app** to your Applications folder.
3. Open Squeegee and follow the onboarding to grant Accessibility access and pick your first rules.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for build instructions, architecture, and development workflow.

## License

[MIT License](LICENSE)
