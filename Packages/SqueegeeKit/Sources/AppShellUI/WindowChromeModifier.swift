import AppCore
import AppKit
import SwiftUI

/// Applies per-route window chrome (ui_design sections 4 and 5.1).
///
/// During onboarding the window is fixed-size with a hidden title bar and
/// floating traffic lights (ui_design section 5.1). When the route switches
/// to settings the window becomes resizable with a visible title bar and
/// resizes to the settings default (760x540).
///
/// Chrome is applied only when the route changes, not on every SwiftUI
/// layout pass. This prevents layout-recursion warnings from
/// `setContentSize` during layout and avoids resetting the user's
/// window size on Cmd-Tab or other redraws.
struct WindowChromeModifier: ViewModifier {
    let route: Route

    func body(content: Content) -> some View {
        content
            .background(WindowChromeHelper(route: route))
    }
}

// MARK: - NSViewRepresentable helper

/// An invisible NSView whose sole job is to find its hosting NSWindow and
/// configure its chrome when the route changes.
private struct WindowChromeHelper: NSViewRepresentable {
    let route: Route

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let isOnboarding = route.isOnboarding
        let routeChanged = isOnboarding != context.coordinator.lastWasOnboarding

        if routeChanged {
            context.coordinator.lastWasOnboarding = isOnboarding
        }

        // Defer to the next run-loop turn so any in-progress layout pass
        // has finished.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }

            if routeChanged {
                Self.applyChrome(to: window, isOnboarding: isOnboarding)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        /// Tracks the last applied route kind so chrome is applied only
        /// when the route changes, not on every SwiftUI body evaluation.
        var lastWasOnboarding: Bool?
    }

    // MARK: - Chrome application

    private static func applyChrome(to window: NSWindow, isOnboarding: Bool) {
        if isOnboarding {
            // Hidden title bar with floating traffic lights
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)

            // Fixed size
            let onboardingSize = NSSize(width: 640, height: 600)
            window.setContentSize(onboardingSize)
            window.minSize = onboardingSize
            window.maxSize = onboardingSize
        } else {
            // Standard title bar
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.styleMask.remove(.fullSizeContentView)
            window.styleMask.insert(.resizable)

            // Settings defaults
            let settingsMin = NSSize(width: 640, height: 440)
            window.minSize = settingsMin
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)

            // Only resize if the window is too small (e.g. coming from
            // onboarding). If the user has already resized the window,
            // keep their size.
            let frame = window.frame
            if frame.width < settingsMin.width || frame.height < settingsMin.height {
                let settingsDefault = NSSize(width: 760, height: 540)
                window.setContentSize(settingsDefault)
            }
        }
    }
}

// MARK: - Route helper

private extension Route {
    var isOnboarding: Bool {
        if case .onboarding = self { return true }
        return false
    }
}
