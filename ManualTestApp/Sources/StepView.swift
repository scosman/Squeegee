import ManualTestKit
import SwiftUI

/// Holds the latest status message for a running `.action` step.
@MainActor
final class StepStatusModel: ObservableObject {
    @Published var message: String?
}

/// Renders a single `TestStep` with interaction controls and a status badge.
struct StepView: View {
    let step: TestStep
    let result: TestResult?
    let onResult: (TestResult) -> Void

    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var checkOutcome: CheckOutcome?
    @State private var noteText = ""
    @StateObject private var statusModel = StepStatusModel()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusBadge
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 8) {
                switch step {
                case let .action(id, label, run):
                    actionView(id: id, label: label, run: run)

                case let .instruction(_, text):
                    instructionView(text: text)

                case let .humanQuestion(id, prompt):
                    humanQuestionView(id: id, prompt: prompt)

                case let .autoCheck(id, label, check):
                    autoCheckView(id: id, label: label, check: check)
                }

                recordedInfo
            }
        }
        .onAppear { noteText = result?.note ?? "" }
        .onChange(of: result) { _, newResult in
            noteText = newResult?.note ?? ""
        }
    }

    // MARK: - Step type views

    @ViewBuilder
    private func actionView(
        id: String,
        label: String,
        run: @escaping @Sendable (@escaping @Sendable (String) -> Void) async throws -> Void
    ) -> some View {
        Text(label).font(.headline)

        HStack(spacing: 8) {
            Button("Run") {
                Task { await executeAction(id: id, run: run) }
            }
            .disabled(isRunning)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if let message = statusModel.message {
            Text(message)
                .foregroundStyle(.secondary)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func instructionView(text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func humanQuestionView(id: String, prompt: String) -> some View {
        Text(prompt).font(.headline)

        TextField("Optional note", text: $noteText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 400)
            .onSubmit { saveNoteIfNeeded() }

        HStack(spacing: 12) {
            Button("Yes (Pass)") {
                recordHuman(id: id, status: .pass)
            }
            Button("No (Fail)") {
                recordHuman(id: id, status: .fail)
            }

            if hasUnsavedNote {
                Text("Press Return to save note")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func autoCheckView(
        id: String,
        label: String,
        check: @escaping @Sendable () async -> CheckOutcome
    ) -> some View {
        Text(label).font(.headline)

        HStack(spacing: 8) {
            Button("Run Check") {
                Task { await executeCheck(id: id, check: check) }
            }
            .disabled(isRunning)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if let checkOutcome {
            if checkOutcome.detail.count > 200 {
                ScrollView {
                    Text(checkOutcome.detail)
                        .foregroundStyle(checkOutcome.passed ? .green : .red)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .border(Color.secondary.opacity(0.2))
            } else {
                Text(checkOutcome.detail)
                    .foregroundStyle(checkOutcome.passed ? .green : .red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Recorded result info

    /// Shows the saved note and timestamp for any step that has a recorded result.
    /// For humanQuestion steps the note field already serves as the note display,
    /// so only the timestamp is shown. For other step types the note text is shown
    /// read-only.
    @ViewBuilder
    private var recordedInfo: some View {
        if let result, result.status != .notRun {
            VStack(alignment: .leading, spacing: 2) {
                if !step.isHumanQuestion, let note = result.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Note:")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let timestamp = result.timestamp {
                    Text("Recorded \(timestamp.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch result?.status {
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .notRun, nil:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Note helpers

    /// True when the note field has been edited but not yet saved.
    private var hasUnsavedNote: Bool {
        guard let existing = result, existing.status != .notRun else { return false }
        let current = noteText.isEmpty ? nil : noteText
        return current != existing.note
    }

    /// Persists the current note text with the existing status and timestamp.
    private func saveNoteIfNeeded() {
        guard let existing = result, existing.status != .notRun else { return }
        let note = noteText.isEmpty ? nil : noteText
        guard note != existing.note else { return }
        onResult(TestResult(
            stepID: existing.stepID,
            status: existing.status,
            note: note,
            timestamp: existing.timestamp
        ))
    }

    // MARK: - Actions

    @MainActor
    private func executeAction(
        id: String,
        run: @escaping @Sendable (@escaping @Sendable (String) -> Void) async throws -> Void
    ) async {
        isRunning = true
        errorMessage = nil
        statusModel.message = nil

        let model = statusModel
        let report: @Sendable (String) -> Void = { message in
            Task { @MainActor in model.message = message }
        }

        do {
            try await run(report)
            onResult(TestResult(stepID: id, status: .pass, timestamp: .now))
        } catch {
            errorMessage = error.localizedDescription
            onResult(TestResult(stepID: id, status: .fail, note: error.localizedDescription, timestamp: .now))
        }
        isRunning = false
    }

    private func executeCheck(
        id: String,
        check: @escaping @Sendable () async -> CheckOutcome
    ) async {
        isRunning = true
        let outcome = await check()
        checkOutcome = outcome
        let status: TestStatus = outcome.passed ? .pass : .fail
        onResult(TestResult(stepID: id, status: status, note: outcome.detail, timestamp: .now))
        isRunning = false
    }

    private func recordHuman(id: String, status: TestStatus) {
        let note = noteText.isEmpty ? nil : noteText
        onResult(TestResult(stepID: id, status: status, note: note, timestamp: .now))
    }
}

// MARK: - TestStep convenience

private extension TestStep {
    var isHumanQuestion: Bool {
        if case .humanQuestion = self { return true }
        return false
    }
}
