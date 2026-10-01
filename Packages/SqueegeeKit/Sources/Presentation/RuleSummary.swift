import Engine
import Foundation

/// Pure rule summary formatting for the sidebar and suggestions list.
public enum RuleSummary {
    // MARK: - Sidebar format

    /// Compact summary for the settings sidebar.
    ///
    /// Examples: "6h . last active", "2h . opened . quits", "Off"
    public static func sidebarSummary(rule: Rule) -> String {
        guard rule.isEnabled else {
            return "Off"
        }
        var parts = [formatDuration(rule.closeAfter)]
        parts.append(rule.measureFrom == .lastActive ? "last active" : "opened")
        if rule.quitPolicy != .never {
            parts.append("quits")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Suggestion format

    /// Sentence summary for the suggestions list.
    ///
    /// Examples: "Close windows 6h after last use",
    ///           "Close windows 2h after last use, then quit"
    public static func suggestionSummary(rule: Rule) -> String {
        let duration = formatDuration(rule.closeAfter)
        let measure = rule.measureFrom == .lastActive ? "last use" : "opening"
        var text = "Close windows \(duration) after \(measure)"
        if rule.quitPolicy != .never {
            text += ", then quit"
        }
        return text
    }

    // MARK: - Duration formatting

    /// Formats a TimeInterval into a compact duration string showing the two
    /// largest non-zero units. Never silently drops a non-zero component.
    ///
    /// Examples: "30m", "1h", "6h", "1d", "2d", "1w", "1d 30m", "1d 2h"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        // Exact weeks
        if days >= 7, days % 7 == 0, hours == 0, minutes == 0 {
            return "\(days / 7)w"
        }

        // Build from the largest non-zero unit, showing up to two components
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }

        // Show the two largest (days+hours, days+minutes, or hours+minutes)
        if parts.isEmpty {
            return "0m"
        }
        return parts.prefix(2).joined(separator: " ")
    }
}
