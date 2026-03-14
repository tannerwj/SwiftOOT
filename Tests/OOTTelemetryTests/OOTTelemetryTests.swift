import XCTest
@testable import OOTTelemetry

final class OOTTelemetryTests: XCTestCase {
    func testTelemetryPublisherConformsToProtocol() {
        let publisher: any TelemetryPublishing = TelemetryPublisher()

        XCTAssertNotNil(publisher)
    }
}
