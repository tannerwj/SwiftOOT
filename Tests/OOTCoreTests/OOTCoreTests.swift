import XCTest
import OOTContent
import OOTDataModel
import OOTTelemetry
@testable import OOTCore

final class OOTCoreTests: XCTestCase {
    func testGameRuntimeBootstrapsSpot04ByDefault() async {
        let runtime = await MainActor.run {
            GameRuntime(
                sceneLoader: MockSceneLoader(),
                telemetryPublisher: TelemetryPublisher()
            )
        }

        await runtime.bootstrapSceneViewer()

        await MainActor.run {
            XCTAssertEqual(runtime.state, .running)
            XCTAssertEqual(runtime.selectedSceneID, 0x55)
            XCTAssertEqual(runtime.availableScenes.map(\.index), [0x01, 0x55])
            XCTAssertEqual(runtime.loadedScene?.manifest.name, "spot04")
            XCTAssertEqual(
                runtime.textureAssetURLs[OOTAssetID.stableID(for: "gSpot04MainTex")]?.lastPathComponent,
                "gSpot04MainTex.tex.bin"
            )
        }
    }
}

private struct MockSceneLoader: SceneLoading {
    private let sceneEntries = [
        SceneTableEntry(index: 0x01, segmentName: "spot01_scene", enumName: "SCENE_TEST"),
        SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
    ]

    func loadSceneTableEntries() throws -> [SceneTableEntry] {
        sceneEntries
    }

    func resolveSceneDirectory(for sceneID: Int) throws -> URL {
        URL(fileURLWithPath: "/tmp/scene-\(sceneID)", isDirectory: true)
    }

    func loadScene(id: Int) throws -> LoadedScene {
        let manifest = SceneManifest(
            id: id,
            name: id == 0x55 ? "spot04" : "spot01",
            rooms: [
                RoomManifest(
                    id: 0,
                    name: "room_0",
                    directory: "Scenes/room_0"
                )
            ],
            textureDirectories: ["Textures/spot04_scene"]
        )
        return LoadedScene(
            manifest: manifest,
            rooms: [
                LoadedSceneRoom(
                    manifest: manifest.rooms[0],
                    displayList: [],
                    vertexData: Data(repeating: 0, count: MemoryLayout<N64Vertex>.stride)
                )
            ]
        )
    }

    func loadScene(named name: String) throws -> LoadedScene {
        try loadScene(id: name == "spot04" ? 0x55 : 0x01)
    }

    func loadTextureAssetURLs(for scene: LoadedScene) throws -> [UInt32: URL] {
        [
            OOTAssetID.stableID(for: "gSpot04MainTex"):
                URL(fileURLWithPath: "/tmp/gSpot04MainTex.tex.bin")
        ]
    }

    func loadSceneManifest(id: Int) throws -> SceneManifest {
        try loadScene(id: id).manifest
    }

    func loadSceneManifest(named name: String) throws -> SceneManifest {
        try loadScene(named: name).manifest
    }

    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] {
        []
    }

    func loadRoomVertexData(for room: RoomManifest) throws -> Data {
        Data()
    }
}
