import Foundation
import XCTest
@testable import OOTExtractCLI
import OOTDataModel

final class TableExtractorTests: XCTestCase {
    func testParserStripsCommentsAndSkipsDisabledDebugAssets() throws {
        let parser = CHeaderParser()
        let text = """
        /* 0x00 */ DEFINE_SCENE(foo_scene, title_a, SCENE_FOO, SDC_DEFAULT, 0, 0) // keep
        #if DEBUG_ASSETS
        /* 0x01 */ DEFINE_SCENE(debug_scene, none, SCENE_DEBUG, SDC_DEFAULT, 0, 0)
        #endif
        /* 0x02 */ DEFINE_OBJECT_UNSET(OBJECT_INVALID) // trailing comment
        """

        let sceneMacros = try parser.parseMacros(in: text, matching: ["DEFINE_SCENE"])
        let objectMacros = try parser.parseMacros(in: text, matching: ["DEFINE_OBJECT_UNSET"])

        XCTAssertEqual(sceneMacros.count, 1)
        XCTAssertEqual(sceneMacros[0].tableIndex, 0)
        XCTAssertEqual(sceneMacros[0].arguments, ["foo_scene", "title_a", "SCENE_FOO", "SDC_DEFAULT", "0", "0"])
        XCTAssertEqual(objectMacros.count, 1)
        XCTAssertEqual(objectMacros[0].arguments, ["OBJECT_INVALID"])
    }

    func testExtractorWritesAndVerifiesTableManifestsFromFixtureHeaders() throws {
        let fixture = try makeFixtureSource()
        let output = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: output)
        }

        let extractor = TableExtractor(
            expectedCounts: TableManifestCounts(scenes: 1, actors: 3, objects: 3)
        )

        try extractor.extract(using: OOTExtractionContext(source: fixture, output: output))
        try extractor.verify(using: OOTVerificationContext(content: output))

        let tablesDirectory = output
            .appendingPathComponent("Manifests")
            .appendingPathComponent("tables")

        let scenes = try decode([SceneTableEntry].self, from: tablesDirectory.appendingPathComponent("scene-table.json"))
        let actors = try decode([ActorTableEntry].self, from: tablesDirectory.appendingPathComponent("actor-table.json"))
        let objects = try decode([ObjectTableEntry].self, from: tablesDirectory.appendingPathComponent("object-table.json"))

        XCTAssertEqual(scenes, [
            SceneTableEntry(index: 0, enumName: "SCENE_FOO", title: "title_card", drawConfig: 0),
        ])
        XCTAssertEqual(actors, [
            ActorTableEntry(
                id: 0,
                enumName: "ACTOR_FOO",
                profile: ActorProfile(id: 0, category: 0, flags: 0, objectID: 0),
                overlayName: "En_Foo"
            ),
            ActorTableEntry(
                id: 1,
                enumName: "ACTOR_BAR",
                profile: ActorProfile(id: 1, category: 0, flags: 0, objectID: 0),
                overlayName: "Player"
            ),
            ActorTableEntry(
                id: 2,
                enumName: "ACTOR_UNSET_2",
                profile: ActorProfile(id: 2, category: 0, flags: 0, objectID: 0),
                overlayName: nil
            ),
        ])
        XCTAssertEqual(objects, [
            ObjectTableEntry(id: 0, enumName: "OBJECT_FOO", assetPath: "objects/object_foo"),
            ObjectTableEntry(id: 1, enumName: "OBJECT_BAR_UNUSED", assetPath: "objects/object_bar"),
            ObjectTableEntry(id: 2, enumName: "OBJECT_INVALID", assetPath: ""),
        ])
    }

    func testVerifyFailsWhenManifestCountsDoNotMatchExpectation() throws {
        let fixture = try makeFixtureSource()
        let output = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: output)
        }

        let extractor = TableExtractor(
            expectedCounts: TableManifestCounts(scenes: 1, actors: 3, objects: 3)
        )
        try extractor.extract(using: OOTExtractionContext(source: fixture, output: output))

        let mismatchedVerifier = TableExtractor(
            expectedCounts: TableManifestCounts(scenes: 1, actors: 4, objects: 3)
        )

        XCTAssertThrowsError(try mismatchedVerifier.verify(using: OOTVerificationContext(content: output))) { error in
            guard let extractorError = error as? TableExtractorError else {
                return XCTFail("Unexpected error type: \(error)")
            }

            guard case .countMismatch(let kind, let expected, let actual) = extractorError else {
                return XCTFail("Unexpected extractor error: \(extractorError)")
            }

            XCTAssertEqual(kind, "actor")
            XCTAssertEqual(expected, 4)
            XCTAssertEqual(actual, 3)
        }
    }

    private func makeFixtureSource() throws -> URL {
        let root = try makeTemporaryDirectory()
        let includeTables = root
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
        try FileManager.default.createDirectory(at: includeTables, withIntermediateDirectories: true)

        try write(
            """
            typedef enum SceneDrawConfig {
                /* 0 */ SDC_DEFAULT,
                /* 1 */ SDC_CUSTOM,
                /* 2 */ SDC_MAX
            } SceneDrawConfig;
            """,
            to: root.appendingPathComponent("include").appendingPathComponent("scene.h")
        )

        try write(
            """
            /* 0x00 */ DEFINE_SCENE(foo_scene, title_card, SCENE_FOO, SDC_DEFAULT, 0, 0)
            #if DEBUG_ASSETS
            /* 0x01 */ DEFINE_SCENE(debug_scene, none, SCENE_DEBUG, SDC_CUSTOM, 0, 0)
            #endif
            """,
            to: includeTables.appendingPathComponent("scene_table.h")
        )

        try write(
            """
            /* 0x0000 */ DEFINE_ACTOR(En_Foo, ACTOR_FOO, ACTOROVL_ALLOC_NORMAL, \"En_Foo\")
            /* 0x0001 */ DEFINE_ACTOR_INTERNAL(Player, ACTOR_BAR, ACTOROVL_ALLOC_NORMAL, \"Player\")
            /* 0x0002 */ DEFINE_ACTOR_UNSET(ACTOR_UNSET_2)
            """,
            to: includeTables.appendingPathComponent("actor_table.h")
        )

        try write(
            """
            /* 0x0000 */ DEFINE_OBJECT(object_foo, OBJECT_FOO)
            /* 0x0001 */ DEFINE_OBJECT_EMPTY(object_bar, OBJECT_BAR_UNUSED)
            /* 0x0002 */ DEFINE_OBJECT_UNSET(OBJECT_INVALID)
            """,
            to: includeTables.appendingPathComponent("object_table.h")
        )

        return root
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}
