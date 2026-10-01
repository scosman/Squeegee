import Foundation

// MARK: - Suggestion category

/// Categories for the built-in suggestion catalog, in display order.
public enum SuggestionCategory: Int, Sendable, Equatable, CaseIterable {
    case files = 0
    case media
    case messaging
    case backgroundApps
    case system
}

// MARK: - Catalog entry

/// A single entry in the built-in suggestion catalog.
public struct CatalogEntry: Sendable, Equatable {
    public let bundleID: String
    public let category: SuggestionCategory
    public let rule: Rule

    public init(bundleID: String, category: SuggestionCategory, rule: Rule) {
        self.bundleID = bundleID
        self.category = category
        self.rule = rule
    }
}

// MARK: - Suggestion

/// A matched catalog entry with the installed app's info.
public struct Suggestion: Sendable, Equatable, Identifiable {
    public var id: String {
        entry.bundleID
    }

    public let entry: CatalogEntry
    public let appName: String
    public let appURL: URL

    public init(entry: CatalogEntry, appName: String, appURL: URL) {
        self.entry = entry
        self.appName = appName
        self.appURL = appURL
    }
}
