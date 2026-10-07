import AppKit
import SwiftUI

/// The "−" button in the sidebar bottom bar. Mirrors the style of the "+"
/// button (AddAppMenu). Enabled only when an app rule is selected.
struct RemoveRuleButton: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.isEnabled = isEnabled
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RemoveRuleButton

        init(parent: RemoveRuleButton) {
            self.parent = parent
        }

        @objc func clicked(_: NSButton) {
            parent.action()
        }
    }
}
