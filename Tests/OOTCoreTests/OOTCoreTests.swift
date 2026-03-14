import XCTest
@testable import OOTCore

final class OOTCoreTests: XCTestCase {
    @MainActor
    func testGameRuntimeStartsIdle() {
        let runtime = GameRuntime()

        XCTAssertEqual(runtime.state, .idle)
    }
}
