import Testing
@testable import Engine

@Test func engineModuleLoads() {
    // Verifies the module links correctly
    let key = WindowKey(pid: 1, windowID: 1)
    #expect(key.pid == 1)
}
