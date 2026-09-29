# Accessibility API: Window Listing, Closing, and the CGWindowID Bridge

## Overview

The macOS Accessibility API (`AXUIElement`) is the primary mechanism for **interacting** with other apps' windows — listing them, reading their properties, and performing actions like closing. It requires the Accessibility TCC permission.

## Core Concepts

### AXUIElement Hierarchy

The accessibility tree for window management:

```
System-wide element (AXUIElementCreateSystemWide)
  └─ Application element (AXUIElementCreateApplication(pid))
       └─ Window elements (kAXWindowsAttribute)
            ├─ Close button (kAXCloseButtonAttribute)
            ├─ Minimize button (kAXMinimizeButtonAttribute)
            ├─ Zoom button (kAXZoomButtonAttribute)
            ├─ Title (kAXTitleAttribute)
            ├─ Position (kAXPositionAttribute)
            ├─ Size (kAXSizeAttribute)
            ├─ Minimized state (kAXMinimizedAttribute)
            └─ ... (130+ possible attributes)
```

Source: [Apple Developer: AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [AXUIElement.h reference](https://leopard-adc.pepas.com/documentation/Accessibility/Reference/AccessibilityLowlevel/AXUIElement_h/CompositePage.html)

### Listing Windows of an App

```swift
// Create element for an app by PID
let appElement = AXUIElementCreateApplication(pid)

// Get all windows
var windowsRef: CFTypeRef?
let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
if error == .success, let windows = windowsRef as? [AXUIElement] {
    for window in windows {
        // Each window is an AXUIElement
    }
}
```

This returns the app's "standard" windows — what appears in the Window menu. It does **not** include:
- Individual tabs (unless the app exposes them as separate windows)
- Popover/sheet windows (those are children of their parent window)
- Off-screen or other-Space windows may or may not appear, depending on the app

Source: [DFAXUIElement library](https://github.com/JEfVAwafT6sNf/DFAXUIElement), [Moment for Technology tutorial](https://www.mo4tech.com/macos-development-series-1-monitoring-and-control-of-all-programs-using-the-accessibility-api.html)

## Closing a Window via Accessibility

The canonical approach uses `kAXCloseButtonAttribute` + `AXPress`:

```swift
// Get the close button from a window AXUIElement
var closeButtonRef: CFTypeRef?
let err1 = AXUIElementCopyAttributeValue(
    windowElement,
    kAXCloseButtonAttribute as CFString,
    &closeButtonRef
)

if err1 == .success, let closeButton = closeButtonRef {
    // Press the close button
    let err2 = AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
}
```

### Behavior of AXPress on the Close Button

- **This is equivalent to the user clicking the red close button.** The app receives the same close request it would get from a mouse click.
- **If there are unsaved changes**, the app will show its normal "Save/Don't Save/Cancel" dialog. The close is **not** forced.
- **The app remains running** after closing the window (standard macOS behavior — closing a window does not quit the app).
- **AXPress works reliably on native AppKit/SwiftUI windows.** For web views inside browsers, AXPress on the close button generally works (unlike AXPress on web content elements, which has reliability issues in Chrome, Safari, etc.).

Source: [Apple Developer: kAXCloseButtonAttribute](https://developer.apple.com/documentation/applicationservices/kaxclosebuttonattribute), [t8r.tech: macOS accessibility UI tree automation](https://t8r.tech/t/macos-accessibility-ui-tree)

### Important Notes on Close Button Reliability

- **Don't traverse the tree looking for the close button.** Read `kAXCloseButtonAttribute` directly from the window element — it's a dedicated attribute for exactly this purpose.
- **Some windows lack a close button** (e.g., panels, utility windows, sheets). Check for `kAXErrorAttributeUnsupported` from the attribute read.
- **AXPress returns success even when the app shows a dialog.** The action was delivered; the app decided to show a dialog instead of closing immediately.

Source: [t8r.tech](https://t8r.tech/t/macos-accessibility-ui-tree) ("Window chrome lives at known attribute keys. Don't search the tree for a Close button — read AXCloseButton off the window element directly and AXPress that.")

## Mapping Between CGWindowID and AXUIElement

### The Problem

`CGWindowListCopyWindowInfo` gives you `CGWindowID` values. The Accessibility API gives you `AXUIElement` references. There is **no public API** to convert between them.

Source: [SO: CGWindowListCopyWindowInfo & AXUIElementSetAttributeValue](https://stackoverflow.com/questions/11251700/cocoa-cgwindowlistcopywindowinfo-axuielementsetattributevalue) ("There is no way to go from a window number to an AXUIElementRef.")

### The Private API: `_AXUIElementGetWindow`

A widely used private function bridges AXUIElement to CGWindowID:

```c
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);
```

**Usage in Swift** (via bridging header):
```swift
// In an Objective-C bridging header:
// extern AXError _AXUIElementGetWindow(AXUIElementRef, CGWindowID *);

var windowID: CGWindowID = 0
let error = _AXUIElementGetWindow(axWindowElement, &windowID)
if error == .success {
    // windowID now contains the CGWindowID
}
```

This gives you the **AXUIElement-to-CGWindowID** direction. For the reverse (CGWindowID-to-AXUIElement), you must:
1. Get the window's owner PID from `CGWindowListCopyWindowInfo`
2. Create an AXUIElement for that app: `AXUIElementCreateApplication(pid)`
3. Read `kAXWindowsAttribute` to get all windows
4. Call `_AXUIElementGetWindow` on each to find the matching CGWindowID

Sources:
- [Hammerspoon issue #1469](https://github.com/Hammerspoon/hammerspoon/issues/1469) ("the only private function being used in there is _AXUIElementGetWindow which you can 'add' to your code by declaring extern AXError")
- [withfig/challenge-window-events](https://github.com/withfig/challenge-window-events) ("This isn't guaranteed to work, but it works as a ground-floor test")
- [tmc/apple Go package](https://pkg.go.dev/github.com/tmc/apple/x/axuiautomation) (wraps `_AXUIElementGetWindow` as `WindowID()`)

### Risk Assessment of `_AXUIElementGetWindow`

**Widely used in production apps:**
- AltTab (22k+ GitHub stars) uses it
- Hammerspoon uses it
- Rectangle, Amethyst, and most window managers use it
- Multiple Go, Rust, and Python automation libraries wrap it

**Risks:**
- It is undocumented and could be removed in a future macOS version without notice
- It could be rejected in a Mac App Store review (private API usage is disallowed)
- For Developer ID distribution (outside the App Store), private API usage is generally tolerated

**Practical assessment:** This function has existed since at least macOS 10.5 and has not been removed through macOS 26. Apple has not provided a public replacement. If Apple removed it, every major window manager on macOS would break — which provides some informal stability guarantee.

### Alternative: Matching Without the Private API

Without `_AXUIElementGetWindow`, you can correlate CGWindowList entries with AXUIElement windows by matching:
- Window title (from AX `kAXTitleAttribute`) against `kCGWindowName` (requires Screen Recording)
- Window position/size (from AX `kAXPositionAttribute`/`kAXSizeAttribute`) against `kCGWindowBounds`

This is fragile: multiple windows can have the same title, and position matching is racy. The private API is strongly preferred.

Source: [SO answer](https://stackoverflow.com/questions/11251700/cocoa-cgwindowlistcopywindowinfo-axuielementsetattributevalue) ("find the owner of the window, then ask it through Accessibility for its windows and look for one with the same title—but an app may have more than one window with the same title")

## Permissions

The Accessibility API requires the **Accessibility** TCC permission (`kTCCServiceAccessibility`). This is a one-time grant that does not expire or re-prompt (unlike Screen Recording on macOS 15+).

Check and request:
```swift
let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
)
```

Source: [Apple Developer: AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices)

## Availability

- AXUIElement: macOS 10.2+
- `_AXUIElementGetWindow`: undocumented, present since at least macOS 10.5, still present in macOS 26
- Works on macOS 14, 15, and 26
