import XCTest
import OOTContent
import OOTDataModel
import OOTTelemetry
@testable import OOTCore
import simd

final class OOTCoreTests: XCTestCase {
    func testGameRuntimeBootstrapsSpot04ByDefault() async {
        let runtime = await MainActor.run {
            GameRuntime(
                sceneLoader: MockSceneLoader(),
                telemetryPublisher: TelemetryPublisher(),
                suspender: { _ in }
            )
        }

        await runtime.bootstrapSceneViewer()

        await MainActor.run {
            XCTAssertEqual(runtime.sceneViewerState, .running)
            XCTAssertEqual(runtime.selectedSceneID, 0x55)
            XCTAssertEqual(runtime.availableScenes.map(\.index), [0x01, 0x55])
            XCTAssertEqual(runtime.loadedScene?.manifest.name, "spot04")
            XCTAssertEqual(
                runtime.textureAssetURLs[OOTAssetID.stableID(for: "gSpot04MainTex")]?.lastPathComponent,
                "gSpot04MainTex.tex.bin"
            )
        }
    }

    @MainActor
    func testGameRuntimeStartsWithBootStateAndRequiredProperties() {
        let runtime = GameRuntime(suspender: { _ in })

        XCTAssertEqual(runtime.currentState, .boot)
        XCTAssertNil(runtime.playState)
        XCTAssertEqual(runtime.saveContext.slots.count, 3)
        XCTAssertFalse(runtime.canContinue)
        XCTAssertEqual(runtime.inputState.selectionIndex, 0)
        XCTAssertEqual(runtime.sceneViewerState, .idle)
    }

    @MainActor
    func testStartAdvancesFromBootToTitleScreen() async {
        let runtime = GameRuntime(suspender: { _ in })

        await runtime.start()

        XCTAssertEqual(runtime.currentState, .titleScreen)
        XCTAssertEqual(runtime.gameTime.frameCount, 2)
    }

    @MainActor
    func testChoosingNewGameOpensFileSelectAndStartsGameplay() async {
        let runtime = GameRuntime(suspender: { _ in })
        await runtime.start()

        runtime.chooseTitleOption(.newGame)

        XCTAssertEqual(runtime.currentState, .fileSelect)
        XCTAssertEqual(runtime.fileSelectMode, .newGame)
        XCTAssertEqual(runtime.saveContext.selectedSlotIndex, 0)

        runtime.selectSaveSlot(2)
        runtime.confirmSelectedSaveSlot()

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .newGame)
        XCTAssertEqual(runtime.playState?.activeSaveSlot, 2)
        XCTAssertTrue(runtime.saveContext.slots[2].hasSaveData)
    }

    @MainActor
    func testContinueWithoutSaveStaysOnTitleScreen() async {
        let runtime = GameRuntime(suspender: { _ in })
        await runtime.start()

        runtime.chooseTitleOption(.continueGame)

        XCTAssertEqual(runtime.currentState, .titleScreen)
        XCTAssertNil(runtime.fileSelectMode)
        XCTAssertEqual(runtime.statusMessage, "No saved games are available yet.")
    }

    @MainActor
    func testContinueUsesFirstOccupiedSaveSlot() async {
        let runtime = GameRuntime(
            saveContext: SaveContext(
                slots: [
                    .empty(id: 0),
                    SaveSlot(id: 1, playerName: "Link", locationName: "Hyrule Field", hearts: 4, hasSaveData: true),
                    .empty(id: 2),
                ]
            ),
            suspender: { _ in }
        )
        await runtime.start()

        runtime.chooseTitleOption(.continueGame)

        XCTAssertEqual(runtime.currentState, .fileSelect)
        XCTAssertEqual(runtime.fileSelectMode, .continueGame)
        XCTAssertEqual(runtime.saveContext.selectedSlotIndex, 1)

        runtime.confirmSelectedSaveSlot()

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .continueGame)
        XCTAssertEqual(runtime.playState?.currentSceneName, "Hyrule Field")
    }

    func testCollisionSystemFindsFloorAndCeiling() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        let floor = system.findFloor(at: SIMD3<Float>(2, 4, 2))
        let ceiling = system.checkCeiling(at: SIMD3<Float>(2, 4, 2))

        XCTAssertNotNil(floor)
        XCTAssertNotNil(ceiling)
        XCTAssertEqual(Double(floor!.floorY), 0, accuracy: 0.001)
        XCTAssertEqual(floor?.polygon.surfaceType?.floorType, 4)
        XCTAssertEqual(Double(ceiling!.ceilingY), 8, accuracy: 0.001)
        XCTAssertEqual(ceiling?.polygon.surfaceType?.canHookshot, true)
    }

    func testCollisionSystemPushesSphereOutOfWall() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        let hit = system.checkWall(
            at: SIMD3<Float>(4.2, 2, 5),
            radius: 0.5,
            displacement: SIMD3<Float>(1, 0, 0)
        )

        XCTAssertNotNil(hit)
        XCTAssertLessThan(hit!.displacement.x, 0)
        XCTAssertEqual(hit?.polygon.surfaceType?.wallType, 7)
    }

    func testCollisionSystemReportsLineOcclusion() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        XCTAssertTrue(
            system.checkLineOcclusion(
                from: SIMD3<Float>(2, 2, 5),
                to: SIMD3<Float>(8, 2, 5)
            )
        )
        XCTAssertFalse(
            system.checkLineOcclusion(
                from: SIMD3<Float>(2, 9, 5),
                to: SIMD3<Float>(8, 9, 5)
            )
        )
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

    func loadCollisionMesh(for manifest: SceneManifest) throws -> CollisionMesh? {
        nil
    }

    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] {
        []
    }

    func loadRoomVertexData(for room: RoomManifest) throws -> Data {
        Data()
    }
}

private func fixtureCollisionMesh() -> CollisionMesh {
    CollisionMesh(
        minimumBounds: Vector3s(x: 0, y: 0, z: 0),
        maximumBounds: Vector3s(x: 10, y: 8, z: 10),
        vertices: [
            Vector3s(x: 0, y: 0, z: 0),
            Vector3s(x: 10, y: 0, z: 0),
            Vector3s(x: 0, y: 0, z: 10),
            Vector3s(x: 10, y: 0, z: 10),
            Vector3s(x: 0, y: 8, z: 0),
            Vector3s(x: 0, y: 8, z: 10),
            Vector3s(x: 10, y: 8, z: 0),
            Vector3s(x: 10, y: 8, z: 10),
            Vector3s(x: 5, y: 0, z: 0),
            Vector3s(x: 5, y: 0, z: 10),
            Vector3s(x: 5, y: 8, z: 0),
            Vector3s(x: 5, y: 8, z: 10),
        ],
        polygons: [
            CollisionPoly(
                surfaceType: 0,
                vertexA: 0,
                vertexB: 1,
                vertexC: 2,
                normal: Vector3s(x: 0, y: 0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 0,
                vertexA: 1,
                vertexB: 3,
                vertexC: 2,
                normal: Vector3s(x: 0, y: 0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 1,
                vertexA: 4,
                vertexB: 5,
                vertexC: 6,
                normal: Vector3s(x: 0, y: -0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 1,
                vertexA: 6,
                vertexB: 5,
                vertexC: 7,
                normal: Vector3s(x: 0, y: -0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 2,
                vertexA: 8,
                vertexB: 9,
                vertexC: 10,
                normal: Vector3s(x: 0x7FFF, y: 0, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 2,
                vertexA: 10,
                vertexB: 9,
                vertexC: 11,
                normal: Vector3s(x: 0x7FFF, y: 0, z: 0),
                distance: 0
            ),
        ],
        surfaceTypes: [
            CollisionSurfaceType(low: (4 << 13), high: 0),
            CollisionSurfaceType(low: 0, high: (1 << 17)),
            CollisionSurfaceType(low: (7 << 21), high: 0),
        ]
    )
}
