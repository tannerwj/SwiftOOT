import Foundation
import XCTest
@testable import OOTExtractSupport
import OOTDataModel

final class OOTContentExtractorTests: XCTestCase {
    func testExtractCompletesWhenDisplayListParserHitsMissingIncludeAfterSceneMetadata() throws {
        let source = try makeFixtureSource()
        let output = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let extractor = OOTContentExtractor(
            pipeline: [
                TableExtractor(expectedCounts: TableManifestCounts(scenes: 1, actors: 19, objects: 1)),
                SceneExtractor(),
                ObjectExtractor(),
                TextureExtractor(),
                ActorExtractor(),
                AudioExtractor(),
                TextExtractor(),
                CollisionExtractor(),
                DisplayListParser(),
                VertexParser(),
            ]
        )

        XCTAssertNoThrow(try extractor.extract(from: source, to: output))
        XCTAssertNoThrow(try extractor.verify(contentAt: output))

        let sceneDirectory = try metadataDirectory(in: output)
        let actors = try decode(SceneActorsFile.self, from: sceneDirectory.appendingPathComponent("actors.json"))
        let environment = try decode(SceneEnvironmentFile.self, from: sceneDirectory.appendingPathComponent("environment.json"))
        let paths = try decode(ScenePathsFile.self, from: sceneDirectory.appendingPathComponent("paths.json"))
        let exits = try decode(SceneExitsFile.self, from: sceneDirectory.appendingPathComponent("exits.json"))

        XCTAssertEqual(actors.sceneName, "spot04")
        XCTAssertEqual(actors.rooms.count, 1)
        XCTAssertEqual(actors.rooms[0].actors.count, 1)
        XCTAssertEqual(environment.lightSettings.count, 1)
        XCTAssertEqual(paths.paths.count, 1)
        XCTAssertEqual(exits.exits.count, 1)
    }

    private func makeFixtureSource() throws -> URL {
        let root = try makeTemporaryDirectory()

        try write(
            """
            typedef enum SceneDrawConfig {
                /* 0 */ SDC_DEFAULT,
                /* 1 */ SDC_MAX
            } SceneDrawConfig;
            """,
            to: root.appendingPathComponent("include").appendingPathComponent("scene.h")
        )

        try write(
            """
            /* 0x00 */ DEFINE_SCENE(spot04_scene, title_card, SCENE_SPOT04, SDC_DEFAULT, 0, 0)
            """,
            to: root.appendingPathComponent("include/tables/scene_table.h")
        )

        let actorNames = [
            "ACTOR_EN_RIVER_SOUND",
            "ACTOR_EN_ITEM00",
            "ACTOR_OBJECT_KANKYO",
            "ACTOR_EN_KO",
            "ACTOR_EN_GS",
            "ACTOR_EN_MD",
            "ACTOR_DOOR_ANA",
            "ACTOR_EN_A_OBJ",
            "ACTOR_EN_SW",
            "ACTOR_OBJ_MAKEKINSUTA",
            "ACTOR_EN_WONDER_ITEM",
            "ACTOR_OBJ_HANA",
            "ACTOR_EN_ISHI",
            "ACTOR_OBJ_MURE2",
            "ACTOR_EN_KANBAN",
            "ACTOR_EN_KUSA",
            "ACTOR_EN_SA",
            "ACTOR_OBJ_BEAN",
            "ACTOR_EN_WONDER_TALK2",
        ]
        let actorTable = actorNames.enumerated().map { index, name in
            String(format: "/* 0x%04X */ DEFINE_ACTOR(%@, %@, ACTOROVL_ALLOC_NORMAL, \"%@\")", index, name, name, name)
        }.joined(separator: "\n")
        try write(actorTable, to: root.appendingPathComponent("include/tables/actor_table.h"))

        try write(
            """
            /* 0x0000 */ DEFINE_OBJECT(object_spot04_objects, OBJECT_SPOT04_OBJECTS)
            """,
            to: root.appendingPathComponent("include/tables/object_table.h")
        )

        try write(
            """
            /* 0x0000 */ DEFINE_ENTRANCE(ENTR_KOKIRI_FOREST_0, spot04_scene, 0)
            """,
            to: root.appendingPathComponent("include/tables/entrance_table.h")
        )

        try write(
            """
            #define Gfx int
            #define gsSPEndDisplayList() 0
            """,
            to: root.appendingPathComponent("include/ultra64/gbi.h")
        )

        let sceneDirectory = root
            .appendingPathComponent("assets/scenes/overworld/spot04")
        try FileManager.default.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)

        try write(
            """
            #include "spot04_scene.h"

            SceneCmd spot04_sceneCommands[] = {
                SCENE_CMD_ROOM_LIST(1, spot04_sceneRoomList0x000184),
                SCENE_CMD_PATH_LIST(spot04_scenePathList_00030C),
                SCENE_CMD_SKYBOX_SETTINGS(29, 0, false),
                SCENE_CMD_EXIT_LIST(spot04_sceneExitList_0001B4),
                SCENE_CMD_ENV_LIGHT_SETTINGS(1, spot04_sceneLightSettings0x0001CC),
                SCENE_CMD_END(),
            };

            u16 spot04_sceneExitList_0001B4[] = {
                ENTR_KOKIRI_FOREST_0,
            };

            EnvLightSettings spot04_sceneLightSettings0x0001CC[] = {
                { 0x82, 0x5A, 0x5A, 0x49, 0x49, 0x49, 0xFF, 0x7D, 0x7D, 0xB7, 0xB7, 0xB7, 0x50, 0x50, 0x9B, 0x78, 0x50, 0x50,
                0xFFDE, 0x16A8 },
            };

            Vec3s spot04_scenePathwayList_0002E0[] = {
                {  -1474,    -80,   -295 },
                {  -1416,    -74,   -138 },
            };

            Path spot04_scenePathList_00030C[] = {
                { ARRAY_COUNT(spot04_scenePathwayList_0002E0), spot04_scenePathwayList_0002E0 },
            };
            """,
            to: sceneDirectory.appendingPathComponent("spot04_scene.c")
        )

        try write(
            """
            #include "spot04_room_0.h"

            SceneCmd spot04_room_0Commands[] = {
                SCENE_CMD_OBJECT_LIST(1, spot04_room_0ObjectList_00007C),
                SCENE_CMD_ACTOR_LIST(1, spot04_room_0ActorEntry_000094),
                SCENE_CMD_END(),
            };

            s16 spot04_room_0ObjectList_00007C[] = {
                OBJECT_SPOT04_OBJECTS,
            };

            ActorEntry spot04_room_0ActorEntry_000094[] = {
                { ACTOR_EN_KO, { 45, 0, -272 }, { 0, 0, 0 }, 0x0000 },
            };
            """,
            to: sceneDirectory.appendingPathComponent("spot04_room_0.c")
        )

        try write(
            """
            Gfx gBrokenDL[] = {
            #include "assets/objects/gameplay_keep/gArrowShaftTex.rgba16.inc.c"
            };
            """,
            to: root.appendingPathComponent("assets/objects/gameplay_keep/arrow_skel.c")
        )

        return root
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

    private func metadataDirectory(in output: URL) throws -> URL {
        let scenesRoot = output
            .appendingPathComponent("Manifests")
            .appendingPathComponent("scenes")
        guard let enumerator = FileManager.default.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "OOTContentExtractorTests", code: 1)
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true, fileURL.lastPathComponent == "actors.json" {
                return fileURL.deletingLastPathComponent()
            }
        }

        throw NSError(domain: "OOTContentExtractorTests", code: 2)
    }
}
