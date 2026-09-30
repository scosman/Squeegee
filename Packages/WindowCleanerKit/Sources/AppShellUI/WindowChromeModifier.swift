import AppCore
import AppKit
import SwiftUI

/// Adjusts NSWindow properties based on the current route.
///
/// During onboarding the window is fixed at 640x600, not resizable, with a
/// hidden title bar and floating traffic lights (ui_design section 5.1).
/// When the route switches to settings the window becomes resizable with a
/// visible title bar and resizes to the settings default (760x540).
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

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Defer to the next run-loop turn so the view is in the window.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            applyChrome(to: window, route: route)
        }
    }

    private func applyChrome(to window: NSWindow, route: Route) {
        switch route {
        case .onboarding:
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

        case .settings:
            // Standard title bar
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.styleMask.remove(.fullSizeContentView)
            window.styleMask.insert(.resizable)

            // Settings defaults
            let settingsMin = NSSize(width: 640, height: 440)
            let settingsDefault = NSSize(width: 760, height: 540)
            window.minSize = settingsMin
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
            window.setContentSize(settingsDefault)
        }
    }
}
