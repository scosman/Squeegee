import Foundation

/// Pure planner: given the current state, rules, time, and flags, computes
/// which windows are scheduled, which actions are due, and when to wake next.
public enum Planner {
    public static func plan(_ input: PlanInput) -> Plan {
        var schedules: [WindowSchedule] = []
        var actions: [PlannedAction] = []
        var wakeCandidates: [Date] = []

        planWindows(input: input, schedules: &schedules, actions: &actions, wakeCandidates: &wakeCandidates)
        planAppQuits(input: input, actions: &actions, wakeCandidates: &wakeCandidates)

        // Paused until a date: that date is a wake candidate
        if input.isPaused, let pausedUntil = input.pausedUntil, pausedUntil > input.now {
            wakeCandidates.append(pausedUntil)
        }

        sortSchedules(&schedules)

        return Plan(schedules: schedules, actions: actions, nextWakeAt: wakeCandidates.min())
    }

    /// Returns what would happen if the given rule set were applied now,
    /// ignoring pause and permission.
    public static func dryRun(
        ruleSet: RuleSet,
        state: TrackerState,
        now: Date
    ) -> DryRunResult {
        let result = plan(PlanInput(
            ruleSet: ruleSet,
            state: state,
            now: now,
            isPaused: false,
            pausedUntil: nil,
            hasPermission: true
        ))

        let closeKeys = Set(result.actions.compactMap { action -> WindowKey? in
            if case let .closeWindow(key) = action { return key }
            return nil
        })

        let windowsToClose = result.schedules.filter { closeKeys.contains($0.key) }

        let quitPids = Set(result.actions.compactMap { action -> Int32? in
            if case let .quitApp(pid) = action { return pid }
            return nil
        })

        let appsToQuit = state.apps.values.filter { quitPids.contains($0.pid) }

        return DryRunResult(
            windowsToClose: windowsToClose,
            appsToQuit: Array(appsToQuit)
        )
    }
}

// MARK: - Private helpers

extension Planner {
    private static func planWindows(
        input: PlanInput,
        schedules: inout [WindowSchedule],
        actions: inout [PlannedAction],
        wakeCandidates: inout [Date]
    ) {
        for window in input.state.windows.values {
            guard let meta = window.metadata, meta.isStandard else {
                continue
            }

            let resolved = input.ruleSet.resolve(bundleID: window.bundleID)

            guard resolved.rule.isEnabled else {
                schedules.append(makeSchedule(window: window, meta: meta, resolved: resolved, deadline: nil, status: .disabled))
                continue
            }

            let base = computeBase(window: window, rule: resolved.rule, session: input.state.session, now: input.now)
            let deadline = base.addingTimeInterval(resolved.rule.closeAfter)
            let status = resolveWindowStatus(window: window, deadline: deadline, input: input, actions: &actions, wakeCandidates: &wakeCandidates)

            schedules.append(makeSchedule(window: window, meta: meta, resolved: resolved, deadline: deadline, status: status))
        }
    }

    private static func computeBase(window: TrackedWindow, rule: Rule, session: FocusSession?, now: Date) -> Date {
        if rule.measureFrom == .opened {
            return window.firstSeen
        }
        return effectiveLastActive(window: window, session: session, now: now) ?? window.firstSeen
    }

    private static func resolveWindowStatus(
        window: TrackedWindow,
        deadline: Date,
        input: PlanInput,
        actions: inout [PlannedAction],
        wakeCandidates: inout [Date]
    ) -> ScheduleStatus {
        switch window.closeState {
        case .sent:
            .closing
        case .declined:
            .keptOpen
        default:
            resolveOpenWindowStatus(window: window, deadline: deadline, input: input, actions: &actions, wakeCandidates: &wakeCandidates)
        }
    }

    private static func resolveOpenWindowStatus(
        window: TrackedWindow,
        deadline: Date,
        input: PlanInput,
        actions: inout [PlannedAction],
        wakeCandidates: inout [Date]
    ) -> ScheduleStatus {
        if deadline > input.now {
            wakeCandidates.append(deadline)
            return .scheduled
        }
        if window.key == input.state.focusedKey {
            return .dueInUse
        }
        if case .unreachable = window.closeState {
            return .dueUnreachable
        }
        if input.isPaused || !input.hasPermission {
            return .duePaused
        }
        actions.append(.closeWindow(window.key))
        return .closing
    }

    private static func makeSchedule(
        window: TrackedWindow,
        meta: WindowMetadata,
        resolved: ResolvedRule,
        deadline: Date?,
        status: ScheduleStatus
    ) -> WindowSchedule {
        WindowSchedule(
            key: window.key,
            bundleID: window.bundleID,
            appName: window.appName,
            title: DefaultWindowNames.effectiveTitle(
                axTitle: meta.title,
                bundleID: window.bundleID
            ),
            ruleSource: resolved.source,
            deadline: deadline,
            status: status
        )
    }

    private static func planAppQuits(
        input: PlanInput,
        actions: inout [PlannedAction],
        wakeCandidates: inout [Date]
    ) {
        // Skipped entirely when paused or no permission
        guard !input.isPaused, input.hasPermission else { return }

        for app in input.state.apps.values {
            guard app.bundleID != "com.apple.finder" else { continue }

            let resolved = input.ruleSet.resolve(bundleID: app.bundleID)
            guard resolved.rule.isEnabled,
                  resolved.source == .app,
                  app.quitState == .none,
                  app.pid != input.state.frontmostPID
            else {
                continue
            }

            planQuitForApp(app: app, policy: resolved.rule.quitPolicy, input: input, actions: &actions, wakeCandidates: &wakeCandidates)
        }
    }

    private static func planQuitForApp(
        app: TrackedApp,
        policy: QuitPolicy,
        input: PlanInput,
        actions: inout [PlannedAction],
        wakeCandidates: inout [Date]
    ) {
        switch policy {
        case .always:
            guard app.hadStandardWindow, let since = app.noStandardWindowsSince else { return }
            let quitAt = since.addingTimeInterval(Tracker.alwaysQuitGrace)
            if input.now >= quitAt {
                actions.append(.quitApp(pid: app.pid))
            } else {
                wakeCandidates.append(quitAt)
            }

        case .ifClosedBySqueegee:
            let presentCount = presentWindowCount(pid: app.pid, state: input.state)
            if app.quitAfterSqueegeeClose, presentCount == 0 {
                actions.append(.quitApp(pid: app.pid))
            }

        case .never:
            break
        }
    }

    private static func presentWindowCount(pid: Int32, state: TrackerState) -> Int {
        state.windows.values.count(where: { window in
            window.key.pid == pid && (window.metadata == nil || window.metadata?.isStandard == true)
        })
    }

    /// Sorts schedules by deadline ascending (nil last), then appName, then title.
    private static func sortSchedules(_ schedules: inout [WindowSchedule]) {
        schedules.sort { lhs, rhs in
            switch (lhs.deadline, rhs.deadline) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate { return lhsDate < rhsDate }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                break
            }
            if lhs.appName != rhs.appName {
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
            let lhsTitle = lhs.title ?? ""
            let rhsTitle = rhs.title ?? ""
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
    }

    /// Returns the effective last-active time for a window, accounting for
    /// an ongoing qualifying focus session.
    private static func effectiveLastActive(
        window: TrackedWindow,
        session: FocusSession?,
        now: Date
    ) -> Date? {
        if let session, session.key == window.key,
           now.timeIntervalSince(session.start) >= Tracker.focusQualifyingDuration
        {
            return now
        }
        return window.lastActive
    }
}
