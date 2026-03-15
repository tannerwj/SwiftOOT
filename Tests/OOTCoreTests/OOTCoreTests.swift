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

    func testMessageContextRevealsPlayerNameDelayAndChoices() {
        var context = MessageContext(
            catalog: MessageCatalog(
                messageList: [
                    MessageDefinition(
                        id: 0x1000,
                        variant: .blue,
                        segments: [
                            .text("Hello "),
                            .playerName,
                            .delay(2),
                            .color(.yellow),
                            .text("!"),
                            .choice([
                                MessageChoiceOption(title: "Yes"),
                                MessageChoiceOption(title: "No"),
                            ]),
                        ]
                    ),
                ]
            )
        )

        context.enqueue(messageID: 0x1000, playerName: "Link")
        XCTAssertEqual(context.phase, .opening)

        for _ in 0..<6 {
            context.tick(playerName: "Link")
        }

        XCTAssertEqual(context.phase, .displaying)

        for _ in 0..<64 where context.phase != .waitingForChoice {
            context.tick(playerName: "Link")
        }

        XCTAssertEqual(
            context.activePresentation?.textRuns,
            [
                MessageTextRun(text: "Hello Link", color: .white),
                MessageTextRun(text: "!", color: .yellow),
            ]
        )
        XCTAssertEqual(context.phase, .waitingForChoice)
        XCTAssertEqual(context.activePresentation?.choiceState?.options.map(\.title), ["Yes", "No"])

        context.moveSelection(delta: 1)
        XCTAssertEqual(context.activePresentation?.choiceState?.selectedIndex, 1)

        context.advanceOrConfirm(playerName: "Link")
        XCTAssertEqual(context.phase, .closing)
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

    @MainActor
    func testLoadSceneSpawnsBaselineActorsUsingDefaultRegistry() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_EN_KO"),
                        makeSpawn(id: 2, name: "ACTOR_DOOR_SHUTTER"),
                        makeSpawn(id: 3, name: "ACTOR_EN_KANBAN"),
                        makeSpawn(id: 4, name: "ACTOR_OBJ_HANA"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_EN_KO", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_DOOR_SHUTTER", category: .door),
                makeActorTableEntry(id: 3, name: "ACTOR_EN_KANBAN", category: .prop),
                makeActorTableEntry(id: 4, name: "ACTOR_OBJ_HANA", category: .prop),
            ]
        )
        let runtime = GameRuntime(contentLoader: fixture.contentLoader, suspender: { _ in })

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [0])
        XCTAssertEqual(
            runtime.actors.map { String(describing: type(of: $0)) },
            [
                "KokiriChildActor",
                "SignActor",
                "GenericPropActor",
                "DoorActor",
            ]
        )
    }

    @MainActor
    func testUpdateCycleRespectsCategoryOrderAndDestroysActorsOnce() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "switch",
                recorder: recorder
            ) { actor, playState in
                playState.requestDestroy(actor)
            }
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "npc",
                recorder: recorder
            ) { actor, _ in
                actor.hitPoints = 0
            }
        }
        registry.register(actorID: 30) {
            RecordingActor(
                spawnRecord: $0,
                label: "door",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_SWITCH_TEST"),
                        makeSpawn(id: 20, name: "ACTOR_NPC_TEST"),
                        makeSpawn(id: 30, name: "ACTOR_DOOR_TEST"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_SWITCH_TEST", category: .switchActor),
                makeActorTableEntry(id: 20, name: "ACTOR_NPC_TEST", category: .npc),
                makeActorTableEntry(id: 30, name: "ACTOR_DOOR_TEST", category: .door),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        recorder.reset()

        runtime.updateFrame()

        XCTAssertEqual(
            recorder.events,
            [
                "update:switch",
                "destroy:switch",
                "update:npc",
                "destroy:npc",
                "update:door",
            ]
        )
        XCTAssertEqual(runtime.actors.count, 1)
    }

    @MainActor
    func testChangingActiveRoomsDespawnsLeavingActorsAndSpawnsNewRoomActors() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "room0",
                recorder: recorder
            )
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "room1",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [makeSpawn(id: 10, name: "ACTOR_ROOM0_TEST")],
                    1: [makeSpawn(id: 20, name: "ACTOR_ROOM1_TEST")],
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_ROOM0_TEST", category: .npc),
                makeActorTableEntry(id: 20, name: "ACTOR_ROOM1_TEST", category: .npc),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        XCTAssertEqual(recorder.events, ["init:room0"])

        runtime.setActiveRooms([1])

        XCTAssertEqual(
            recorder.events,
            [
                "init:room0",
                "destroy:room0",
                "init:room1",
            ]
        )
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [1])
        XCTAssertEqual(runtime.actors.count, 1)
    }

    func testPrimaryGameplayInputRequestsDialogueFromTalkActor() async throws {
        try await MainActor.run {
            let fixture = RuntimeFixture(
                scene: makeScene(
                    roomSpawns: [
                        0: [
                            makeSpawn(id: 1, name: "ACTOR_EN_KO", params: 0x1000),
                        ],
                    ]
                ),
                actorTable: [
                    makeActorTableEntry(id: 1, name: "ACTOR_EN_KO", category: .npc),
                ],
                messageCatalog: MessageCatalog(
                    messageList: [
                        MessageDefinition(
                            id: 0x1000,
                            variant: .white,
                            segments: [.text("Welcome to Kokiri Forest.") ]
                        ),
                    ]
                )
            )
            let runtime = GameRuntime(contentLoader: fixture.contentLoader, suspender: { _ in })

            try runtime.loadScene(id: 0x55)
            runtime.handlePrimaryGameplayInput()

            XCTAssertEqual(runtime.activeMessagePresentation?.messageID, 0x1000)
            XCTAssertEqual(runtime.gameplayActionLabel, "Next")
        }
    }

    @MainActor
    func testDrawPassesOnlyCallMatchingActors() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "opaque",
                recorder: recorder,
                drawPasses: [.opaque]
            )
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "translucent",
                recorder: recorder,
                drawPasses: [.translucent]
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_OPAQUE_TEST"),
                        makeSpawn(id: 20, name: "ACTOR_TRANSLUCENT_TEST"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_OPAQUE_TEST", category: .npc),
                makeActorTableEntry(id: 20, name: "ACTOR_TRANSLUCENT_TEST", category: .misc),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        recorder.reset()

        runtime.drawActors(in: .opaque)
        runtime.drawActors(in: .translucent)

        XCTAssertEqual(
            recorder.events,
            [
                "draw:opaque:opaque",
                "draw:translucent:translucent",
            ]
        )
        XCTAssertNil(runtime.playState?.currentDrawPass)
    }
}

private struct RuntimeFixture {
    let contentLoader: MockContentLoader

    init(
        scene: LoadedScene,
        actorTable: [ActorTableEntry],
        messageCatalog: MessageCatalog = MessageCatalog()
    ) {
        contentLoader = MockContentLoader(
            scene: scene,
            actorTable: actorTable,
            messageCatalog: messageCatalog
        )
    }
}

private struct MockContentLoader: ContentLoading {
    let scene: LoadedScene
    let actorTable: [ActorTableEntry]
    let messageCatalog: MessageCatalog

    func loadInitialContent() async throws {}

    func loadScene(id: Int) throws -> LoadedScene {
        scene
    }

    func loadActorTable() throws -> [ActorTableEntry] {
        actorTable
    }

    func loadMessageCatalog() throws -> MessageCatalog {
        messageCatalog
    }
}

@MainActor
private final class EventRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }
}

@MainActor
private final class RecordingActor: DamageableBaseActor {
    let label: String
    let recorder: EventRecorder
    let updateAction: (@MainActor (RecordingActor, PlayState) -> Void)?
    let configuredDrawPasses: Set<ActorDrawPass>

    init(
        spawnRecord: ActorSpawnRecord,
        label: String,
        recorder: EventRecorder,
        drawPasses: Set<ActorDrawPass> = [.opaque],
        updateAction: (@MainActor (RecordingActor, PlayState) -> Void)? = nil
    ) {
        self.label = label
        self.recorder = recorder
        self.configuredDrawPasses = drawPasses
        self.updateAction = updateAction
        super.init(spawnRecord: spawnRecord)
    }

    override var drawPasses: Set<ActorDrawPass> {
        configuredDrawPasses
    }

    override func initialize(playState: PlayState) {
        recorder.append("init:\(label)")
    }

    override func update(playState: PlayState) {
        recorder.append("update:\(label)")
        updateAction?(self, playState)
    }

    override func draw(playState: PlayState, pass: ActorDrawPass) {
        recorder.append("draw:\(label):\(pass.rawValue)")
    }

    override func destroy(playState: PlayState) {
        recorder.append("destroy:\(label)")
    }
}

private func makeScene(roomSpawns: [Int: [SceneActorSpawn]]) -> LoadedScene {
    let sortedRooms = roomSpawns.keys.sorted()
    let manifestRooms = sortedRooms.map { roomID in
        RoomManifest(
            id: roomID,
            name: "room_\(roomID)",
            directory: "Scenes/test/rooms/room_\(roomID)"
        )
    }
    let loadedRooms = manifestRooms.map { room in
        LoadedSceneRoom(
            manifest: room,
            displayList: [],
            vertexData: Data()
        )
    }
    let actors = SceneActorsFile(
        sceneName: "test_scene",
        rooms: manifestRooms.map { room in
            RoomActorSpawns(
                roomName: room.name,
                actors: roomSpawns[room.id, default: []]
            )
        }
    )

    return LoadedScene(
        manifest: SceneManifest(
            id: 0x55,
            name: "test_scene",
            rooms: manifestRooms,
            actorsPath: "Manifests/scenes/test_scene/actors.json"
        ),
        actors: actors,
        rooms: loadedRooms
    )
}

private func makeSpawn(
    id: Int,
    name: String,
    position: Vector3s = Vector3s(x: 0, y: 0, z: 0),
    rotation: Vector3s = Vector3s(x: 0, y: 0, z: 0),
    params: Int16 = 0
) -> SceneActorSpawn {
    SceneActorSpawn(
        actorID: id,
        actorName: name,
        position: position,
        rotation: rotation,
        params: params
    )
}

private func makeActorTableEntry(
    id: Int,
    name: String,
    category: ActorCategory
) -> ActorTableEntry {
    ActorTableEntry(
        id: id,
        enumName: name,
        profile: ActorProfile(
            id: id,
            category: category.rawValue,
            flags: 0,
            objectID: 0
        )
    )
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

    func loadActorTable() throws -> [ActorTableEntry] {
        []
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
