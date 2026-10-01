import CoreGraphics
import Testing
@testable import SystemBridge

@Suite("Fallback bounds matching")
struct BoundsMatchingTests {
    private func candidate(_ windowID: UInt32, _ rect: CGRect) -> (windowID: UInt32, bounds: CGRect) {
        (windowID: windowID, bounds: rect)
    }

    @Test("Unique match returns the window ID")
    func uniqueMatch() {
        let candidates = [
            candidate(10, CGRect(x: 100, y: 200, width: 800, height: 600)),
            candidate(20, CGRect(x: 500, y: 300, width: 400, height: 300))
        ]
        let result = AXHelpers.matchBounds(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 800, height: 600),
            candidates: candidates
        )
        #expect(result == 10)
    }

    @Test("Match within 2 pt tolerance")
    func withinTolerance() {
        let candidates = [
            candidate(10, CGRect(x: 100, y: 200, width: 800, height: 600))
        ]
        let result = AXHelpers.matchBounds(
            position: CGPoint(x: 101.5, y: 198.5),
            size: CGSize(width: 801, height: 599),
            candidates: candidates
        )
        #expect(result == 10)
    }

    @Test("No match returns nil")
    func noMatch() {
        let candidates = [
            candidate(10, CGRect(x: 100, y: 200, width: 800, height: 600))
        ]
        let result = AXHelpers.matchBounds(
            position: CGPoint(x: 500, y: 500),
            size: CGSize(width: 800, height: 600),
            candidates: candidates
        )
        #expect(result == nil)
    }

    @Test("Ambiguous match returns nil")
    func ambiguousMatch() {
        // Two windows at nearly the same position
        let candidates = [
            candidate(10, CGRect(x: 100, y: 200, width: 800, height: 600)),
            candidate(20, CGRect(x: 101, y: 201, width: 800, height: 600))
        ]
        let result = AXHelpers.matchBounds(
            position: CGPoint(x: 100.5, y: 200.5),
            size: CGSize(width: 800, height: 600),
            candidates: candidates
        )
        #expect(result == nil)
    }

    @Test("Empty candidates returns nil")
    func emptyCandidates() {
        let result = AXHelpers.matchBounds(
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 800, height: 600),
            candidates: []
        )
        #expect(result == nil)
    }
}
