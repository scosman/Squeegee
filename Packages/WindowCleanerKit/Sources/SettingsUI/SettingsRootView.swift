import AppCore
import SwiftUI

/// The root settings view: a NavigationSplitView with sidebar and detail
/// (ui_design section 4).
public struct SettingsRootView: View {
    let core: AppCore
    @State private var selection: SettingsSelection?

    public init(core: AppCore, initialSelection: SettingsSelection = .general) {
        self.core = core
        _selection = State(initialValue: initialSelection)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(core: core, selection: $selection)
                .frame(minWidth: 200)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 640, minHeight: 440)
        .onChange(of: selection) { _, newValue in
            if let sel = newValue {
                core.store.settings.lastSettingsSelection = selectionString(sel)
            }
        }
        .onChange(of: core.route) { _, newRoute in
            if case let .settings(sel) = newRoute {
                selection = sel
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general, .none:
            GeneralPage(core: core)
        case .globalRule:
            RulePage(core: core, bundleID: nil)
        case let .appRule(bundleID):
            RulePage(core: core, bundleID: bundleID)
                .id(bundleID) // Force recreation when selection changes
        }
    }

    private func selectionString(_ selection: SettingsSelection) -> String {
        switch selection {
        case .general: "general"
        case .globalRule: "global"
        case let .appRule(bundleID): bundleID
        }
    }
}
