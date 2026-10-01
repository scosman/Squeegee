import Foundation

// MARK: - Schedule status

/// The current status of a managed window's close schedule.
public enum ScheduleStatus: Sendable, Equatable {
    /// Deadline in the future.
    case scheduled
    /// Past deadline, focused window of frontmost app.
    case dueInUse
    /// Past deadline, paused or no permission.
    case duePaused
    /// Past deadline, waiting for AX reach (other Space).
    case dueUnreachable
    /// Close sent, awaiting verification.
    case closing
    /// Declined; waits until used again.
    case keptOpen
    /// Rule off.
    case disabled
}

// MARK: - Window schedule

/// A managed window's schedule, including its deadline and current status.
public struct WindowSchedule: Sendable, Equatable, Identifiable {
    public var id: WindowKey {
        key
    }

    public let key: WindowKey
    public let bundleID: String
    public let appName: String
    public let title: String?
    public let ruleSource: ResolvedRule.Source
    public let deadline: Date?
    public let status: ScheduleStatus

    public init(
        key: WindowKey,
        bundleID: String,
        appName: String,
        title: String?,
        ruleSource: ResolvedRule.Source,
        deadline: Date?,
        status: ScheduleStatus
    ) {
        self.key = key
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.ruleSource = ruleSource
        self.deadline = deadline
        self.status = status
    }
}

// MARK: - Planned action

/// An action the planner has decided to take.
public enum PlannedAction: Sendable, Equatable {
    case closeWindow(WindowKey)
    case quitApp(pid: Int32)
}

// MARK: - Plan input

/// Everything the planner needs to compute a plan.
public struct PlanInput: Sendable {
    public var ruleSet: RuleSet
    public var state: TrackerState
    public var now: Date
    public var isPaused: Bool
    public var pausedUntil: Date?
    public var hasPermission: Bool

    public init(
        ruleSet: RuleSet,
        state: TrackerState,
        now: Date,
        isPaused: Bool,
        pausedUntil: Date? = nil,
        hasPermission: Bool
    ) {
        self.ruleSet = ruleSet
        self.state = state
        self.now = now
        self.isPaused = isPaused
        self.pausedUntil = pausedUntil
        self.hasPermission = hasPermission
    }
}

// MARK: - Plan

/// The result of planning: schedules for display, actions to execute, and the next wake time.
public struct Plan: Sendable, Equatable {
    public var schedules: [WindowSchedule]
    public var actions: [PlannedAction]
    public var nextWakeAt: Date?

    public static let empty = Plan(schedules: [], actions: [], nextWakeAt: nil)

    public init(schedules: [WindowSchedule], actions: [PlannedAction], nextWakeAt: Date?) {
        self.schedules = schedules
        self.actions = actions
        self.nextWakeAt = nextWakeAt
    }
}

// MARK: - Dry run result

/// A preview of what would happen if a rule set were applied right now.
public struct DryRunResult: Sendable, Equatable {
    public let windowsToClose: [WindowSchedule]
    public let appsToQuit: [TrackedApp]

    public init(windowsToClose: [WindowSchedule], appsToQuit: [TrackedApp]) {
        self.windowsToClose = windowsToClose
        self.appsToQuit = appsToQuit
    }
}
