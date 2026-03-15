import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class SceneExtractorTests: XCTestCase {
    func testExtractWritesPerRoomGeometryBundles() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_scene" Segment="2">
                    <Scene Name="spot04_scene" Offset="0x0"/>
                </File>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
                <File Name="spot04_room_1" Segment="3">
                    <Room Name="spot04_room_1" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeRoomSource(
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertices: """
            Vtx spot04_room_0Vtx_000000[] = {
                VTX(-1, 2, 3, 0, 4, 6, 7, 8, 9),
                VTX(10, 11, 12, 0, 13, 15, 16, 17, 18),
                VTX(19, 20, 21, 0, 22, 24, 25, 26, 27),
            };
            """,
            displayList: """
            gsSPVertex(spot04_room_0Vtx_000000, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )
        try harness.writeRoomSource(
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_1",
            vertices: """
            Vtx spot04_room_1Vtx_000000[] = {
                VTX(1, 1, 1, 0, 2, 3, 4, 5, 6),
                VTX(7, 8, 9, 0, 10, 12, 13, 14, 15),
                VTX(16, 17, 18, 0, 19, 21, 22, 23, 24),
            };
            """,
            displayList: """
            gsSPVertex(spot04_room_1Vtx_000000, 3, 0),
            gsSP1Triangle(2, 1, 0, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let room0Directory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_0", isDirectory: true)
        let room1Directory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_1", isDirectory: true)

        let room0Vertices = try VertexParser.decode(
            Data(contentsOf: room0Directory.appendingPathComponent("vtx.bin"))
        )
        XCTAssertEqual(room0Vertices.count, 3)
        XCTAssertEqual(room0Vertices[0].position, Vector3s(x: -1, y: 2, z: 3))

        let room0Commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: room0Directory.appendingPathComponent("dl.json"))
        )
        XCTAssertEqual(
            room0Commands,
            [
                .spVertex(
                    VertexCommand(
                        address: 0x03000000,
                        count: 3,
                        destinationIndex: 0
                    )
                ),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ]
        )

        let room1Commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: room1Directory.appendingPathComponent("dl.json"))
        )
        XCTAssertEqual(room1Commands.count, 3)

        try SceneExtractor().verify(using: harness.verificationContext)
    }

    func testExtractHonorsSceneFilter() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot05.xml",
            contents: """
            <Root>
                <File Name="spot05_room_0" Segment="3">
                    <Room Name="spot05_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeRoomSource(
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertices: """
            Vtx spot04_room_0Vtx_000000[] = {
                VTX(0, 0, 0, 0, 0, 255, 255, 255, 255),
            };
            """,
            displayList: """
            gsSPVertex(spot04_room_0Vtx_000000, 1, 0),
            gsSPEndDisplayList(),
            """
        )
        try harness.writeRoomSource(
            sceneDirectory: "assets/scenes/overworld/spot05",
            roomName: "spot05_room_0",
            vertices: """
            Vtx spot05_room_0Vtx_000000[] = {
                VTX(1, 1, 1, 0, 0, 255, 255, 255, 255),
            };
            """,
            displayList: """
            gsSPVertex(spot05_room_0Vtx_000000, 1, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Scenes/spot04/rooms/room_0/vtx.bin")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Scenes/spot05/rooms/room_0/vtx.bin")
                    .path
            )
        )
    }

    func testExtractPrefersBuildRoomSourceOverBrokenSourceWrapper() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeBrokenRoomWrapper(
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0"
        )
        try harness.writeRoomSource(
            sceneDirectory: "build/assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertices: """
            Vtx spot04_room_0Vtx_000000[] = {
                VTX(7, 8, 9, 10, 11, 12, 13, 14, 15),
            };
            """,
            displayList: """
            gsSPVertex(spot04_room_0Vtx_000000, 1, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let vertices = try VertexParser.decode(
            Data(
                contentsOf: harness.outputRoot
                    .appendingPathComponent("Scenes/spot04/rooms/room_0/vtx.bin")
            )
        )
        XCTAssertEqual(vertices, [
            N64Vertex(
                position: Vector3s(x: 7, y: 8, z: 9),
                flag: 0,
                textureCoordinate: Vector2s(x: 10, y: 11),
                colorOrNormal: RGBA8(red: 12, green: 13, blue: 14, alpha: 15)
            ),
        ])
    }

    func testExtractBuildRoomWrapperResolvesBuildRelativeIncludes() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeBrokenRoomWrapper(
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0"
        )
        try harness.writeBuildBackedRoomSource(
            sceneDirectory: "build/assets/scenes/overworld/spot04",
            includeDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertexArrayName: "spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_",
            vertices: """
            { { { -1, 2, 3 }, 0, { 4, 5 }, { 6, 7, 8, 9 } } },
            { { { 10, 11, 12 }, 0, { 13, 14 }, { 15, 16, 17, 18 } } },
            { { { 19, 20, 21 }, 0, { 22, 23 }, { 24, 25, 26, 27 } } },
            """,
            displayList: """
            gsSPVertex(spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let roomDirectory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_0", isDirectory: true)
        let vertices = try VertexParser.decode(
            Data(contentsOf: roomDirectory.appendingPathComponent("vtx.bin"))
        )
        XCTAssertEqual(vertices.count, 3)
        XCTAssertEqual(vertices[0].position, Vector3s(x: -1, y: 2, z: 3))

        let commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: roomDirectory.appendingPathComponent("dl.json"))
        )
        XCTAssertEqual(commands.count, 3)
    }

    func testExtractExtractedRoomSourceResolvesAssetRelativeIncludes() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeExtractedRoomSource(
            extractedRoot: "extracted/ntsc-1.2",
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertexArrayName: "spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_",
            vertices: """
            VTX(-1, 2, 3, 0, 4, 5, 6, 7, 8),
            VTX(10, 11, 12, 0, 13, 14, 15, 16, 17),
            VTX(19, 20, 21, 0, 22, 23, 24, 25, 26),
            """,
            displayList: """
            gsSPVertex(spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let roomDirectory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_0", isDirectory: true)

        let vertices = try VertexParser.decode(
            Data(contentsOf: roomDirectory.appendingPathComponent("vtx.bin"))
        )
        XCTAssertEqual(vertices.count, 3)
        XCTAssertEqual(vertices[0].position, Vector3s(x: -1, y: 2, z: 3))

        let commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: roomDirectory.appendingPathComponent("dl.json"))
        )
        XCTAssertEqual(commands.count, 3)
    }

    func testExtractRewritesIndexedVertexReferencesIntoRoomSegmentOffsets() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )

        try harness.writeExtractedRoomSource(
            extractedRoot: "extracted/ntsc-1.2",
            sceneDirectory: "assets/scenes/overworld/spot04",
            roomName: "spot04_room_0",
            vertexArrayName: "spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_",
            vertices: """
            VTX(-1, 2, 3, 0, 4, 5, 6, 7, 8),
            VTX(10, 11, 12, 0, 13, 14, 15, 16, 17),
            VTX(19, 20, 21, 0, 22, 23, 24, 25, 26),
            """,
            displayList: """
            gsSPVertex(&spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_[1], 2, 0),
            gsSP1Triangle(0, 1, 1, 0),
            gsSPEndDisplayList(),
            """
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let roomDirectory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_0", isDirectory: true)

        let commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: roomDirectory.appendingPathComponent("dl.json"))
        )

        XCTAssertEqual(
            commands.first,
            .spVertex(
                VertexCommand(
                    address: 0x03000010,
                    count: 2,
                    destinationIndex: 0
                )
            )
        )
    }

    func testExtractWritesSpot04SceneMetadataFromFixtureSource() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.seedActorTableManifest()
        try harness.seedObjectTableManifest()
        try harness.writeSceneXML(at: "assets/xml/scenes/overworld/spot04.xml", contents: sceneXMLFixture)
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_scene.c",
            contents: sceneMetadataSourceFixture
        )
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_room_0.c",
            contents: roomMetadataSourceFixture
        )
        try harness.writeSourceFile(
            at: "include/tables/entrance_table.h",
            contents: entranceTableFixture
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let sceneDirectory = try harness.metadataDirectory()
        let actors = try JSONDecoder().decode(
            SceneActorsFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("actors.json"))
        )
        let spawns = try JSONDecoder().decode(
            SceneSpawnsFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("spawns.json"))
        )
        let environment = try JSONDecoder().decode(
            SceneEnvironmentFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("environment.json"))
        )
        let paths = try JSONDecoder().decode(
            ScenePathsFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("paths.json"))
        )
        let exits = try JSONDecoder().decode(
            SceneExitsFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("exits.json"))
        )
        let sceneHeader = try JSONDecoder().decode(
            SceneHeaderDefinition.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("scene-header.json"))
        )

        XCTAssertEqual(actors.sceneName, "spot04")
        XCTAssertEqual(actors.rooms.map(\.roomName), ["spot04_room_0"])
        XCTAssertEqual(actors.rooms[0].actors.count, 78)

        let kokiriSpawns = actors.rooms[0].actors.filter { $0.actorName == "ACTOR_EN_KO" }
        XCTAssertEqual(
            Array(kokiriSpawns.prefix(5).map(\.position)),
            [
                Vector3s(x: -292, y: 0, z: -430),
                Vector3s(x: 45, y: 0, z: -272),
                Vector3s(x: -608, y: 120, z: 1022),
                Vector3s(x: -1472, y: -80, z: -294),
                Vector3s(x: 669, y: 0, z: 521),
            ]
        )
        XCTAssertEqual(spawns.sceneName, "spot04")
        XCTAssertEqual(spawns.spawns.count, 2)

        XCTAssertEqual(environment.sceneName, "spot04")
        XCTAssertEqual(environment.time, SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 255))
        XCTAssertEqual(
            environment.skybox,
            SceneSkyboxSettings(
                skyboxID: 29,
                skyboxConfig: 0,
                environmentLightingMode: "false",
                skyboxDisabled: false,
                sunMoonDisabled: false
            )
        )
        XCTAssertEqual(environment.lightSettings.count, 12)
        XCTAssertEqual(environment.lightSettings[0].ambientColor, RGB8(red: 0x82, green: 0x5A, blue: 0x5A))
        XCTAssertEqual(environment.lightSettings[0].fogNear, 990)
        XCTAssertEqual(environment.lightSettings[0].blendRate, 252)
        XCTAssertEqual(environment.lightSettings[0].zFar, 5800)

        XCTAssertEqual(paths.sceneName, "spot04")
        XCTAssertEqual(paths.paths.count, 3)
        XCTAssertEqual(
            paths.paths[0],
            ScenePathDefinition(
                index: 0,
                pointsName: "spot04_scenePathwayList_0002E0",
                points: [
                    Vector3s(x: -1474, y: -80, z: -295),
                    Vector3s(x: -1416, y: -74, z: -138),
                ]
            )
        )

        XCTAssertEqual(exits.sceneName, "spot04")
        XCTAssertEqual(exits.exits.count, 12)
        XCTAssertEqual(
            Array(exits.exits.prefix(4)),
            [
                SceneExitDefinition(index: 0, entranceIndex: 0x0EE, entranceName: "ENTR_KOKIRI_FOREST_0"),
                SceneExitDefinition(index: 1, entranceIndex: 0x000, entranceName: "ENTR_DEKU_TREE_0"),
                SceneExitDefinition(index: 2, entranceIndex: 0x5E0, entranceName: "ENTR_LOST_WOODS_9"),
                SceneExitDefinition(index: 3, entranceIndex: 0x272, entranceName: "ENTR_LINKS_HOUSE_1"),
            ]
        )

        XCTAssertEqual(sceneHeader.sceneName, "spot04")
        XCTAssertEqual(sceneHeader.sceneObjectIDs, [1])
        XCTAssertEqual(sceneHeader.soundSettings, SceneSoundSettings(specID: 1, natureAmbienceID: 4, sequenceID: 60))
        XCTAssertEqual(
            sceneHeader.specialFiles,
            SceneSpecialFiles(
                naviHintName: "NAVI_QUEST_HINTS_OVERWORLD",
                keepObjectName: "OBJECT_GAMEPLAY_FIELD_KEEP"
            )
        )
        XCTAssertEqual(
            Array(sceneHeader.spawns.prefix(2)),
            [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 95, y: 0, z: 778),
                    rotation: Vector3s(x: 0, y: Int16(bitPattern: 0x8001), z: 0)
                ),
                SceneSpawnPoint(
                    index: 1,
                    roomID: 0,
                    position: Vector3s(x: 95, y: 0, z: 778),
                    rotation: Vector3s(x: 0, y: Int16(bitPattern: 0x8001), z: 0)
                ),
            ]
        )
        XCTAssertEqual(
            Array(sceneHeader.entrances.prefix(2)),
            [
                SceneEntranceDefinition(index: 0, spawnIndex: 0),
                SceneEntranceDefinition(index: 1, spawnIndex: 1),
            ]
        )
        XCTAssertEqual(
            sceneHeader.rooms,
            [
                SceneRoomDefinition(
                    id: 0,
                    shape: .cullable,
                    objectIDs: [2, 3],
                    echo: 1,
                    behavior: SceneRoomBehavior(disableWarpSongs: false, showInvisibleActors: false)
                )
            ]
        )
        XCTAssertEqual(
            sceneHeader.transitionTriggers,
            [
                SceneTransitionTrigger(
                    id: 0,
                    kind: .door,
                    roomID: 0,
                    destinationRoomID: 1,
                    effect: .fade,
                    volume: SceneTriggerVolume(
                        minimum: Vector3s(x: 120, y: 0, z: 320),
                        maximum: Vector3s(x: 120, y: 0, z: 320)
                    )
                ),
                SceneTransitionTrigger(
                    id: 1,
                    kind: .door,
                    roomID: 1,
                    destinationRoomID: 0,
                    effect: .fade,
                    volume: SceneTriggerVolume(
                        minimum: Vector3s(x: -240, y: 10, z: 512),
                        maximum: Vector3s(x: -240, y: 10, z: 512)
                    )
                ),
            ]
        )
    }

    func testExtractMetadataPrefersHigherSignalSceneCommandArray() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.seedActorTableManifest()
        try harness.seedObjectTableManifest()
        try harness.writeSceneXML(at: "assets/xml/scenes/overworld/spot04.xml", contents: sceneXMLFixture)
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_scene.c",
            contents: """
            SceneCmd spot04_sceneCommands[] = {
                SCENE_CMD_ALTERNATE_HEADER_LIST(spot04_sceneAlternateHeaders0x000070),
                SCENE_CMD_END(),
            };

            \(sceneMetadataSourceFixture.replacingOccurrences(
                of: "SceneCmd spot04_sceneCommands[] = {",
                with: "SceneCmd spot04_sceneMainCommands[] = {"
            ))
            """
        )
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_room_0.c",
            contents: roomMetadataSourceFixture
        )
        try harness.writeSourceFile(
            at: "include/tables/entrance_table.h",
            contents: entranceTableFixture
        )

        try SceneExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let sceneDirectory = try harness.metadataDirectory()
        let environment = try JSONDecoder().decode(
            SceneEnvironmentFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("environment.json"))
        )
        let paths = try JSONDecoder().decode(
            ScenePathsFile.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("paths.json"))
        )

        XCTAssertEqual(environment.lightSettings.count, 12)
        XCTAssertEqual(paths.paths.count, 3)
    }

    func testVerifyRoundTripsSceneMetadataJSON() throws {
        let harness = try SceneHarness()
        defer { harness.cleanup() }

        try harness.seedActorTableManifest()
        try harness.seedObjectTableManifest()
        try harness.writeSceneXML(at: "assets/xml/scenes/overworld/spot04.xml", contents: sceneXMLFixture)
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_scene.c",
            contents: sceneMetadataSourceFixture
        )
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_room_0.c",
            contents: roomMetadataSourceFixture
        )
        try harness.writeSourceFile(
            at: "include/tables/entrance_table.h",
            contents: entranceTableFixture
        )

        let extractor = SceneExtractor()
        try extractor.extract(using: harness.extractionContext(sceneName: "spot04"))
        try extractor.verify(using: harness.verificationContext)
    }
}

private struct SceneHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("swiftoot-sceneextract-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        self.root = root
        self.sourceRoot = sourceRoot
        self.outputRoot = outputRoot

        try writeCommonHeaders()
    }

    var verificationContext: OOTVerificationContext {
        OOTVerificationContext(content: outputRoot)
    }

    func extractionContext(sceneName: String?) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneName: sceneName)
    }

    func writeSceneXML(at relativePath: String, contents: String) throws {
        let url = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeSourceFile(at relativePath: String, contents: String) throws {
        let url = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeRoomSource(sceneDirectory: String, roomName: String, vertices: String, displayList: String) throws {
        let directory = sourceRoot.appendingPathComponent(sceneDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try """
        #include "gfx.h"
        #include "\(roomName).vtx.inc.c"

        Gfx \(roomName)DL[] = {
        #include "\(roomName).dl.inc.c"
        };
        """.write(
            to: directory.appendingPathComponent("\(roomName).c"),
            atomically: true,
            encoding: .utf8
        )

        try vertices.write(
            to: directory.appendingPathComponent("\(roomName).vtx.inc.c"),
            atomically: true,
            encoding: .utf8
        )
        try displayList.write(
            to: directory.appendingPathComponent("\(roomName).dl.inc.c"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeBrokenRoomWrapper(sceneDirectory: String, roomName: String) throws {
        let directory = sourceRoot.appendingPathComponent(sceneDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try """
        #include "gfx.h"
        #include "\(roomName).vtx.inc.c"

        Gfx \(roomName)DL[] = {
        #include "\(roomName).dl.inc.c"
        };
        """.write(
            to: directory.appendingPathComponent("\(roomName).c"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeBuildBackedRoomSource(
        sceneDirectory: String,
        includeDirectory: String,
        roomName: String,
        vertexArrayName: String,
        vertices: String,
        displayList: String
    ) throws {
        let directory = sourceRoot.appendingPathComponent(sceneDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try """
        #include "gfx.h"

        Vtx \(vertexArrayName)[] = {
        #include "\(includeDirectory)/\(roomName).vtx.inc.c"
        };

        Gfx \(roomName)DL[] = {
        #include "\(includeDirectory)/\(roomName).dl.inc.c"
        };
        """.write(
            to: directory.appendingPathComponent("\(roomName).c"),
            atomically: true,
            encoding: .utf8
        )

        try vertices.write(
            to: directory.appendingPathComponent("\(roomName).vtx.inc.c"),
            atomically: true,
            encoding: .utf8
        )
        try displayList.write(
            to: directory.appendingPathComponent("\(roomName).dl.inc.c"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeExtractedRoomSource(
        extractedRoot: String,
        sceneDirectory: String,
        roomName: String,
        vertexArrayName: String,
        vertices: String,
        displayList: String
    ) throws {
        let directory = sourceRoot
            .appendingPathComponent(extractedRoot, isDirectory: true)
            .appendingPathComponent(sceneDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try "".write(
            to: directory.appendingPathComponent("\(roomName).h"),
            atomically: true,
            encoding: .utf8
        )
        try "".write(
            to: directory.appendingPathComponent("spot04_scene.h"),
            atomically: true,
            encoding: .utf8
        )

        try """
        #include "\(roomName).h"
        #include "assets/scenes/overworld/spot04/spot04_scene.h"
        #include "gfx.h"

        u8 \(roomName)_unaccounted_0006AC[] = {
        #include "assets/scenes/overworld/spot04/\(roomName)_unaccounted_0006AC.bin.inc.c"
        };

        Vtx \(vertexArrayName)[] = {
        #include "assets/scenes/overworld/spot04/\(roomName).vtx.inc.c"
        };

        Gfx \(roomName)DL[] = {
        #include "assets/scenes/overworld/spot04/\(roomName).dl.inc.c"
        };
        """.write(
            to: directory.appendingPathComponent("\(roomName).c"),
            atomically: true,
            encoding: .utf8
        )

        try vertices.write(
            to: directory.appendingPathComponent("\(roomName).vtx.inc.c"),
            atomically: true,
            encoding: .utf8
        )
        try displayList.write(
            to: directory.appendingPathComponent("\(roomName).dl.inc.c"),
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func seedActorTableManifest() throws {
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

        let manifestDirectory = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

        let entries = actorNames.enumerated().map { index, name in
            ActorTableEntry(
                id: index,
                enumName: name,
                profile: ActorProfile(id: index, category: 0, flags: 0, objectID: 0),
                overlayName: nil
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(
            to: manifestDirectory.appendingPathComponent("actor-table.json"),
            options: .atomic
        )
    }

    func seedObjectTableManifest() throws {
        let manifestDirectory = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

        let entries = [
            ObjectTableEntry(id: 0, enumName: "OBJECT_INVALID", assetPath: ""),
            ObjectTableEntry(id: 1, enumName: "OBJECT_GAMEPLAY_FIELD_KEEP", assetPath: "objects/object_gameplay_field_keep"),
            ObjectTableEntry(id: 2, enumName: "OBJECT_KM1", assetPath: "objects/object_km1"),
            ObjectTableEntry(id: 3, enumName: "OBJECT_LINK_CHILD", assetPath: "objects/object_link_child"),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(
            to: manifestDirectory.appendingPathComponent("object-table.json"),
            options: .atomic
        )
    }

    func metadataDirectory() throws -> URL {
        let scenesRoot = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "SceneExtractorTests", code: 1)
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true, fileURL.lastPathComponent == "actors.json" {
                return fileURL.deletingLastPathComponent()
            }
        }

        throw NSError(domain: "SceneExtractorTests", code: 2)
    }

    private func writeCommonHeaders() throws {
        let includeDirectory = sourceRoot.appendingPathComponent("include/ultra64", isDirectory: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        try "".write(
            to: includeDirectory.appendingPathComponent("gbi.h"),
            atomically: true,
            encoding: .utf8
        )
        try """
        #include "ultra64/gbi.h"
        """.write(
            to: sourceRoot.appendingPathComponent("gfx.h"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private let sceneXMLFixture = """
<Root>
    <File Name="spot04_scene" Segment="2">
        <Scene Name="spot04_scene" Offset="0x0"/>
    </File>
    <File Name="spot04_room_0" Segment="3">
        <Room Name="spot04_room_0" Offset="0x0"/>
    </File>
</Root>
"""

private let sceneMetadataSourceFixture = """
#include "spot04_scene.h"

SceneCmd spot04_sceneCommands[] = {
    SCENE_CMD_ALTERNATE_HEADER_LIST(spot04_sceneAlternateHeaders0x000070),
    SCENE_CMD_SOUND_SETTINGS(1, 4, 60),
    SCENE_CMD_ROOM_LIST(1, spot04_sceneRoomList0x000184),
    SCENE_CMD_TRANSITION_ACTOR_LIST(2, spot04_sceneTransitionActorList_000164),
    SCENE_CMD_MISC_SETTINGS(0x00, 0x00000004),
    SCENE_CMD_COL_HEADER(&spot04_sceneCollisionHeader_008918),
    SCENE_CMD_ENTRANCE_LIST(spot04_sceneEntranceList0x00019C),
    SCENE_CMD_SPECIAL_FILES(NAVI_QUEST_HINTS_OVERWORLD, OBJECT_GAMEPLAY_FIELD_KEEP),
    SCENE_CMD_PATH_LIST(spot04_scenePathList_00030C),
    SCENE_CMD_SPAWN_LIST(2, spot04_sceneStartPositionList0x0000A4),
    SCENE_CMD_SKYBOX_SETTINGS(29, 0, false),
    SCENE_CMD_EXIT_LIST(spot04_sceneExitList_0001B4),
    SCENE_CMD_ENV_LIGHT_SETTINGS(12, spot04_sceneLightSettings0x0001CC),
    SCENE_CMD_END(),
};

ActorEntry spot04_sceneStartPositionList0x0000A4[] = {
    { ACTOR_PLAYER, { 95, 0, 778 }, { 0, 0X8001, 0 }, 0x0FFF },
    { ACTOR_PLAYER, { 95, 0, 778 }, { 0, 0X8001, 0 }, 0x0FFF },
};

TransitionActorEntry spot04_sceneTransitionActorList_000164[] = {
    { 0, 255, 1, 255, ACTOR_DOOR_ANA, 120, 0, 320, 0X4000, 0x0000 },
    { 1, 255, 0, 255, ACTOR_DOOR_ANA, -240, 10, 512, 0XC000, 0x0000 },
};

Spawn spot04_sceneEntranceList0x00019C[] = {
    { 0, 0 },
    { 1, 0 },
};

u16 spot04_sceneExitList_0001B4[] = {
    ENTR_KOKIRI_FOREST_0,
    ENTR_DEKU_TREE_0,
    ENTR_LOST_WOODS_9,
    ENTR_LINKS_HOUSE_1,
    ENTR_KOKIRI_SHOP_0,
    ENTR_KNOW_IT_ALL_BROS_HOUSE_0,
    ENTR_LOST_WOODS_0,
    ENTR_KOKIRI_FOREST_0,
    ENTR_TWINS_HOUSE_0,
    ENTR_MIDOS_HOUSE_0,
    ENTR_SARIAS_HOUSE_0,
    ENTR_DEKU_TREE_0,
};

EnvLightSettings spot04_sceneLightSettings0x0001CC[] = {
    { 0x82, 0x5A, 0x5A, 0x49, 0x49, 0x49, 0xFF, 0x7D, 0x7D, 0xB7, 0xB7, 0xB7, 0x50, 0x50, 0x9B, 0x78, 0x50, 0x50,
    0xFFDE, 0x16A8 },
    { 0x50, 0x50, 0x50, 0x49, 0x49, 0x49, 0xFF, 0xFF, 0xFF, 0xB7, 0xB7, 0xB7, 0x46, 0x46, 0x5A, 0xC8, 0xC8, 0x96,
    0xFFE2, 0x16A8 },
    { 0x6E, 0x6E, 0x32, 0x49, 0x49, 0x49, 0xFF, 0x91, 0x3C, 0xB7, 0xB7, 0xB7, 0x64, 0x64, 0x64, 0x96, 0x82, 0x3C,
    0xFFDE, 0x16A8 },
    { 0x3C, 0x50, 0x6E, 0x49, 0x49, 0x49, 0x32, 0x32, 0x5A, 0xB7, 0xB7, 0xB7, 0x6E, 0x8C, 0xC3, 0x28, 0x32, 0x50,
    0xFFCA, 0x16A8 },
    { 0x3C, 0x28, 0x46, 0x49, 0x49, 0x49, 0x50, 0x1E, 0x3C, 0xB7, 0xB7, 0xB7, 0x50, 0x32, 0x96, 0x46, 0x2B, 0x2D,
    0xFFD2, 0x16A8 },
    { 0x4B, 0x5A, 0x64, 0x49, 0x49, 0x49, 0x37, 0xFF, 0xF0, 0xB7, 0xB7, 0xB7, 0x0A, 0x96, 0xBE, 0x14, 0x5A, 0x6E,
    0xFFD2, 0x16A8 },
    { 0x3C, 0x28, 0x50, 0x49, 0x49, 0x49, 0x3C, 0x4B, 0x96, 0xB7, 0xB7, 0xB7, 0x3C, 0x37, 0x96, 0x32, 0x1E, 0x1E,
    0xFFD2, 0x16A8 },
    { 0x00, 0x28, 0x50, 0x49, 0x49, 0x49, 0x14, 0x32, 0x4B, 0xB7, 0xB7, 0xB7, 0x32, 0x64, 0x96, 0x00, 0x0A, 0x14,
    0xFFD2, 0x16A8 },
    { 0x46, 0x2D, 0x39, 0x00, 0x00, 0x00, 0xB4, 0x9A, 0x8A, 0x00, 0x00, 0x00, 0x14, 0x14, 0x3C, 0x0F, 0x05, 0x05,
    0x07BC, 0x16A8 },
    { 0x50, 0x50, 0x50, 0x00, 0x00, 0x00, 0x9B, 0x9B, 0x9B, 0x00, 0x00, 0x00, 0x46, 0x46, 0x5A, 0x32, 0x32, 0x28,
    0x07BC, 0x16A8 },
    { 0x78, 0x5A, 0x00, 0x00, 0x00, 0x00, 0xFA, 0x87, 0x32, 0x00, 0x00, 0x00, 0x1E, 0x1E, 0x3C, 0x1C, 0x14, 0x00,
    0x07BC, 0x16A8 },
    { 0x1E, 0x28, 0x46, 0x00, 0x00, 0x00, 0x32, 0x32, 0x64, 0x00, 0x00, 0x00, 0x64, 0x64, 0xA5, 0x14, 0x28, 0x3C,
    0x07BC, 0x16A8 },
};

Vec3s spot04_scenePathwayList_0002D4[] = {
    {   1522,      0,    105 },
    {   1412,      0,    211 },
};

Vec3s spot04_scenePathwayList_0002E0[] = {
    {  -1474,    -80,   -295 },
    {  -1416,    -74,   -138 },
};

Vec3s spot04_scenePathwayList_0002EC[] = {
    {   -247,    120,   1869 },
    {   -247,    120,   1538 },
    {   -575,    120,   1538 },
    {   -575,    120,   1869 },
    {   -247,    120,   1869 },
};

Path spot04_scenePathList_00030C[] = {
    { ARRAY_COUNT(spot04_scenePathwayList_0002E0), spot04_scenePathwayList_0002E0 },
    { ARRAY_COUNT(spot04_scenePathwayList_0002D4), spot04_scenePathwayList_0002D4 },
    { ARRAY_COUNT(spot04_scenePathwayList_0002EC), spot04_scenePathwayList_0002EC },
};
"""

private let roomMetadataSourceFixture = """
#include "gfx.h"

SceneCmd spot04_room_0Commands[] = {
    SCENE_CMD_ALTERNATE_HEADER_LIST(spot04_room_0AlternateHeaders0x000048),
    SCENE_CMD_ECHO_SETTINGS(1),
    SCENE_CMD_ROOM_BEHAVIOR(0x00, 0x00, false, false),
    SCENE_CMD_SKYBOX_DISABLES(false, false),
    SCENE_CMD_TIME_SETTINGS(255, 255, 0),
    SCENE_CMD_ROOM_SHAPE(&spot04_room_0RoomShapeCullable_000580),
    SCENE_CMD_OBJECT_LIST(2, spot04_room_0ObjectList_00007C),
    SCENE_CMD_ACTOR_LIST(78, spot04_room_0ActorEntry_000094),
    SCENE_CMD_END(),
};

s16 spot04_room_0ObjectList_00007C[] = {
    OBJECT_KM1,
    OBJECT_LINK_CHILD,
};

ActorEntry spot04_room_0ActorEntry_000094[] = {
    { ACTOR_EN_RIVER_SOUND,  {    398,    -29,   -483 }, {      0,      0,      0 }, 0x0001 },
    { ACTOR_EN_ITEM00,       {   -537,      1,    194 }, {      0,      0,   0XB6 }, 0x2400 },
    { ACTOR_EN_ITEM00,       {   -459,      1,    181 }, {      0,      0,      0 }, 0x2700 },
    { ACTOR_EN_ITEM00,       {     35,      1,   -418 }, {      0,      0,      0 }, 0x2500 },
    { ACTOR_EN_ITEM00,       {    107,      1,   -418 }, {      0,      0,      0 }, 0x2600 },
    { ACTOR_EN_ITEM00,       {   -364,     53,   -783 }, {      0,      0,      0 }, 0x1201 },
    { ACTOR_EN_ITEM00,       {      2,    180,    -45 }, {      0,      0,      0 }, 0x1101 },
    { ACTOR_OBJECT_KANKYO,   {    355,      1,   -150 }, {      0,      0,      0 }, 0x0000 },
    { ACTOR_EN_KO,           {   -292,      0,   -430 }, {      0,      0,      0 }, 0xFF00 },
    { ACTOR_EN_KO,           {     45,      0,   -272 }, {      0,      0,      0 }, 0xFF01 },
    { ACTOR_EN_KO,           {   -608,    120,   1022 }, {      0, 0XA000,      0 }, 0xFF02 },
    { ACTOR_EN_KO,           {  -1472,    -80,   -294 }, {      0, 0X4000,      0 }, 0x0003 },
    { ACTOR_EN_KO,           {    669,      0,    521 }, {      0, 0X871C,      0 }, 0xFF04 },
    { ACTOR_EN_KO,           {    853,    100,   -311 }, {      0,      0,      0 }, 0xFF05 },
    { ACTOR_EN_KO,           {   -678,      1,   -179 }, {      0, 0X3777,      0 }, 0xFF06 },
    { ACTOR_EN_GS,           {   -622,    380,  -1223 }, {      0, 0X4000,      0 }, 0x381E },
    { ACTOR_EN_KO,           {    -10,    180,    -22 }, {      0, 0X305B,      0 }, 0xFF0C },
    { ACTOR_EN_MD,           {   1522,      0,    105 }, {      0, 0XBBBC,      0 }, 0x0100 },
    { ACTOR_DOOR_ANA,        {   -512,    380,  -1224 }, {      0, 0X4000,      0 }, 0x012C },
    { ACTOR_EN_ITEM00,       {    451,    200,    810 }, {      0,      0,      0 }, 0x1C03 },
    { ACTOR_EN_ITEM00,       {    509,    205,    725 }, {      0,      0,      0 }, 0x1E03 },
    { ACTOR_EN_ITEM00,       {    567,    212,    819 }, {      0,      0,      0 }, 0x1D03 },
    { ACTOR_EN_A_OBJ,        {  -1008,    120,    479 }, {      0, 0X5C72,      0 }, 0x3D0A },
    { ACTOR_EN_A_OBJ,        {   -924,    120,    928 }, {      0, 0X349F,      0 }, 0x430A },
    { ACTOR_EN_A_OBJ,        {   -779,    121,    424 }, {      0, 0XCAAB,      0 }, 0x100A },
    { ACTOR_EN_A_OBJ,        {   -512,      0,   -459 }, {      0, 0X1A50,      0 }, 0x3C0A },
    { ACTOR_EN_A_OBJ,        {   -170,    380,  -1335 }, {      0, 0X6B61,      0 }, 0x140A },
    { ACTOR_EN_A_OBJ,        {    436,      0,    601 }, {      0, 0XDA50,      0 }, 0x3F0A },
    { ACTOR_EN_A_OBJ,        {    728,      0,   -195 }, {      0, 0X1C72,      0 }, 0x1E0A },
    { ACTOR_EN_A_OBJ,        {   1089,      0,    473 }, {      0, 0XAAAB,      0 }, 0x3E0A },
    { ACTOR_EN_SW,           {  -1307,    153,    401 }, {      0, 0XCD83,      0 }, 0xAD02 },
    { ACTOR_OBJ_MAKEKINSUTA, {   1190,      0,   -480 }, {      0,      0,      0 }, 0x4D01 },
    { ACTOR_EN_WONDER_ITEM,  {   -488,    140,    600 }, {      0, 0XB27D,      0 }, 0x1A53 },
    { ACTOR_EN_WONDER_ITEM,  {   1074,      0,    178 }, {      0,      0,    0X2 }, 0x2A63 },
    { ACTOR_EN_WONDER_ITEM,  {   1069,      0,    406 }, {      0,      0,      0 }, 0x37E3 },
    { ACTOR_EN_WONDER_ITEM,  {   1074,      0,    -80 }, {      0,      0,    0X1 }, 0x37E3 },
    { ACTOR_EN_WONDER_ITEM,  {    188,      3,   -198 }, {      0,      0,    0X1 }, 0x0FE0 },
    { ACTOR_EN_WONDER_ITEM,  {    548,      3,   -158 }, {      0,      0,      0 }, 0x0FE0 },
    { ACTOR_EN_WONDER_ITEM,  {    364,      0,     28 }, {      0,      0,    0X2 }, 0x0260 },
    { ACTOR_EN_WONDER_ITEM,  {   -747,    165,    951 }, {      0,      0,    0X1 }, 0x1214 },
    { ACTOR_EN_WONDER_ITEM,  {   -698,    166,    830 }, {      0,      0,    0X1 }, 0x1215 },
    { ACTOR_EN_WONDER_ITEM,  {   -677,    166,    899 }, {      0,      0,    0X1 }, 0x1256 },
    { ACTOR_OBJ_HANA,        {   -915,    120,    872 }, {      0,      0,      0 }, 0x0001 },
    { ACTOR_OBJ_HANA,        {   -896,    120,    826 }, {      0,      0,      0 }, 0x0001 },
    { ACTOR_OBJ_HANA,        {   -584,    120,    963 }, {      0,      0,      0 }, 0x0001 },
    { ACTOR_OBJ_HANA,        {   -292,      0,   -415 }, {      0,      0,      0 }, 0x0001 },
    { ACTOR_EN_ISHI,         {  -1361,    120,    145 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_ISHI,         {   -672,      0,   -623 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_ISHI,         {    248,      0,    601 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_ISHI,         {    726,      0,    961 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_OBJ_MURE2,       {   -292,      0,   -430 }, {      0,      0,      0 }, 0x0202 },
    { ACTOR_EN_KANBAN,       {  -1432,    -66,   -426 }, {      0, 0X4000,      0 }, 0x0320 },
    { ACTOR_EN_KANBAN,       {   -845,    120,   1018 }, {      0, 0X8000,      0 }, 0x0337 },
    { ACTOR_EN_KANBAN,       {   -784,    120,   1675 }, {      0, 0X8000,      0 }, 0x0340 },
    { ACTOR_EN_KANBAN,       {   -538,    120,    718 }, {      0, 0XB333,      0 }, 0x0338 },
    { ACTOR_EN_KANBAN,       {   -494,    120,    598 }, {      0, 0XB3E9,      0 }, 0x0336 },
    { ACTOR_EN_KANBAN,       {     49,    -80,    967 }, {      0, 0X8000,      0 }, 0x031F },
    { ACTOR_EN_KANBAN,       {    607,      0,    -80 }, {      0, 0X305B,      0 }, 0x0341 },
    { ACTOR_EN_KANBAN,       {    871,      0,    311 }, {      0, 0XC71C,      0 }, 0x0312 },
    { ACTOR_OBJ_HANA,        {    668,      0,    500 }, {      0,  0X71C,      0 }, 0x0002 },
    { ACTOR_EN_KUSA,         {   -835,    120,    605 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -823,    120,    666 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -757,    120,    708 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -748,    120,    632 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -671,    120,    671 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -612,    120,    737 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -523,    120,    771 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {   -498,    120,    696 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {    385,      0,    643 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {    572,      0,    603 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {    594,      0,    542 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_KUSA,         {    678,      0,    596 }, {      0,      0,      0 }, 0x0200 },
    { ACTOR_EN_SA,           {     18,    -80,    873 }, {      0, 0XE38E,      0 }, 0x0000 },
    { ACTOR_OBJ_BEAN,        {   1190,      0,   -480 }, {      0,      0,      0 }, 0x1F09 },
    { ACTOR_EN_WONDER_TALK2, {    861,     34,   -340 }, {      0,      0,    0X3 }, 0x461F },
    { ACTOR_EN_WONDER_TALK2, {   -915,    130,    872 }, {      0, 0X2E39,      0 }, 0xFFFF },
    { ACTOR_EN_WONDER_TALK2, {   -896,    130,    826 }, {      0, 0X2E39,      0 }, 0xFFFF },
    { ACTOR_EN_WONDER_TALK2, {   -584,    130,    963 }, {      0, 0XB1C7,   0X28 }, 0xFFFF },
};

Vtx spot04_room_0Vtx_000000[] = {
    VTX(-1, 2, 3, 0, 4, 5, 6, 7, 8),
    VTX(10, 11, 12, 0, 13, 14, 15, 16, 17),
    VTX(19, 20, 21, 0, 22, 23, 24, 25, 26),
};

Gfx spot04_room_0DL[] = {
    gsSPVertex(spot04_room_0Vtx_000000, 3, 0),
    gsSP1Triangle(0, 1, 2, 0),
    gsSPEndDisplayList(),
};
"""

private let entranceTableFixture = """
/* 0x000 */ DEFINE_ENTRANCE(ENTR_DEKU_TREE_0, SCENE_DEKU_TREE, 0, false, true, TRANS_TYPE_FADE_BLACK, TRANS_TYPE_FADE_BLACK)
/* 0x09C */ DEFINE_ENTRANCE(ENTR_TWINS_HOUSE_0, SCENE_TWINS_HOUSE, 0, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x0C1 */ DEFINE_ENTRANCE(ENTR_KOKIRI_SHOP_0, SCENE_KOKIRI_SHOP, 0, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x0C9 */ DEFINE_ENTRANCE(ENTR_KNOW_IT_ALL_BROS_HOUSE_0, SCENE_KNOW_IT_ALL_BROS_HOUSE, 0, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x0EE */ DEFINE_ENTRANCE(ENTR_KOKIRI_FOREST_0, SCENE_KOKIRI_FOREST, 0, false, true, TRANS_TYPE_FADE_WHITE, TRANS_TYPE_FADE_WHITE)
/* 0x11E */ DEFINE_ENTRANCE(ENTR_LOST_WOODS_0, SCENE_LOST_WOODS, 0, false, true, TRANS_TYPE_FADE_BLACK, TRANS_TYPE_FADE_BLACK)
/* 0x272 */ DEFINE_ENTRANCE(ENTR_LINKS_HOUSE_1, SCENE_LINKS_HOUSE, 1, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x433 */ DEFINE_ENTRANCE(ENTR_MIDOS_HOUSE_0, SCENE_MIDOS_HOUSE, 0, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x437 */ DEFINE_ENTRANCE(ENTR_SARIAS_HOUSE_0, SCENE_SARIAS_HOUSE, 0, false, true, TRANS_TYPE_FADE_BLACK_FAST, TRANS_TYPE_FADE_BLACK_FAST)
/* 0x5E0 */ DEFINE_ENTRANCE(ENTR_LOST_WOODS_9, SCENE_LOST_WOODS, 9, false, false, TRANS_TYPE_FADE_BLACK, TRANS_TYPE_FADE_BLACK)
"""
