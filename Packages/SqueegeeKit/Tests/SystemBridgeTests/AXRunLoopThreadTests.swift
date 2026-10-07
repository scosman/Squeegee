import Foundation
import Testing
@testable import SystemBridge

@Suite("AXRunLoopThread")
struct AXRunLoopThreadTests {
    @Test("perform runs work off the main thread and returns its result")
    @MainActor
    func performRunsOffMain() async {
        let worker = AXRunLoopThread(name: "test.ax-worker")
        let (isMain, name) = await worker.perform {
            (Thread.isMainThread, Thread.current.name)
        }
        #expect(!isMain)
        #expect(name == "test.ax-worker")
    }

    @Test("work runs in submission order")
    func workRunsInOrder() async {
        final class Log: @unchecked Sendable {
            var entries: [Int] = []
        }
        let worker = AXRunLoopThread(name: "test.ax-worker-order")
        let log = Log()
        for index in 0 ..< 20 {
            worker.enqueue { log.entries.append(index) }
        }
        // FIFO: this runs after all enqueued work.
        let entries = await worker.perform { log.entries }
        #expect(entries == Array(0 ..< 20))
    }
}
