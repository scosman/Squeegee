import Dispatch
import Engine
import Foundation

/// Implements `AppScheduler` using `DispatchSource` timers on the main queue.
///
/// - One-shot timers use `DispatchWallTime` so the deadline stays correct
///   across system sleep.
/// - Repeating timers use `DispatchTime` (monotonic).
public struct LiveAppScheduler: AppScheduler, Sendable {
    public init() {}

    public func now() -> Date {
        Date()
    }

    @MainActor
    public func schedule(
        at date: Date,
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let deadline = DispatchWallTime(date: date)
        timer.schedule(wallDeadline: deadline, leeway: .nanoseconds(Int(tolerance * 1_000_000_000)))
        timer.setEventHandler { action() }
        timer.resume()
        return DispatchSourceCancellable(source: timer)
    }

    @MainActor
    public func schedule(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .nanoseconds(Int(tolerance * 1_000_000_000))
        )
        timer.setEventHandler { action() }
        timer.resume()
        return DispatchSourceCancellable(source: timer)
    }
}

/// A `Cancellable` wrapper around a `DispatchSourceTimer`.
private final class DispatchSourceCancellable: Engine.Cancellable, @unchecked Sendable {
    private let source: DispatchSourceTimer

    init(source: DispatchSourceTimer) {
        self.source = source
    }

    func cancel() {
        source.cancel()
    }
}

// MARK: - DispatchWallTime convenience

private extension DispatchWallTime {
    init(date: Date) {
        let interval = date.timeIntervalSince1970
        let seconds = Int(interval)
        let nanoseconds = Int((interval - Double(seconds)) * 1_000_000_000)
        let timespec = timespec(tv_sec: seconds, tv_nsec: nanoseconds)
        self.init(timespec: timespec)
    }
}
