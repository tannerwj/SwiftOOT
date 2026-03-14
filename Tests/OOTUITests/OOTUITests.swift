import XCTest
@testable import OOTUI

@MainActor
final class OOTUITests: XCTestCase {
    func testAppViewCompiles() {
        _ = OOTAppView()
        _ = DebugSidebar()
    }
}
