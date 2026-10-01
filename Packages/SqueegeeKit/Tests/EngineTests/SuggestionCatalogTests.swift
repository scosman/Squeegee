import Foundation
import Testing
@testable import Engine

@Test func builtInCatalogEntriesHaveValidRules() {
    let catalog = SuggestionCatalog.builtIn
    #expect(catalog.entries.count >= 18) // 19 minus Granola which is omitted

    for entry in catalog.entries {
        #expect(!entry.bundleID.isEmpty)
        #expect(entry.rule.isEnabled)
        #expect(Rule.closeAfterRange.contains(entry.rule.closeAfter))
    }
}

@Test func suggestionsMatchInstalledApps() {
    let catalog = SuggestionCatalog.builtIn
    let installed = [
        InstalledApp(bundleID: "com.apple.finder", name: "Finder", url: URL(filePath: "/System/Library/CoreServices/Finder.app")),
        InstalledApp(bundleID: "com.apple.Preview", name: "Preview", url: URL(filePath: "/System/Applications/Preview.app")),
        InstalledApp(bundleID: "com.unknown.app", name: "Unknown", url: URL(filePath: "/Applications/Unknown.app"))
    ]

    let suggestions = catalog.suggestions(installedApps: installed)
    #expect(suggestions.count == 2)
    #expect(suggestions[0].entry.bundleID == "com.apple.finder")
    #expect(suggestions[0].appName == "Finder")
    #expect(suggestions[1].entry.bundleID == "com.apple.Preview")
}

@Test func suggestionsExcludeBundleIDs() {
    let catalog = SuggestionCatalog.builtIn
    let installed = [
        InstalledApp(bundleID: "com.apple.finder", name: "Finder", url: URL(filePath: "/System/Library/CoreServices/Finder.app")),
        InstalledApp(bundleID: "com.apple.Preview", name: "Preview", url: URL(filePath: "/System/Applications/Preview.app"))
    ]

    let suggestions = catalog.suggestions(
        installedApps: installed,
        excludingBundleIDs: ["com.apple.finder"]
    )
    #expect(suggestions.count == 1)
    #expect(suggestions[0].entry.bundleID == "com.apple.Preview")
}

@Test func suggestionsPreserveCatalogOrder() {
    let catalog = SuggestionCatalog.builtIn
    let installed = catalog.entries.map {
        InstalledApp(bundleID: $0.bundleID, name: $0.bundleID, url: URL(filePath: "/Applications/\($0.bundleID).app"))
    }

    let suggestions = catalog.suggestions(installedApps: installed)
    #expect(suggestions.count == catalog.entries.count)

    // Verify order: category order, then catalog order within each category
    var lastCategoryRaw = -1
    for suggestion in suggestions {
        #expect(suggestion.entry.category.rawValue >= lastCategoryRaw)
        lastCategoryRaw = suggestion.entry.category.rawValue
    }
}

@Test func finderRuleHasNeverQuitPolicy() {
    let finderEntry = SuggestionCatalog.builtIn.entries.first { $0.bundleID == "com.apple.finder" }
    #expect(finderEntry != nil)
    #expect(finderEntry?.rule.quitPolicy == .never)
}
