import Engine
import SwiftUI
import SystemBridge

/// The Live Inspector tab: a table of windows joined with AX metadata,
/// the frontmost app, focused window ID, and a live event log.
struct LiveInspectorView: View {
    @State private var monitor = MonitorLoop()
    @State private var selectedWindowKey: WindowKey?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Monitor", isOn: Binding(
                    get: { monitor.isRunning },
                    set: { newValue in
                        if newValue { monitor.start() } else { monitor.stop() }
                    }
                ))
                .toggleStyle(.switch)

                Spacer()

                Text("Permission: \(monitor.permissionGranted ? "Granted" : "Denied")")
                    .foregroundStyle(monitor.permissionGranted ? .green : .red)
                    .font(.caption.bold())

                if let app = monitor.frontmostApp {
                    Text("Frontmost: \(app.name) (pid \(app.pid))")
                        .font(.caption)
                }

                if let wid = monitor.focusedWindowID {
                    Text("Focused: \(wid)")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Action bar for the selected window
            selectedWindowActions

            // Split view: window table on top, event log on bottom
            VSplitView {
                windowTable
                    .frame(minHeight: 200)

                eventLog
                    .frame(minHeight: 150)
            }
        }
    }

    // MARK: - Window table

    private var windowTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Windows (\(monitor.windows.count))")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            List(windowRows, id: \.key, selection: $selectedWindowKey) { row in
                windowRow(row)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private struct WindowRow: Identifiable {
        var id: WindowKey {
            key
        }

        let key: WindowKey
        let app: ObservedApp
        let bounds: CGRect
        let isOnScreen: Bool
        let metadata: WindowMetadata?
    }

    private var windowRows: [WindowRow] {
        monitor.windows.map { window in
            let meta = metadataForWindow(window)
            return WindowRow(
                key: window.key,
                app: window.app,
                bounds: window.bounds,
                isOnScreen: window.isOnScreen,
                metadata: meta
            )
        }.sorted { lhs, rhs in
            if lhs.app.name != rhs.app.name {
                return lhs.app.name < rhs.app.name
            }
            return lhs.key.windowID < rhs.key.windowID
        }
    }

    private func metadataForWindow(_ window: ObservedWindow) -> WindowMetadata? {
        guard let result = monitor.inspectionResults[window.key.pid],
              case let .inspected(map) = result
        else { return nil }
        return map[window.key.windowID]
    }

    private func windowRow(_ row: WindowRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            windowRowHeader(row)
            windowRowDetail(row)
        }
        .padding(.vertical, 2)
    }

    private func windowRowHeader(_ row: WindowRow) -> some View {
        HStack {
            Text(row.app.name)
                .fontWeight(.medium)
            Text("pid \(row.key.pid)")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("wid \(row.key.windowID)")
                .foregroundStyle(.secondary)
                .font(.caption)

            windowRowBadges(row)

            if row.isOnScreen {
                Text("onScreen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if row.key == selectedWindowKey {
                Text("selected")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func windowRowBadges(_ row: WindowRow) -> some View {
        if let meta = row.metadata {
            if meta.isStandard {
                Text("standard")
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.green.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Text("non-standard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if meta.isMinimized {
                Text("minimized")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func windowRowDetail(_ row: WindowRow) -> some View {
        HStack {
            if let meta = row.metadata {
                if let title = meta.title {
                    Text(title)
                        .font(.caption)
                        .lineLimit(1)
                }
                if let url = meta.documentURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            } else {
                Text("(no AX metadata)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(row.bounds.width))x\(Int(row.bounds.height))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selected window actions

    @ViewBuilder
    private var selectedWindowActions: some View {
        if let key = selectedWindowKey, let row = windowRows.first(where: { $0.key == key }) {
            VStack(spacing: 4) {
                HStack {
                    Text("Selected: \(row.app.name) pid \(key.pid) wid \(key.windowID)")
                        .font(.caption.bold())

                    if let meta = row.metadata, let url = meta.documentURL {
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Close") {
                        Task { _ = await monitor.closeWindow(key) }
                    }

                    if !monitor.capturedCloses.isEmpty {
                        Button("Reopen All (\(monitor.capturedCloses.count))") {
                            Task { await monitor.reopenCapturedDocuments() }
                        }
                    }
                }

                if let result = monitor.lastCloseResult {
                    HStack {
                        Text("Last close: \(closeResultText(result))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()
        }
    }

    // MARK: - Event log

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Event Log (\(monitor.logEntries.count))")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    monitor.clearLog()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                List(monitor.logEntries) { entry in
                    HStack(alignment: .top) {
                        Text(Self.timeFormatter.string(from: entry.timestamp))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .id(entry.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onChange(of: monitor.logEntries.count) {
                    if let last = monitor.logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private func closeResultText(_ result: CloseAttemptResult) -> String {
    switch result {
    case let .pressed(latest, wasListed):
        let title = latest?.title ?? "untitled"
        return "pressed(wasListed: \(wasListed), title: \(title))"
    case .unreachable:
        return "unreachable"
    case .noCloseButton:
        return "noCloseButton"
    case let .failed(code):
        return "failed(code: \(code))"
    case .notTrusted:
        return "notTrusted"
    }
}
