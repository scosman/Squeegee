import Foundation
import ManualTestKit
import Testing

@Suite("ResultsStore")
struct ResultsStoreTests {
    private func makeStore() -> ResultsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManualTestKitTests-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("test_results.json")
        return ResultsStore(fileURL: url)
    }

    @Test("Load returns empty dictionary when file does not exist")
    func loadMissingFile() throws {
        let store = makeStore()
        let results = try store.load()
        #expect(results.isEmpty)
    }

    @Test("Round-trip: save then load preserves results")
    func roundTrip() throws {
        let store = makeStore()
        let result1 = TestResult(stepID: "step_a", status: .pass, note: "ok")
        let result2 = TestResult(stepID: "step_b", status: .fail, note: "broken")
        try store.save(["step_a": result1, "step_b": result2])

        let loaded = try store.load()
        #expect(loaded.count == 2)
        #expect(loaded["step_a"]?.status == .pass)
        #expect(loaded["step_a"]?.note == "ok")
        #expect(loaded["step_b"]?.status == .fail)
    }

    @Test("Record merges into existing results")
    func recordMerges() throws {
        let store = makeStore()
        let existing = TestResult(stepID: "step_a", status: .pass)
        try store.save(["step_a": existing])

        let newResult = TestResult(stepID: "step_b", status: .fail, note: "new")
        try store.record(newResult)

        let loaded = try store.load()
        #expect(loaded.count == 2)
        #expect(loaded["step_a"]?.status == .pass)
        #expect(loaded["step_b"]?.status == .fail)
    }

    @Test("Record overwrites an existing entry for the same step ID")
    func recordOverwrites() throws {
        let store = makeStore()
        try store.record(TestResult(stepID: "step_a", status: .fail))
        try store.record(TestResult(stepID: "step_a", status: .pass, note: "fixed"))

        let loaded = try store.load()
        #expect(loaded["step_a"]?.status == .pass)
        #expect(loaded["step_a"]?.note == "fixed")
    }

    @Test("unrun finds missing and not-run steps")
    func unrunFindsGaps() throws {
        let store = makeStore()
        let scripts = [
            TestScript(id: "test", title: "Test", steps: [
                .humanQuestion(id: "q1", prompt: "?"),
                .humanQuestion(id: "q2", prompt: "?"),
                .humanQuestion(id: "q3", prompt: "?")
            ])
        ]

        // q1 is pass, q2 is not-run, q3 is missing entirely
        try store.save([
            "q1": TestResult(stepID: "q1", status: .pass),
            "q2": TestResult(stepID: "q2", status: .notRun)
        ])

        let unrun = try store.unrun(in: scripts)
        #expect(unrun.contains("q2"))
        #expect(unrun.contains("q3"))
        #expect(!unrun.contains("q1"))
    }

    @Test("markScriptNotRun resets steps to not-run")
    func markNotRun() throws {
        let store = makeStore()
        try store.save([
            "q1": TestResult(stepID: "q1", status: .pass),
            "q2": TestResult(stepID: "q2", status: .pass)
        ])

        try store.markScriptNotRun(scriptID: "test", allStepIDs: ["q1", "q2"])

        let loaded = try store.load()
        #expect(loaded["q1"]?.status == .notRun)
        #expect(loaded["q2"]?.status == .notRun)
    }

    @Test("recordableStepIDs excludes instruction steps")
    func recordableExcludesInstructions() {
        let store = makeStore()
        let scripts = [
            TestScript(id: "test", title: "Test", steps: [
                .instruction(id: "info", text: "Read this"),
                .humanQuestion(id: "q1", prompt: "?"),
                .autoCheck(id: "c1", label: "check") { CheckOutcome(passed: true, detail: "ok") }
            ])
        ]

        let ids = store.recordableStepIDs(in: scripts)
        #expect(ids == ["q1", "c1"])
        #expect(!ids.contains("info"))
    }

    @Test("allStepIDs includes instruction steps")
    func allStepIDsIncludesInstructions() {
        let store = makeStore()
        let scripts = [
            TestScript(id: "test", title: "Test", steps: [
                .instruction(id: "info", text: "Read this"),
                .humanQuestion(id: "q1", prompt: "?")
            ])
        ]

        let ids = store.allStepIDs(in: scripts)
        #expect(ids == ["info", "q1"])
    }
}
