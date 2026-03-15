import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class CollisionExtractorTests: XCTestCase {
    func testExtractWritesCollisionBinaryForSceneHeader() throws {
        let harness = try CollisionHarness()
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
            </Root>
            """
        )
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_scene.c",
            contents: collisionSceneSourceFixture
        )

        try CollisionExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let collisionURL = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("collision.bin")
        let collisionData = try Data(contentsOf: collisionURL)
        let collision = try CollisionExtractor.decode(collisionData, path: collisionURL.path)

        XCTAssertEqual(collisionData.count, 100)
        XCTAssertEqual(collision.minimumBounds, Vector3s(x: -1000, y: -200, z: -3000))
        XCTAssertEqual(collision.maximumBounds, Vector3s(x: 4000, y: 500, z: 6000))
        XCTAssertEqual(
            collision.vertices,
            [
                Vector3s(x: -10, y: 0, z: -20),
                Vector3s(x: 20, y: 5, z: 30),
                Vector3s(x: 40, y: 10, z: 50),
            ]
        )
        XCTAssertEqual(
            collision.polygons,
            [
                CollisionPolygonBinary(
                    surfaceType: 0,
                    vertexA: 0,
                    vertexB: 1,
                    vertexC: 2,
                    normal: Vector3s(x: 0, y: Int16(bitPattern: 0x7FFF), z: 0),
                    distance: -10
                ),
                CollisionPolygonBinary(
                    surfaceType: 1,
                    vertexA: 2,
                    vertexB: 1,
                    vertexC: 0,
                    normal: Vector3s(x: 1, y: 2, z: 3),
                    distance: 4
                ),
            ]
        )
        XCTAssertEqual(
            collision.surfaceTypes,
            [
                CollisionSurfaceTypeBinary(low: 0x12345678, high: 0x90ABCDEF),
                CollisionSurfaceTypeBinary(low: 0x00000001, high: 0x00000002),
            ]
        )
        XCTAssertEqual(
            collision.waterBoxes,
            [
                CollisionWaterBoxBinary(
                    xMin: -100,
                    ySurface: 20,
                    zMin: -200,
                    xLength: 300,
                    zLength: 400,
                    properties: 0x01020304
                )
            ]
        )

        try CollisionExtractor().verify(using: harness.verificationContext)
    }

    func testExtractSkipsSceneWithoutCollisionHeader() throws {
        let harness = try CollisionHarness()
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
            </Root>
            """
        )
        try harness.writeSourceFile(
            at: "assets/scenes/overworld/spot04/spot04_scene.c",
            contents: """
            SceneCmd spot04_sceneCommands[] = {
                SCENE_CMD_ROOM_LIST(1, spot04_sceneRoomList0x000000),
                SCENE_CMD_END(),
            };
            """
        )

        try CollisionExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let collisionURL = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
            .appendingPathComponent("collision.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: collisionURL.path))
    }

    func testVerifyRejectsMalformedCollisionBinary() throws {
        let harness = try CollisionHarness()
        defer { harness.cleanup() }

        let sceneDirectory = harness.outputRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
        try FileManager.default.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)

        let valid = CollisionExtractor.encode(
            CollisionSceneBinary(
                minimumBounds: Vector3s(x: 0, y: 0, z: 0),
                maximumBounds: Vector3s(x: 10, y: 10, z: 10),
                vertices: [Vector3s(x: 1, y: 2, z: 3)],
                polygons: [
                    CollisionPolygonBinary(
                        surfaceType: 0,
                        vertexA: 0,
                        vertexB: 0,
                        vertexC: 0,
                        normal: Vector3s(x: 0, y: 1, z: 0),
                        distance: 0
                    )
                ],
                surfaceTypes: [CollisionSurfaceTypeBinary(low: 0, high: 0)],
                waterBoxes: []
            )
        )
        try valid.dropLast().write(to: sceneDirectory.appendingPathComponent("collision.bin"))

        XCTAssertThrowsError(try CollisionExtractor().verify(using: harness.verificationContext)) { error in
            XCTAssertTrue(error.localizedDescription.contains("invalid size"))
        }
    }
}

private struct CollisionHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("swiftoot-collisionextract-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        self.root = root
        self.sourceRoot = sourceRoot
        self.outputRoot = outputRoot
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

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private let collisionSceneSourceFixture = """
SceneCmd spot04_sceneCommands[] = {
    SCENE_CMD_ROOM_LIST(1, spot04_sceneRoomList0x000000),
    SCENE_CMD_COL_HEADER(&spot04_sceneCollisionHeader_000100),
    SCENE_CMD_END(),
};

Vec3s spot04_sceneCollisionHeader_000100Vertices[] = {
    { -10, 0, -20 },
    { 20, 5, 30 },
    { 40, 10, 50 },
};

CollisionPoly spot04_sceneCollisionHeader_000100Polygons[] = {
    { 0x0000, 0x0000, 0x2001, 0x4002, { 0x0000, 0x7FFF, 0x0000 }, -10 },
    { 0x0001, 0x0002, 0x0001, 0x0000, 0x0001, 0x0002, 0x0003, 0x0004 },
};

SurfaceType spot04_sceneCollisionHeader_000100SurfaceTypes[] = {
    { 0x12345678, 0x90ABCDEF },
    { 0x00000001, 0x00000002 },
};

WaterBox spot04_sceneCollisionHeader_000100WaterBoxes[] = {
    { -100, 20, -200, 300, 400, 0x01020304 },
};

CollisionHeader spot04_sceneCollisionHeader_000100 = {
    { -1000, -200, -3000 },
    { 4000, 500, 6000 },
    ARRAY_COUNT(spot04_sceneCollisionHeader_000100Vertices), spot04_sceneCollisionHeader_000100Vertices,
    ARRAY_COUNT(spot04_sceneCollisionHeader_000100Polygons), spot04_sceneCollisionHeader_000100Polygons,
    spot04_sceneCollisionHeader_000100SurfaceTypes,
    NULL,
    ARRAY_COUNT(spot04_sceneCollisionHeader_000100WaterBoxes), spot04_sceneCollisionHeader_000100WaterBoxes,
};
"""
