import XCTest
@testable import OOTContent

final class OOTContentTests: XCTestCase {
    func testContentLoaderConformsToProtocol() {
        let loader: any ContentLoading = ContentLoader()

        XCTAssertNotNil(loader)
    }
}
