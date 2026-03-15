import XCTest
import OOTContent
import OOTDataModel

final class MessageLoaderTests: XCTestCase {
    func testMessageLoaderReadsArrayCatalogFromMessagesDirectory() throws {
        let fixture = try MessageLoaderFixture(
            relativePath: "Messages/messages.json",
            json: """
            [
              {
                "id": "0x1000",
                "variant": "blue",
                "segments": [
                  { "type": "text", "text": "Hello " },
                  { "type": "playerName" }
                ]
              }
            ]
            """
        )

        let catalog = try MessageLoader(contentRoot: fixture.contentRoot).loadMessageCatalog()

        XCTAssertEqual(catalog[0x1000]?.variant, .blue)
        XCTAssertEqual(
            catalog[0x1000]?.segments,
            [
                .text("Hello "),
                .playerName,
            ]
        )
    }

    func testMessageLoaderReadsKeyedCatalogFromManifestPath() throws {
        let fixture = try MessageLoaderFixture(
            relativePath: "Manifests/messages.json",
            json: """
            {
              "messages": {
                "0x1001": {
                  "boxVariant": "red",
                  "text": "Need something?",
                  "choices": ["Yes", "No"]
                }
              }
            }
            """
        )

        let catalog = try MessageLoader(contentRoot: fixture.contentRoot).loadMessageCatalog()

        XCTAssertEqual(catalog[0x1001]?.variant, .red)
        XCTAssertEqual(
            catalog[0x1001]?.segments,
            [
                .text("Need something?"),
                .choice([
                    MessageChoiceOption(title: "Yes"),
                    MessageChoiceOption(title: "No"),
                ]),
            ]
        )
    }
}

private struct MessageLoaderFixture {
    let contentRoot: URL

    init(
        relativePath: String,
        json: String
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        contentRoot = root

        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try XCTUnwrap(json.data(using: .utf8))
        try data.write(to: fileURL)
    }
}
