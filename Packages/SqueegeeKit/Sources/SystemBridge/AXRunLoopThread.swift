import Foundation

/// A dedicated thread that runs a `CFRunLoop` for its whole life.
///
/// Used for blocking AX calls and for `AXObserver` run-loop sources, so that
/// neither runs on the main thread. Work submitted with `perform` or `enqueue`
/// runs in FIFO order on this thread.
final class AXRunLoopThread: @unchecked Sendable {
    private let runLoop: CFRunLoop

    init(name: String) {
        final class Handoff: @unchecked Sendable {
            var runLoop: CFRunLoop?
        }
        let handoff = Handoff()
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread {
            handoff.runLoop = CFRunLoopGetCurrent()
            // A run loop with no sources returns at once; this port keeps it alive.
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            while true {
                RunLoop.current.run()
            }
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()

        // The thread sets this before it signals `ready`.
        runLoop = handoff.runLoop! // swiftlint:disable:this force_unwrapping
    }

    /// Runs `work` on the thread and returns its result.
    func perform<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            enqueue { continuation.resume(returning: work()) }
        }
    }

    /// Schedules `work` on the thread without waiting for it.
    func enqueue(_ work: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }
}
