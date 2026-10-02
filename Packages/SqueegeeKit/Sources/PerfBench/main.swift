import AppCore
import CoreGraphics
import Darwin
import Engine
import Foundation
import Persistence
import TestSupport

// MARK: - CLI

enum Scenario: String, CaseIterable {
    case churn, idle, scale
}

struct CLIOptions {
    var scenarios: [Scenario] = Scenario.allCases
    var repeatCount: Int = 5
}

func parseArgs() -> CLIOptions {
    var opts = CLIOptions()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--scenario":
            guard !args.isEmpty else { fatalError("--scenario requires a value") }
            let value = args.removeFirst()
            if value == "all" {
                opts.scenarios = Scenario.allCases
            } else if let scenario = Scenario(rawValue: value) {
                opts.scenarios = [scenario]
            } else {
                fatalError("Unknown scenario: \(value). Use churn|idle|scale|all.")
            }
        case "--repeat":
            guard !args.isEmpty else { fatalError("--repeat requires a value") }
            guard let count = Int(args.removeFirst()), count > 0 else {
                fatalError("--repeat must be a positive integer")
            }
            opts.repeatCount = count
        default:
            fatalError("Unknown argument: \(arg)")
        }
    }
    return opts
}

// MARK: - CPU measurement

func cpuTimeMs() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let userMs = Double(usage.ru_utime.tv_sec) * 1000.0 + Double(usage.ru_utime.tv_usec) / 1000.0
    let sysMs = Double(usage.ru_stime.tv_sec) * 1000.0 + Double(usage.ru_stime.tv_usec) / 1000.0
    return userMs + sysMs
}

// MARK: - Window / app factories

let benchAppCount = 10

func makeBundleID(_ index: Int) -> String {
    "bench.app\(index)"
}

func makeApp(index: Int, launchDate: Date) -> ObservedApp {
    let pid = Int32(1001 + index)
    return ObservedApp(pid: pid, bundleID: makeBundleID(index), name: "App\(index)", launchDate: launchDate)
}

func makeWindows(count windowCount: Int, launchDate: Date) -> [ObservedWindow] {
    var windows: [ObservedWindow] = []
    for idx in 0 ..< windowCount {
        let appIndex = idx % benchAppCount
        let app = makeApp(index: appIndex, launchDate: launchDate)
        let windowID = UInt32(idx + 1)
        windows.append(ObservedWindow(
            key: WindowKey(pid: app.pid, windowID: windowID),
            app: app,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        ))
    }
    return windows
}

func makeInspectionResults(windows: [ObservedWindow]) -> [Int32: InspectionResult] {
    var byPid: [Int32: [UInt32: WindowMetadata]] = [:]
    for window in windows {
        byPid[window.key.pid, default: [:]][window.key.windowID] = WindowMetadata(
            isStandard: true,
            title: "Window \(window.key.windowID)"
        )
    }
    return byPid.mapValues { .inspected($0) }
}

// MARK: - Store setup

@MainActor
func makeStore() -> (store: Store, tempDir: URL) {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bench-\(UUID().uuidString)")
    do {
        let store = try Store(configuration: .onDisk(tempDir))
        return (store, tempDir)
    } catch {
        fatalError("Failed to create benchmark store: \(error)")
    }
}

func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

@MainActor
func configureStore(_ store: Store) {
    store.settings.globalIsEnabled = true
    store.settings.globalCloseAfterSeconds = 6 * 3600
    store.settings.globalMeasureFromRaw = "lastActive"

    store.addAppRule(bundleID: makeBundleID(0), appName: "App0", rule: Rule(
        isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never
    ))
    store.addAppRule(bundleID: makeBundleID(1), appName: "App1", rule: Rule(
        isEnabled: true, closeAfter: 8 * 3600, measureFrom: .lastActive, quitPolicy: .never
    ))
    store.addAppRule(bundleID: makeBundleID(2), appName: "App2", rule: Rule(
        isEnabled: true, closeAfter: 12 * 3600, measureFrom: .lastActive, quitPolicy: .never
    ))
    store.save()
}

// MARK: - Scenarios

struct RepeatResult {
    let cpuMs: Double
    let events: Int
    let tempDir: URL
}

struct ScenarioResult {
    let name: String
    let cpuMs: [Double]
    let events: Int
}

let dwellTimes: [TimeInterval] = [3, 8, 20, 45]

@MainActor
func runChurn(windowCount: Int, epoch: Date, bundle: FakePortsBundle) async -> RepeatResult {
    let windows = makeWindows(count: windowCount, launchDate: epoch)
    bundle.windowLister.windows = windows
    bundle.windowInspector.inspectionResults = makeInspectionResults(windows: windows)
    bundle.windowInspector.focusedWindowIDs = [:]
    bundle.permission.trusted = true

    let firstApp = makeApp(index: 0, launchDate: epoch)
    bundle.workspace.frontmost = firstApp
    bundle.windowInspector.focusedWindowIDs[firstApp.pid] = windows[0].key.windowID

    let (store, tempDir) = makeStore()
    configureStore(store)

    let core = AppCore(store: store, ports: bundle.ports)
    await core.start()
    await settle()

    let churnResult = await runChurnLoop(
        windows: windows, bundle: bundle, firstPid: firstApp.pid, windowCount: windowCount
    )

    // Suppress unused-variable warning — core must stay alive during the timed section
    _ = core

    bundle.workspace.finish()
    bundle.focus.finish()
    bundle.permission.finish()

    return RepeatResult(cpuMs: churnResult.cpuMs, events: churnResult.events, tempDir: tempDir)
}

@MainActor
func runChurnLoop(
    windows: [ObservedWindow],
    bundle: FakePortsBundle,
    firstPid: Int32,
    windowCount: Int
) async -> (cpuMs: Double, events: Int) {
    var currentFrontPid = firstPid
    let switchCount = 300
    var events = 0
    var totalDwell: TimeInterval = 0

    let startCPU = cpuTimeMs()

    for idx in 0 ..< switchCount {
        let targetIndex = (idx * 7) % windowCount
        let targetWindow = windows[targetIndex]
        let targetPid = targetWindow.key.pid

        bundle.windowInspector.focusedWindowIDs[targetPid] = targetWindow.key.windowID

        if targetPid != currentFrontPid {
            let targetApp = targetWindow.app
            bundle.workspace.frontmost = targetApp
            bundle.workspace.send(.appActivated(targetApp))
            events += 1
            await settle()
            currentFrontPid = targetPid
        }

        let now = bundle.scheduler.now()
        bundle.focus.send(FocusSignal(pid: targetPid, kind: .focusMayHaveChanged, at: now))
        events += 1
        await settle()
        bundle.focus.send(FocusSignal(pid: targetPid, kind: .focusMayHaveChanged, at: now))
        events += 1
        await settle()

        let dwellTime = dwellTimes[idx % 4]
        totalDwell += dwellTime
        bundle.scheduler.advance(by: dwellTime)
        await settle()
    }

    // Scan ticks derived from total fake time advanced (one tick per 60 s)
    let scanTicks = Int(totalDwell / 60)
    events += scanTicks

    let endCPU = cpuTimeMs()
    return (cpuMs: endCPU - startCPU, events: events)
}

@MainActor
func runIdle(windowCount: Int, epoch: Date, bundle: FakePortsBundle) async -> RepeatResult {
    let windows = makeWindows(count: windowCount, launchDate: epoch)
    bundle.windowLister.windows = windows
    bundle.windowInspector.inspectionResults = makeInspectionResults(windows: windows)
    bundle.permission.trusted = true

    let firstApp = makeApp(index: 0, launchDate: epoch)
    bundle.workspace.frontmost = firstApp
    bundle.windowInspector.focusedWindowIDs[firstApp.pid] = windows[0].key.windowID

    let (store, tempDir) = makeStore()
    configureStore(store)

    let core = AppCore(store: store, ports: bundle.ports)
    await core.start()
    await settle()

    let ticks = 60
    var events = 0

    let startCPU = cpuTimeMs()

    for _ in 0 ..< ticks {
        bundle.scheduler.advance(by: 60)
        events += 1
        await settle()
    }

    let endCPU = cpuTimeMs()

    // Suppress unused-variable warning — core must stay alive during the timed section
    _ = core

    bundle.workspace.finish()
    bundle.focus.finish()
    bundle.permission.finish()

    return RepeatResult(cpuMs: endCPU - startCPU, events: events, tempDir: tempDir)
}

// MARK: - Runner

@MainActor
func runScenario(
    _ scenario: Scenario,
    repeatCount: Int
) async -> ScenarioResult {
    var cpuSamples: [Double] = []
    var eventCount: Int?

    for _ in 0 ..< repeatCount {
        // 2026-01-01 ~09:00 UTC
        let epoch = Date(timeIntervalSinceReferenceDate: 789_000_000)
        let bundle = FakePortsBundle(now: epoch)

        let result: RepeatResult = switch scenario {
        case .churn:
            await runChurn(windowCount: 50, epoch: epoch, bundle: bundle)
        case .idle:
            await runIdle(windowCount: 50, epoch: epoch, bundle: bundle)
        case .scale:
            await runChurn(windowCount: 300, epoch: epoch, bundle: bundle)
        }

        cpuSamples.append(result.cpuMs)
        if let existing = eventCount {
            assert(existing == result.events, "Event count changed between repeats")
        }
        eventCount = result.events
        removeTempDir(result.tempDir)
    }

    return ScenarioResult(name: scenario.rawValue, cpuMs: cpuSamples, events: eventCount ?? 0)
}

// MARK: - Output

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let count = sorted.count
    if count == 0 { return 0 }
    if count % 2 == 0 {
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }
    return sorted[count / 2]
}

func printResults(_ results: [ScenarioResult]) {
    print("| Scenario | Repeats | Median CPU (ms) | Min CPU (ms) | Events | us/event (median) |")
    print("|---|---:|---:|---:|---:|---:|")
    for result in results {
        let med = median(result.cpuMs)
        let minVal = result.cpuMs.min() ?? 0
        let usPerEvent = result.events > 0 ? (med * 1000.0 / Double(result.events)) : 0
        print(String(
            format: "| %@ | %d | %.1f | %.1f | %d | %.1f |",
            result.name,
            result.cpuMs.count,
            med,
            minVal,
            result.events,
            usPerEvent
        ))
    }
}

// MARK: - Entry point

let opts = parseArgs()

var results: [ScenarioResult] = []
for scenario in opts.scenarios {
    let result = await runScenario(scenario, repeatCount: opts.repeatCount)
    results.append(result)
}

printResults(results)
