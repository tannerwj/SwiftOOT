import XCTest
import OOTCore
@testable import OOTUI

@MainActor
final class OOTUITests: XCTestCase {
    func testAppViewCompiles() {
        _ = OOTAppView(runtime: GameRuntime(suspender: { _ in }))
        _ = DebugSidebar()
    }

    func testRootViewStateMatchesRuntimeState() {
        XCTAssertEqual(OOTAppView.rootViewState(for: .boot), .boot)
        XCTAssertEqual(OOTAppView.rootViewState(for: .consoleLogo), .consoleLogo)
        XCTAssertEqual(OOTAppView.rootViewState(for: .titleScreen), .titleScreen)
        XCTAssertEqual(OOTAppView.rootViewState(for: .fileSelect), .fileSelect)
        XCTAssertEqual(OOTAppView.rootViewState(for: .gameplay), .gameplay)
    }
}
