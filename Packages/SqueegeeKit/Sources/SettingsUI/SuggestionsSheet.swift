import AppCore
import Engine
import SharedUI
import SwiftUI

/// A sheet that shows suggested rules for installed apps. Opened from the
/// sidebar + button's "Suggested Rules..." option (ui_design section 4.5).
struct SuggestionsSheet: View {
    let core: AppCore
    @Binding var isPresented: Bool

    @State private var suggestions: [Suggestion] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Suggested Rules")
                .font(.headline)
                .padding(.top, 16)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: 200)
            } else if suggestions.isEmpty {
                emptyState
            } else {
                SuggestionListView(suggestions: suggestions, selectedIDs: $selectedIDs)
                    .padding(.horizontal, 16)
            }

            Spacer()

            buttons
        }
        .frame(width: 480, height: 420)
        .task {
            suggestions = await core.suggestions(excludingExistingRules: true)
            selectedIDs = Set(suggestions.map(\.id))
            isLoading = false
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("All suggested apps already have rules.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            if suggestions.isEmpty, !isLoading {
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add \(selectedIDs.count) Rules") {
                    let selected = suggestions.filter { selectedIDs.contains($0.id) }
                    core.applySuggestions(selected)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
