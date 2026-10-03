import Engine
import Foundation

/// Pure helpers for the close-after duration picker. Extracted so the
/// clamping and preset-matching logic can be unit-tested.
public enum DurationClamping {
    /// The preset durations shown in the close-after picker (in seconds).
    public static let presets: [Int] = [
        60, 1800, 3600, 7200, 14400, 21600, 43200, 86400, 172_800, 604_800
    ]

    /// The set form for fast membership checks.
    public static let presetSet: Set<Int> = Set(presets)

    /// Returns whether the value matches a preset.
    public static func isPreset(_ seconds: Int) -> Bool {
        presetSet.contains(seconds)
    }

    /// Clamps a duration in seconds to `Rule.closeAfterRange`.
    public static func clamp(_ seconds: Int) -> Int {
        let lower = Int(Rule.closeAfterRange.lowerBound)
        let upper = Int(Rule.closeAfterRange.upperBound)
        return max(lower, min(upper, seconds))
    }
}
