import CoreGraphics
import Testing
@testable import Engine
@testable import SystemBridge

@Suite("CGWindowLister.parse")
struct CGWindowListerParseTests {
    // MARK: - Test helpers

    private let ownPID: Int32 = 999

    private func makeApp(pid: Int32, bundleID: String = "com.example.app", name: String = "App") -> ObservedApp {
        ObservedApp(pid: pid, bundleID: bundleID, name: name, launchDate: nil)
    }

    private func makeWindowInfo(
        pid: Int32 = 100,
        windowID: UInt32 = 1,
        layer: Int = 0,
        alpha: Double = 1.0,
        originX: CGFloat = 0,
        originY: CGFloat = 0,
        width: CGFloat = 800,
        height: CGFloat = 600,
        isOnScreen: Bool = true,
        name: String? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowNumber as String: windowID,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: [
                "X": originX, "Y": originY,
                "Width": width, "Height": height
            ] as [String: Any],
            kCGWindowIsOnscreen as String: isOnScreen
        ]
        if let name {
            info[kCGWindowName as String] = name
        }
        return info
    }

    private func parse(
        _ infos: [[String: Any]],
        lookup: ((Int32) -> ObservedApp?)? = nil
    ) -> [ObservedWindow] {
        let defaultLookup: (Int32) -> ObservedApp? = { pid in
            makeApp(pid: pid)
        }
        return CGWindowLister.parse(infos, ownPID: ownPID, appLookup: lookup ?? defaultLookup)
    }

    // MARK: - Happy path

    @Test("Parses a valid window")
    func happyPath() {
        let infos = [makeWindowInfo(pid: 100, windowID: 42)]
        let result = parse(infos)

        #expect(result.count == 1)
        #expect(result[0].key == WindowKey(pid: 100, windowID: 42))
        #expect(result[0].isOnScreen == true)
        #expect(result[0].bounds.width == 800)
    }

    @Test("Multiple valid windows from different apps")
    func multipleWindows() {
        let infos = [
            makeWindowInfo(pid: 100, windowID: 1),
            makeWindowInfo(pid: 200, windowID: 2)
        ]
        let result = parse(infos) { pid in
            makeApp(pid: pid, bundleID: "com.example.\(pid)")
        }

        #expect(result.count == 2)
    }

    // MARK: - Filter: layer

    @Test("Filters out windows with layer != 0")
    func nonZeroLayer() {
        let infos = [makeWindowInfo(layer: 1)]
        let result = parse(infos)
        #expect(result.isEmpty)
    }

    // MARK: - Filter: alpha

    @Test("Filters out windows with alpha == 0")
    func zeroAlpha() {
        let infos = [makeWindowInfo(alpha: 0)]
        let result = parse(infos)
        #expect(result.isEmpty)
    }

    @Test("Keeps windows with alpha > 0")
    func positiveAlpha() {
        let infos = [makeWindowInfo(alpha: 0.01)]
        let result = parse(infos)
        #expect(result.count == 1)
    }

    // MARK: - Filter: own pid

    @Test("Filters out own pid")
    func ownPidFiltered() {
        let infos = [makeWindowInfo(pid: ownPID)]
        let result = parse(infos)
        #expect(result.isEmpty)
    }

    // MARK: - Filter: minimum size

    @Test("Filters windows smaller than 40x40")
    func tooSmall() {
        let small = [
            makeWindowInfo(width: 39, height: 600),
            makeWindowInfo(width: 800, height: 39),
            makeWindowInfo(width: 39, height: 39)
        ]
        for info in small {
            let result = parse([info])
            #expect(result.isEmpty, "Expected window with size \(info[kCGWindowBounds as String] ?? "?") to be filtered")
        }
    }

    @Test("Keeps windows at exactly 40x40")
    func exactMinimum() {
        let infos = [makeWindowInfo(width: 40, height: 40)]
        let result = parse(infos)
        #expect(result.count == 1)
    }

    // MARK: - Filter: app lookup

    @Test("Filters windows with no app from lookup")
    func noApp() {
        let infos = [makeWindowInfo()]
        let result = parse(infos) { _ in nil }
        #expect(result.isEmpty)
    }

    // MARK: - Filter: excluded bundle IDs

    @Test("Filters excluded system bundle IDs")
    func excludedBundles() {
        for bundleID in CGWindowLister.excludedBundleIDs {
            let infos = [makeWindowInfo(pid: 100)]
            let result = parse(infos) { pid in
                makeApp(pid: pid, bundleID: bundleID)
            }
            #expect(result.isEmpty, "Expected \(bundleID) to be filtered")
        }
    }

    @Test("Filters any Squeegee bundle prefix")
    func squeegeePrefix() {
        let bundleIDs = [
            "net.scosman.squeegee",
            "net.scosman.squeegee.manualtest",
            "net.scosman.squeegee.helper"
        ]
        for bundleID in bundleIDs {
            let infos = [makeWindowInfo(pid: 100)]
            let result = parse(infos) { pid in
                makeApp(pid: pid, bundleID: bundleID)
            }
            #expect(result.isEmpty, "Expected \(bundleID) to be filtered")
        }
    }

    // MARK: - Filter: missing keys

    @Test("Filters windows with missing layer key")
    func missingLayer() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowLayer as String)
        let result = parse([info])
        #expect(result.isEmpty)
    }

    @Test("Filters windows with missing alpha key")
    func missingAlpha() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowAlpha as String)
        let result = parse([info])
        #expect(result.isEmpty)
    }

    @Test("Filters windows with missing pid key")
    func missingPid() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowOwnerPID as String)
        let result = parse([info])
        #expect(result.isEmpty)
    }

    @Test("Filters windows with missing bounds key")
    func missingBounds() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowBounds as String)
        let result = parse([info])
        #expect(result.isEmpty)
    }

    @Test("Filters windows with missing window number key")
    func missingWindowNumber() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowNumber as String)
        let result = parse([info])
        #expect(result.isEmpty)
    }

    // MARK: - isOnScreen default

    @Test("isOnScreen defaults to false when missing")
    func isOnScreenDefault() {
        var info = makeWindowInfo()
        info.removeValue(forKey: kCGWindowIsOnscreen as String)
        let result = parse([info])
        #expect(result.count == 1)
        #expect(result[0].isOnScreen == false)
    }

    // MARK: - App caching

    @Test("App lookup is called once per pid")
    func appCaching() {
        let infos = [
            makeWindowInfo(pid: 100, windowID: 1),
            makeWindowInfo(pid: 100, windowID: 2),
            makeWindowInfo(pid: 100, windowID: 3)
        ]
        var callCount = 0
        _ = parse(infos) { pid in
            callCount += 1
            return makeApp(pid: pid)
        }
        #expect(callCount == 1)
    }
}
