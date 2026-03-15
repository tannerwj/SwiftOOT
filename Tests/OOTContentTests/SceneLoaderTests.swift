import Foundation
import XCTest
@testable import OOTContent
import OOTDataModel

final class SceneLoaderTests: XCTestCase {
    func testSceneLoaderLoadsSpot04FixtureBySceneID() throws {
        let fixture = try SceneLoaderFixture()
        defer { fixture.cleanup() }

        let loader = SceneLoader(contentRoot: fixture.contentRoot)

        let sceneDirectory = try loader.resolveSceneDirectory(for: 0x55)
        XCTAssertEqual(sceneDirectory.path, fixture.sceneDirectory.path)

        let scene = try loader.loadScene(id: 0x55)

        XCTAssertEqual(scene.manifest.name, "spot04")
        XCTAssertEqual(scene.manifest.rooms.count, 2)
        XCTAssertEqual(
            scene.rooms[0].displayList,
            [
                .spVertex(VertexCommand(address: 0x03000000, count: 3, destinationIndex: 0)),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ]
        )
        XCTAssertEqual(scene.rooms[1].displayList.count, 2)
        XCTAssertEqual(scene.rooms.map { $0.vertexData.count }, [3 * 16, 1 * 16])

        XCTAssertEqual(scene.actors, fixture.actors)
        XCTAssertEqual(scene.environment, fixture.environment)
        XCTAssertEqual(scene.paths, fixture.paths)
    }

    func testSceneLoaderAcceptsLegacyManifestFilename() throws {
        let fixture = try SceneLoaderFixture(manifestFilename: "scene_manifest.json")
        defer { fixture.cleanup() }

        let loader = SceneLoader(contentRoot: fixture.contentRoot)
        let manifest = try loader.loadSceneManifest(named: "spot04")

        XCTAssertEqual(manifest.id, 0x55)
        XCTAssertEqual(manifest.rooms.count, 2)
    }

    func testSceneLoaderResolvesTextureAssetURLsByStableID() throws {
        let fixture = try SceneLoaderFixture()
        defer { fixture.cleanup() }

        let loader = SceneLoader(contentRoot: fixture.contentRoot)
        let scene = try loader.loadScene(id: 0x55)
        let textureURLs = try loader.loadTextureAssetURLs(for: scene)

        XCTAssertEqual(
            textureURLs[OOTAssetID.stableID(for: "gSpot04MainTex")]?.lastPathComponent,
            "gSpot04MainTex.tex.bin"
        )
        XCTAssertEqual(
            textureURLs[OOTAssetID.stableID(for: "gSpot04Room0Tex")]?.lastPathComponent,
            "gSpot04Room0Tex.tex.bin"
        )
    }
}

private struct SceneLoaderFixture {
    let root: URL
    let contentRoot: URL
    let sceneDirectory: URL
    let actors: SceneActorsFile
    let environment: SceneEnvironmentFile
    let paths: ScenePathsFile

    init(manifestFilename: String = "SceneManifest.json") throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("swiftoot-sceneloader-\(UUID().uuidString)", isDirectory: true)
        contentRoot = root
            .appendingPathComponent("Content", isDirectory: true)
            .appendingPathComponent("OOT", isDirectory: true)
        sceneDirectory = contentRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)

        actors = SceneActorsFile(
            sceneName: "spot04",
            rooms: [
                RoomActorSpawns(
                    roomName: "spot04_room_0",
                    actors: [
                        SceneActorSpawn(
                            actorID: 5,
                            actorName: "ACTOR_EN_OKUTA",
                            position: Vector3s(x: 10, y: 20, z: 30),
                            rotation: Vector3s(x: 0, y: 0, z: 0),
                            params: 12
                        )
                    ]
                ),
                RoomActorSpawns(roomName: "spot04_room_1", actors: []),
            ]
        )
        environment = SceneEnvironmentFile(
            sceneName: "spot04",
            time: SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 0),
            skybox: SceneSkyboxSettings(
                skyboxID: 29,
                skyboxConfig: 0,
                environmentLightingMode: "LIGHT_MODE_TIME",
                skyboxDisabled: false,
                sunMoonDisabled: false
            ),
            lightSettings: [
                SceneLightSetting(
                    ambientColor: RGB8(red: 70, green: 80, blue: 90),
                    light1Direction: Vector3b(x: 1, y: 2, z: 3),
                    light1Color: RGB8(red: 100, green: 110, blue: 120),
                    light2Direction: Vector3b(x: -1, y: -2, z: -3),
                    light2Color: RGB8(red: 130, green: 140, blue: 150),
                    fogColor: RGB8(red: 160, green: 170, blue: 180),
                    blendRate: 4,
                    fogNear: 900,
                    zFar: 1000
                )
            ]
        )
        paths = ScenePathsFile(
            sceneName: "spot04",
            paths: [
                ScenePathDefinition(
                    index: 0,
                    pointsName: "spot04_scenePathwayList_0002D4",
                    points: [
                        Vector3s(x: 1, y: 2, z: 3),
                        Vector3s(x: 4, y: 5, z: 6),
                    ]
                )
            ]
        )

        try fileManager.createDirectory(at: contentRoot, withIntermediateDirectories: true)
        try seedSceneTable()
        try seedSceneManifest(filename: manifestFilename)
        try seedSceneMetadata()
        try seedTextureAssets()
        try seedRoom(
            id: 0,
            vertices: [
                N64Vertex(
                    position: Vector3s(x: -1, y: 2, z: 3),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 4, y: 5),
                    colorOrNormal: RGBA8(red: 255, green: 200, blue: 150, alpha: 100)
                ),
                N64Vertex(
                    position: Vector3s(x: 6, y: 7, z: 8),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 9, y: 10),
                    colorOrNormal: RGBA8(red: 11, green: 12, blue: 13, alpha: 14)
                ),
                N64Vertex(
                    position: Vector3s(x: 15, y: 16, z: 17),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 18, y: 19),
                    colorOrNormal: RGBA8(red: 20, green: 21, blue: 22, alpha: 23)
                ),
            ],
            commands: [
                .spVertex(VertexCommand(address: 0x03000000, count: 3, destinationIndex: 0)),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ]
        )
        try seedRoom(
            id: 1,
            vertices: [
                N64Vertex(
                    position: Vector3s(x: 24, y: 25, z: 26),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 27, y: 28),
                    colorOrNormal: RGBA8(red: 29, green: 30, blue: 31, alpha: 32)
                )
            ],
            commands: [
                .spVertex(VertexCommand(address: 0x03000030, count: 1, destinationIndex: 0)),
                .spEndDisplayList,
            ]
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private func seedSceneTable() throws {
        try writeJSON(
            [
                SceneTableEntry(
                    index: 0x55,
                    segmentName: "spot04_scene",
                    enumName: "SCENE_KOKIRI_FOREST",
                    title: "g_pn_31",
                    drawConfig: 0
                )
            ],
            to: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("scene-table.json")
        )
    }

    private func seedSceneManifest(filename: String) throws {
        try writeJSON(
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
                    ),
                    RoomManifest(
                        id: 1,
                        name: "spot04_room_1",
                        directory: "Scenes/spot04/rooms/room_1"
                    ),
                ],
                collisionPath: "Scenes/spot04/collision.bin",
                actorsPath: "Manifests/scenes/overworld/spot04/actors.json",
                environmentPath: "Manifests/scenes/overworld/spot04/environment.json",
                pathsPath: "Manifests/scenes/overworld/spot04/paths.json",
                textureDirectories: ["Textures/spot04_scene"]
            ),
            to: sceneDirectory.appendingPathComponent(filename)
        )
    }

    private func seedSceneMetadata() throws {
        let metadataRoot = contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
            .appendingPathComponent("overworld", isDirectory: true)
            .appendingPathComponent("spot04", isDirectory: true)

        try writeJSON(actors, to: metadataRoot.appendingPathComponent("actors.json"))
        try writeJSON(environment, to: metadataRoot.appendingPathComponent("environment.json"))
        try writeJSON(paths, to: metadataRoot.appendingPathComponent("paths.json"))
    }

    private func seedTextureAssets() throws {
        try seedTexture(
            relativeDirectory: "Textures/spot04_scene",
            name: "gSpot04MainTex"
        )
        try seedTexture(
            relativeDirectory: "Textures/spot04_room_0",
            name: "gSpot04Room0Tex"
        )
    }

    private func seedRoom(
        id: Int,
        vertices: [N64Vertex],
        commands: [F3DEX2Command]
    ) throws {
        let roomDirectory = sceneDirectory
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: roomDirectory, withIntermediateDirectories: true)

        try vertexBinary(for: vertices).write(
            to: roomDirectory.appendingPathComponent("vtx.bin"),
            options: .atomic
        )
        try writeJSON(commands, to: roomDirectory.appendingPathComponent("dl.json"))
    }

    private func seedTexture(
        relativeDirectory: String,
        name: String
    ) throws {
        let directory = contentRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0, 0, 0, 255]).write(
            to: directory.appendingPathComponent("\(name).tex.bin"),
            options: .atomic
        )
        try writeJSON(
            TextureAssetMetadata(format: .rgba16, width: 1, height: 1, hasTLUT: false),
            to: directory.appendingPathComponent("\(name).tex.json")
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func vertexBinary(for vertices: [N64Vertex]) -> Data {
        var data = Data()
        data.reserveCapacity(vertices.count * 16)

        for vertex in vertices {
            append(vertex.position.x, to: &data)
            append(vertex.position.y, to: &data)
            append(vertex.position.z, to: &data)
            append(vertex.flag, to: &data)
            append(vertex.textureCoordinate.x, to: &data)
            append(vertex.textureCoordinate.y, to: &data)
            data.append(contentsOf: [
                vertex.colorOrNormal.red,
                vertex.colorOrNormal.green,
                vertex.colorOrNormal.blue,
                vertex.colorOrNormal.alpha,
            ])
        }

        return data
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
