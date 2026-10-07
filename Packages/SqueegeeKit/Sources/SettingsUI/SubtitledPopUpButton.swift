import AppKit
import SwiftUI

/// An option for a ``SubtitledPopUpButton``.
struct PopUpOption {
    let value: String
    let title: String
    let subtitle: String
}

/// An NSPopUpButton wrapper that supports `NSMenuItem.subtitle` on each item.
/// Standard SwiftUI `Picker` does not expose the subtitle property.
struct SubtitledPopUpButton: NSViewRepresentable {
    @Binding var selection: String
    let options: [PopUpOption]
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.alignment = .right
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        rebuildItems(popup)
        popup.isEnabled = isEnabled
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        popup.isEnabled = isEnabled

        // Rebuild items only if the option set changed.
        let currentValues = popup.itemArray.compactMap { $0.representedObject as? String }
        let newValues = options.map(\.value)
        if currentValues != newValues {
            rebuildItems(popup)
        }

        // Sync selection without triggering the action.
        let targetIndex = options.firstIndex(where: { $0.value == selection }) ?? 0
        if popup.indexOfSelectedItem != targetIndex {
            context.coordinator.isSyncing = true
            popup.selectItem(at: targetIndex)
            context.coordinator.isSyncing = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var parent: SubtitledPopUpButton
        /// True while the code is syncing the selection; suppresses the action.
        var isSyncing = false

        init(parent: SubtitledPopUpButton) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard !isSyncing,
                  let value = sender.selectedItem?.representedObject as? String
            else { return }
            parent.selection = value
        }
    }

    // MARK: - Helpers

    private func rebuildItems(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        for option in options {
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.subtitle = option.subtitle
            item.representedObject = option.value
            popup.menu?.addItem(item)
        }
        let idx = options.firstIndex(where: { $0.value == selection }) ?? 0
        popup.selectItem(at: idx)
    }
}
