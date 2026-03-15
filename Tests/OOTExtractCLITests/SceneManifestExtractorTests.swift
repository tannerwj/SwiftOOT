import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class SceneManifestExtractorTests: XCTestCase {
    func testExtractWritesSceneManifestUsingSceneTableLookup() throws {
        let harness = try ManifestHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML()
        try harness.seedSceneTableManifest(
            entries: [
                SceneTableEntry(
                    index: 0x55,
                    segmentName: "spot04_scene",
                    enumName: "SCENE_KOKIRI_FOREST",
                    title: "g_pn_31",
                    drawConfig: 0
                )
            ]
        )
        try harness.seedSceneOutputs()

        let extractor = SceneManifestExtractor()
        try extractor.extract(using: harness.extractionContext(sceneName: "spot04"))

        let manifest = try JSONDecoder().decode(
            SceneManifest.self,
            from: Data(contentsOf: harness.outputRoot.appendingPathComponent("Scenes/spot04/SceneManifest.json"))
        )
        let metadataPrefix = "Manifests/scenes/\(harness.sceneCategoryPath())/spot04"

        XCTAssertEqual(
            manifest,
            SceneManifest(
                id: 0x55,
                name: "spot04",
                title: "g_pn_31",
                drawConfig: 0,
                rooms: [
                    RoomManifest(
                        id: 0,
                        name: "spot04_room_0",
                        directory: "Scenes/spot04/rooms/room_0",
                        textureDirectories: ["Textures/spot04_room_0"]
                    )
                ],
                collisionPath: "Scenes/spot04/collision.bin",
                actorsPath: "\(metadataPrefix)/actors.json",
                environmentPath: "\(metadataPrefix)/environment.json",
                pathsPath: "\(metadataPrefix)/paths.json",
                exitsPath: "\(metadataPrefix)/exits.json",
                textureDirectories: ["Textures/spot04_scene"]
            )
        )

        try extractor.verify(using: harness.verificationContext)
    }

    func testVerifyFailsWhenManifestReferenceIsMissing() throws {
        let harness = try ManifestHarness()
        defer { harness.cleanup() }

        try harness.writeSceneXML()
        try harness.seedSceneTableManifest(
            entries: [
                SceneTableEntry(
                    index: 0x55,
                    segmentName: "spot04_scene",
                    enumName: "SCENE_KOKIRI_FOREST",
                    title: "g_pn_31",
                    drawConfig: 0
                )
            ]
        )
        try harness.seedSceneOutputs()

        let extractor = SceneManifestExtractor()
        try extractor.extract(using: harness.extractionContext(sceneName: "spot04"))

        try FileManager.default.removeItem(
            at: harness.outputRoot.appendingPathComponent("Scenes/spot04/rooms/room_0/vtx.bin")
        )

        XCTAssertThrowsError(try extractor.verify(using: harness.verificationContext)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("vtx.bin"),
                "Unexpected error: \(error.localizedDescription)"
            )
        }
    }
}

private struct ManifestHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("swiftoot-scenemanifest-\(UUID().uuidString)", isDirectory: true)
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

    func extractionContext(sceneName: String? = nil) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneName: sceneName)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeSceneXML() throws {
        try writeFile(
            at: sourceRoot.appendingPathComponent("assets/xml/scenes/overworld/spot04.xml"),
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
    }

    func seedSceneTableManifest(entries: [SceneTableEntry]) throws {
        try writeJSON(
            entries,
            to: outputRoot.appendingPathComponent("Manifests/tables/scene-table.json")
        )
    }

    func seedSceneOutputs() throws {
        let roomDirectory = outputRoot.appendingPathComponent("Scenes/spot04/rooms/room_0", isDirectory: true)
        try FileManager.default.createDirectory(at: roomDirectory, withIntermediateDirectories: true)

        let vertices = [
            N64Vertex(
                position: Vector3s(x: 1, y: 2, z: 3),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
            )
        ]
        try VertexParser.encode(vertices).write(
            to: roomDirectory.appendingPathComponent("vtx.bin"),
            options: .atomic
        )
        try writeJSON(
            [F3DEX2Command.spEndDisplayList],
            to: roomDirectory.appendingPathComponent("dl.json")
        )

        let collision = CollisionSceneBinary(
            minimumBounds: Vector3s(x: 0, y: 0, z: 0),
            maximumBounds: Vector3s(x: 10, y: 10, z: 10),
            vertices: [Vector3s(x: 0, y: 0, z: 0)],
            polygons: [],
            surfaceTypes: [],
            waterBoxes: []
        )
        try CollisionExtractor.encode(collision).write(
            to: outputRoot.appendingPathComponent("Scenes/spot04/collision.bin"),
            options: .atomic
        )

        let metadataRoot = outputRoot
            .appendingPathComponent("Manifests/scenes", isDirectory: true)
            .appendingPathComponent(sceneCategoryPath(), isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
        try writeJSON(
            SceneActorsFile(sceneName: "spot04", rooms: [RoomActorSpawns(roomName: "spot04_room_0", actors: [])]),
            to: metadataRoot.appendingPathComponent("actors.json")
        )
        try writeJSON(
            SceneEnvironmentFile(
                sceneName: "spot04",
                time: SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 255),
                skybox: SceneSkyboxSettings(
                    skyboxID: 29,
                    skyboxConfig: 0,
                    environmentLightingMode: "false",
                    skyboxDisabled: false,
                    sunMoonDisabled: false
                ),
                lightSettings: []
            ),
            to: metadataRoot.appendingPathComponent("environment.json")
        )
        try writeJSON(
            ScenePathsFile(sceneName: "spot04", paths: []),
            to: metadataRoot.appendingPathComponent("paths.json")
        )
        try writeJSON(
            SceneExitsFile(sceneName: "spot04", exits: []),
            to: metadataRoot.appendingPathComponent("exits.json")
        )

        try FileManager.default.createDirectory(
            at: outputRoot.appendingPathComponent("Textures/spot04_scene", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outputRoot.appendingPathComponent("Textures/spot04_room_0", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func writeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func sceneCategoryPath() -> String {
        let xmlRoot = sourceRoot
            .appendingPathComponent("assets/xml/scenes", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let sceneParent = sourceRoot
            .appendingPathComponent("assets/xml/scenes/overworld", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return sceneParent.pathComponents
            .dropFirst(xmlRoot.pathComponents.count)
            .joined(separator: "/")
    }
}
