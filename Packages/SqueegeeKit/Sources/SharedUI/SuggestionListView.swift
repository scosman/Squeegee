import Engine
import Presentation
import SwiftUI

/// A shared checklist of suggested app rules grouped by category. Used in
/// onboarding step 3 and the Settings "Suggested Rules" sheet.
public struct SuggestionListView: View {
    let suggestions: [Suggestion]
    @Binding var selectedIDs: Set<String>

    public init(suggestions: [Suggestion], selectedIDs: Binding<Set<String>>) {
        self.suggestions = suggestions
        _selectedIDs = selectedIDs
    }

    public var body: some View {
        if suggestions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                listContent
                Divider()
                selectionCount
            }
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("None of the suggested apps are installed.")
                .foregroundStyle(.secondary)
            Text("You can add rules for any app later in Settings.")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - List content

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let grouped = groupedByCategory()
                ForEach(grouped, id: \.category) { group in
                    categorySection(group)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Category section

    private func categorySection(_ group: CategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.category.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(group.suggestions) { suggestion in
                suggestionRow(suggestion)
                if suggestion.id != group.suggestions.last?.id {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Row

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        let isSelected = selectedIDs.contains(suggestion.id)
        return Button {
            if isSelected {
                selectedIDs.remove(suggestion.id)
            } else {
                selectedIDs.insert(suggestion.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)

                AppIconView(bundleID: suggestion.entry.bundleID, size: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.appName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(RuleSummary.suggestionSummary(rule: suggestion.entry.rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(suggestion.appName), \(RuleSummary.suggestionSummary(rule: suggestion.entry.rule))"
        )
    }

    // MARK: - Selection count

    private var selectionCount: some View {
        HStack {
            Spacer()
            Text("\(selectedIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Grouping

    private struct CategoryGroup {
        let category: SuggestionCategory
        let suggestions: [Suggestion]
    }

    private func groupedByCategory() -> [CategoryGroup] {
        var groups: [SuggestionCategory: [Suggestion]] = [:]
        for suggestion in suggestions {
            groups[suggestion.entry.category, default: []].append(suggestion)
        }
        return SuggestionCategory.allCases.compactMap { category in
            guard let items = groups[category], !items.isEmpty else { return nil }
            return CategoryGroup(category: category, suggestions: items)
        }
    }
}

// MARK: - Category display name

extension SuggestionCategory {
    var displayName: String {
        switch self {
        case .files: "Files"
        case .media: "Media"
        case .messaging: "Messaging"
        case .backgroundApps: "Background Apps"
        case .system: "System"
        }
    }
}
