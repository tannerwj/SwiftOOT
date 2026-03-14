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
                VTX(-1, 2, 3, 0, 4, 5, 6, 7, 8, 9),
                VTX(10, 11, 12, 0, 13, 14, 15, 16, 17, 18),
                VTX(19, 20, 21, 0, 22, 23, 24, 25, 26, 27),
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
                VTX(1, 1, 1, 0, 2, 2, 3, 4, 5, 6),
                VTX(7, 8, 9, 0, 10, 11, 12, 13, 14, 15),
                VTX(16, 17, 18, 0, 19, 20, 21, 22, 23, 24),
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
                        address: DisplayListParser.stableID(for: "spot04_room_0Vtx_000000"),
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
                VTX(0, 0, 0, 0, 0, 0, 255, 255, 255, 255),
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
                VTX(1, 1, 1, 0, 0, 0, 255, 255, 255, 255),
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

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
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
