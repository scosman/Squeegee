import Foundation

/// Whether the close timer measures from the window's last active time or its opened time.
public enum MeasureFrom: String, Codable, Sendable {
    case lastActive
    case opened
}

/// What happens when the last standard window of an app is closed.
public enum QuitPolicy: String, Codable, Sendable {
    case never
    case ifClosedBySqueegee
    case always
}

/// A per-app or global rule controlling when windows close and whether the app quits.
public struct Rule: Equatable, Sendable, Codable {
    public var isEnabled: Bool
    public var closeAfter: TimeInterval
    public var measureFrom: MeasureFrom
    public var quitPolicy: QuitPolicy

    /// The allowed range for `closeAfter`: 1 minute to 30 days.
    public static let closeAfterRange: ClosedRange<TimeInterval> = 60 ... (30 * 86400)

    /// The default global rule: disabled, 6 hours, last active, never quit.
    public static let globalDefault = Rule(
        isEnabled: false,
        closeAfter: 6 * 3600,
        measureFrom: .lastActive,
        quitPolicy: .never
    )

    /// The default rule for a newly created app rule: enabled, 6 hours, last active, never quit.
    public static let newAppRuleDefault = Rule(
        isEnabled: true,
        closeAfter: 6 * 3600,
        measureFrom: .lastActive,
        quitPolicy: .never
    )

    public init(isEnabled: Bool, closeAfter: TimeInterval, measureFrom: MeasureFrom, quitPolicy: QuitPolicy) {
        self.isEnabled = isEnabled
        self.closeAfter = closeAfter
        self.measureFrom = measureFrom
        self.quitPolicy = quitPolicy
    }
}

/// The result of resolving a rule for a specific app: either an app-specific rule or the global rule.
public struct ResolvedRule: Equatable, Sendable {
    public let rule: Rule
    public let source: Source

    public enum Source: Sendable, Equatable {
        case app
        case global
    }

    public init(rule: Rule, source: Source) {
        self.rule = rule
        self.source = source
    }
}

/// A collection of rules: one global rule plus per-app overrides.
public struct RuleSet: Equatable, Sendable {
    public var global: Rule
    public var appRules: [String: Rule]

    public init(global: Rule = .globalDefault, appRules: [String: Rule] = [:]) {
        self.global = global
        self.appRules = appRules
    }

    /// Resolves the effective rule for an app. An app rule fully replaces the
    /// global rule. The global rule's quit policy is always treated as `.never`,
    /// and Finder's quit policy is always `.never`.
    public func resolve(bundleID: String) -> ResolvedRule {
        if let appRule = appRules[bundleID] {
            var resolved = appRule
            if bundleID == "com.apple.finder" {
                resolved.quitPolicy = .never
            }
            return ResolvedRule(rule: resolved, source: .app)
        }
        var globalRule = global
        globalRule.quitPolicy = .never
        return ResolvedRule(rule: globalRule, source: .global)
    }
}
