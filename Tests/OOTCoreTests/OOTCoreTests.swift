import XCTest
import OOTContent
import OOTDataModel
@testable import OOTCore

final class OOTCoreTests: XCTestCase {
    @MainActor
    func testGameRuntimeStartsIdle() {
        let runtime = GameRuntime()

        XCTAssertEqual(runtime.state, .idle)
        XCTAssertTrue(runtime.actors.isEmpty)
        XCTAssertNil(runtime.playState)
    }

    @MainActor
    func testLoadSceneSpawnsBaselineActorsUsingDefaultRegistry() async throws {
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
        let runtime = GameRuntime(contentLoader: fixture.contentLoader)

        try await runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.state, .running)
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
    func testUpdateCycleRespectsCategoryOrderAndDestroysActorsOnce() async throws {
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
            actorRegistry: registry
        )

        try await runtime.loadScene(id: 0x55)
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
        XCTAssertEqual(runtime.actors.map { String(describing: type(of: $0)) }, ["RecordingActor"])
    }

    @MainActor
    func testChangingActiveRoomsDespawnsLeavingActorsAndSpawnsNewRoomActors() async throws {
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
            actorRegistry: registry
        )

        try await runtime.loadScene(id: 0x55)
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

    @MainActor
    func testDrawPassesOnlyCallMatchingActors() async throws {
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
            actorRegistry: registry
        )

        try await runtime.loadScene(id: 0x55)
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

    init(scene: LoadedScene, actorTable: [ActorTableEntry]) {
        contentLoader = MockContentLoader(scene: scene, actorTable: actorTable)
    }
}

private struct MockContentLoader: ContentLoading {
    let scene: LoadedScene
    let actorTable: [ActorTableEntry]

    func loadInitialContent() async throws {}

    func loadScene(id: Int) async throws -> LoadedScene {
        scene
    }

    func loadActorTable() async throws -> [ActorTableEntry] {
        actorTable
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
