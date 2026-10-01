import ApplicationServices
import Testing
@testable import Engine
@testable import SystemBridge

@Suite("AX error mapping")
struct AXErrorMappingTests {
    @Test("success returns nil (no error)")
    func successReturnsNil() {
        #expect(AXHelpers.mapCopyError(.success) == nil)
    }

    @Test("apiDisabled returns notTrusted")
    func apiDisabled() {
        #expect(AXHelpers.mapCopyError(.apiDisabled) == .notTrusted)
    }

    @Test("cannotComplete returns appUnavailable")
    func cannotComplete() {
        #expect(AXHelpers.mapCopyError(.cannotComplete) == .appUnavailable)
    }

    @Test("notImplemented returns appUnavailable")
    func notImplemented() {
        #expect(AXHelpers.mapCopyError(.notImplemented) == .appUnavailable)
    }

    @Test("invalidUIElement returns appUnavailable")
    func invalidUIElement() {
        #expect(AXHelpers.mapCopyError(.invalidUIElement) == .appUnavailable)
    }

    @Test("noValue returns inspected with empty map")
    func noValue() {
        #expect(AXHelpers.mapCopyError(.noValue) == .inspected([:]))
    }

    @Test("unknown error returns appUnavailable")
    func unknownError() {
        #expect(AXHelpers.mapCopyError(.failure) == .appUnavailable)
    }
}
