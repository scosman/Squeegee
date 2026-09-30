import Engine
import Foundation

/// A deterministic scheduler for tests. Holds a manual `now` and fires
/// scheduled actions when `advance(to:)` / `advance(by:)` moves past their
/// fire date.
@MainActor
public final class FakeScheduler: AppScheduler, @unchecked Sendable {
    public private(set) var currentDate: Date

    private var nextID: UInt64 = 0
    private var oneShots: [ScheduledAction] = []
    private var repeating: [RepeatingAction] = []

    public init(now: Date) {
        currentDate = now
    }

    // MARK: - AppScheduler

    public nonisolated func now() -> Date {
        // This is called from @MainActor contexts in AppCore. We use an
        // unsafe approach here since tests are single-threaded in practice.
        MainActor.assumeIsolated { currentDate }
    }

    public func schedule(
        at date: Date,
        tolerance _: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Engine.Cancellable {
        let id = issueID()
        let entry = ScheduledAction(id: id, fireDate: date, action: action)
        oneShots.append(entry)
        return FakeCancellable { [weak self] in
            self?.oneShots.removeAll { $0.id == id }
        }
    }

    public func schedule(
        every interval: TimeInterval,
        tolerance _: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Engine.Cancellable {
        let id = issueID()
        let nextFire = currentDate.addingTimeInterval(interval)
        let entry = RepeatingAction(id: id, interval: interval, nextFire: nextFire, action: action)
        repeating.append(entry)
        return FakeCancellable { [weak self] in
            self?.repeating.removeAll { $0.id == id }
        }
    }

    // MARK: - Test controls

    /// Advances time to the given date, firing all due actions in time order.
    public func advance(to target: Date) {
        guard target > currentDate else { return }
        // Fire actions in time order until we pass the target
        while true {
            let nextOneShot = oneShots.filter { $0.fireDate <= target }.min(by: { $0.fireDate < $1.fireDate })
            let nextRepeat = repeating.filter { $0.nextFire <= target }.min(by: { $0.nextFire < $1.nextFire })

            let nextDate: Date
            switch (nextOneShot?.fireDate, nextRepeat?.nextFire) {
            case let (oneShotDate?, repeatDate?): nextDate = min(oneShotDate, repeatDate)
            case let (oneShotDate?, nil): nextDate = oneShotDate
            case let (nil, repeatDate?): nextDate = repeatDate
            case (nil, nil):
                currentDate = target
                return
            }

            currentDate = nextDate

            // Fire all one-shots at this exact date
            let dueOneShots = oneShots.filter { $0.fireDate <= currentDate }
            for entry in dueOneShots {
                oneShots.removeAll { $0.id == entry.id }
                entry.action()
            }

            // Fire all repeating timers at this exact date
            for idx in repeating.indices where repeating[idx].nextFire <= currentDate {
                repeating[idx].action()
                repeating[idx].nextFire = currentDate.addingTimeInterval(repeating[idx].interval)
            }
        }
    }

    /// Advances time by the given interval.
    public func advance(by interval: TimeInterval) {
        advance(to: currentDate.addingTimeInterval(interval))
    }

    /// The number of pending one-shot timers.
    public var pendingOneShotCount: Int {
        oneShots.count
    }

    /// The number of active repeating timers.
    public var activeRepeatingCount: Int {
        repeating.count
    }

    // MARK: - Private

    private func issueID() -> UInt64 {
        let id = nextID
        nextID += 1
        return id
    }

    private struct ScheduledAction {
        let id: UInt64
        let fireDate: Date
        let action: @MainActor () -> Void
    }

    private struct RepeatingAction {
        let id: UInt64
        let interval: TimeInterval
        var nextFire: Date
        let action: @MainActor () -> Void
    }
}

// MARK: - Cancellable

private final class FakeCancellable: Engine.Cancellable, @unchecked Sendable {
    private var onCancel: (@MainActor () -> Void)?

    init(_ onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        MainActor.assumeIsolated {
            onCancel?()
            onCancel = nil
        }
    }
}
