import OOTContent
import OOTDataModel

public struct SceneTransitionRequest: Sendable, Equatable {
    public var sceneID: Int
    public var entranceIndex: Int
    public var effect: SceneTransitionEffect

    public init(
        sceneID: Int,
        entranceIndex: Int,
        effect: SceneTransitionEffect
    ) {
        self.sceneID = sceneID
        self.entranceIndex = entranceIndex
        self.effect = effect
    }
}

public struct SceneManagerState: Sendable, Equatable {
    public var currentSceneID: Int
    public var currentRoomID: Int
    public var currentEntranceIndex: Int?
    public var currentSpawnIndex: Int?
    public var activeRoomIDs: Set<Int>
    public var loadedObjectIDs: [Int]
    public var transitionEffect: SceneTransitionEffect?
    public var objectSlotOverflow: Bool

    public init(
        currentSceneID: Int,
        currentRoomID: Int,
        currentEntranceIndex: Int?,
        currentSpawnIndex: Int?,
        activeRoomIDs: Set<Int>,
        loadedObjectIDs: [Int],
        transitionEffect: SceneTransitionEffect? = nil,
        objectSlotOverflow: Bool = false
    ) {
        self.currentSceneID = currentSceneID
        self.currentRoomID = currentRoomID
        self.currentEntranceIndex = currentEntranceIndex
        self.currentSpawnIndex = currentSpawnIndex
        self.activeRoomIDs = activeRoomIDs
        self.loadedObjectIDs = loadedObjectIDs
        self.transitionEffect = transitionEffect
        self.objectSlotOverflow = objectSlotOverflow
    }
}

public enum SceneManagerEvent: Sendable, Equatable {
    case roomTransition(SceneManagerState)
    case sceneTransition(SceneTransitionRequest)
}

public struct SceneManager: Sendable {
    private let scene: LoadedScene
    private let actorTableByID: [Int: ActorTableEntry]
    private let entranceTableByIndex: [Int: EntranceTableEntry]
    private let roomDefinitionsByID: [Int: SceneRoomDefinition]
    private let actorSpawnsByRoomID: [Int: [SceneActorSpawn]]

    public private(set) var state: SceneManagerState

    public init(
        scene: LoadedScene,
        actorTable: [ActorTableEntry],
        entranceTable: [EntranceTableEntry] = [],
        entranceIndex: Int? = nil,
        spawnIndex: Int? = nil,
        activeRoomIDs: Set<Int>? = nil
    ) {
        self.scene = scene
        actorTableByID = Dictionary(uniqueKeysWithValues: actorTable.map { ($0.id, $0) })
        entranceTableByIndex = Dictionary(uniqueKeysWithValues: entranceTable.map { ($0.index, $0) })
        roomDefinitionsByID = Dictionary(
            uniqueKeysWithValues: (scene.sceneHeader?.rooms ?? []).map { ($0.id, $0) }
        )
        actorSpawnsByRoomID = SceneManager.makeActorSpawnsByRoomID(scene: scene)

        let entry = SceneManager.resolveEntry(
            scene: scene,
            entranceTableByIndex: entranceTableByIndex,
            entranceIndex: entranceIndex,
            spawnIndex: spawnIndex,
            activeRoomIDs: activeRoomIDs
        )
        let objectSlots = SceneManager.resolveObjectSlots(
            scene: scene,
            roomDefinitionsByID: roomDefinitionsByID,
            actorSpawnsByRoomID: actorSpawnsByRoomID,
            actorTableByID: actorTableByID,
            activeRoomIDs: entry.activeRoomIDs
        )

        state = SceneManagerState(
            currentSceneID: scene.manifest.id,
            currentRoomID: entry.currentRoomID,
            currentEntranceIndex: entranceIndex,
            currentSpawnIndex: entry.spawnIndex,
            activeRoomIDs: entry.activeRoomIDs,
            loadedObjectIDs: objectSlots.ids,
            objectSlotOverflow: objectSlots.overflow
        )
    }

    public mutating func syncActiveRooms(_ roomIDs: Set<Int>) {
        let nextRoomIDs = roomIDs.isEmpty ? Set([state.currentRoomID]) : Set(roomIDs.prefix(2))
        let currentRoomID = nextRoomIDs.contains(state.currentRoomID)
            ? state.currentRoomID
            : nextRoomIDs.sorted().first ?? state.currentRoomID
        applyRoomState(
            currentRoomID: currentRoomID,
            activeRoomIDs: nextRoomIDs,
            transitionEffect: state.transitionEffect
        )
    }

    public mutating func activateDoor(id triggerID: Int) -> SceneManagerEvent? {
        guard
            let trigger = scene.sceneHeader?.transitionTriggers.first(where: { trigger in
                trigger.id == triggerID &&
                    trigger.kind == .door &&
                    (trigger.roomID == state.currentRoomID || trigger.destinationRoomID == state.currentRoomID)
            })
        else {
            return nil
        }

        let destinationRoomID: Int
        if state.currentRoomID == trigger.roomID {
            guard let configuredDestination = trigger.destinationRoomID else {
                return nil
            }
            destinationRoomID = configuredDestination
        } else {
            destinationRoomID = trigger.roomID
        }

        applyRoomState(
            currentRoomID: destinationRoomID,
            activeRoomIDs: [state.currentRoomID, destinationRoomID],
            transitionEffect: trigger.effect
        )
        return .roomTransition(state)
    }

    public mutating func evaluateLoadingZones(at position: Vector3s) -> SceneManagerEvent? {
        guard
            let trigger = scene.sceneHeader?.transitionTriggers.first(where: { trigger in
                trigger.kind == .loadingZone &&
                    trigger.roomID == state.currentRoomID &&
                    trigger.volume.contains(position)
            })
        else {
            return nil
        }

        if let destinationRoomID = trigger.destinationRoomID {
            applyRoomState(
                currentRoomID: destinationRoomID,
                activeRoomIDs: [state.currentRoomID, destinationRoomID],
                transitionEffect: trigger.effect
            )
            return .roomTransition(state)
        }

        guard
            let exitIndex = trigger.exitIndex,
            let exitDefinition = scene.exits?.exits.first(where: { $0.index == exitIndex }),
            let entrance = entranceTableByIndex[exitDefinition.entranceIndex]
        else {
            return nil
        }

        state.transitionEffect = trigger.effect
        return .sceneTransition(
            SceneTransitionRequest(
                sceneID: entrance.sceneID,
                entranceIndex: entrance.index,
                effect: trigger.effect
            )
        )
    }
}

private extension SceneManager {
    struct EntryResolution {
        let currentRoomID: Int
        let activeRoomIDs: Set<Int>
        let spawnIndex: Int?
    }

    struct ObjectSlotResolution {
        let ids: [Int]
        let overflow: Bool
    }

    static func resolveEntry(
        scene: LoadedScene,
        entranceTableByIndex: [Int: EntranceTableEntry],
        entranceIndex: Int?,
        spawnIndex: Int?,
        activeRoomIDs: Set<Int>?
    ) -> EntryResolution {
        if let activeRoomIDs, activeRoomIDs.isEmpty == false {
            return EntryResolution(
                currentRoomID: activeRoomIDs.sorted().first ?? fallbackRoomID(in: scene),
                activeRoomIDs: Set(activeRoomIDs.prefix(2)),
                spawnIndex: nil
            )
        }

        guard let sceneHeader = scene.sceneHeader else {
            let roomID = fallbackRoomID(in: scene)
            return EntryResolution(currentRoomID: roomID, activeRoomIDs: [roomID], spawnIndex: nil)
        }

        let entrance = sceneHeader.entrances.first { $0.index == entranceIndex } ?? sceneHeader.entrances.first
        let resolvedSpawnIndex =
            spawnIndex ??
            entranceTableByIndex[entranceIndex ?? -1]?.spawnIndex ??
            entrance?.spawnIndex
        let spawn = sceneHeader.spawns.first { $0.index == resolvedSpawnIndex } ?? sceneHeader.spawns.first
        let roomID = spawn?.roomID ?? fallbackRoomID(in: scene)

        return EntryResolution(
            currentRoomID: roomID,
            activeRoomIDs: [roomID],
            spawnIndex: spawn?.index
        )
    }

    static func fallbackRoomID(in scene: LoadedScene) -> Int {
        scene.manifest.rooms.first?.id ?? 0
    }

    static func makeActorSpawnsByRoomID(scene: LoadedScene) -> [Int: [SceneActorSpawn]] {
        let roomIDByName = Dictionary(uniqueKeysWithValues: scene.manifest.rooms.map { ($0.name, $0.id) })
        return Dictionary(
            uniqueKeysWithValues: (scene.actors?.rooms ?? []).compactMap { roomActors in
                guard let roomID = roomIDByName[roomActors.roomName] else {
                    return nil
                }
                return (roomID, roomActors.actors)
            }
        )
    }

    static func resolveObjectSlots(
        scene: LoadedScene,
        roomDefinitionsByID: [Int: SceneRoomDefinition],
        actorSpawnsByRoomID: [Int: [SceneActorSpawn]],
        actorTableByID: [Int: ActorTableEntry],
        activeRoomIDs: Set<Int>
    ) -> ObjectSlotResolution {
        var orderedObjectIDs: [Int] = []
        var seenObjectIDs: Set<Int> = []

        func appendObjectID(_ objectID: Int) {
            guard objectID > 0, seenObjectIDs.insert(objectID).inserted else {
                return
            }
            orderedObjectIDs.append(objectID)
        }

        for objectID in scene.sceneHeader?.sceneObjectIDs ?? [] {
            appendObjectID(objectID)
        }

        for roomID in activeRoomIDs.sorted() {
            for objectID in roomDefinitionsByID[roomID]?.objectIDs ?? [] {
                appendObjectID(objectID)
            }

            for spawn in actorSpawnsByRoomID[roomID] ?? [] {
                guard let objectID = actorTableByID[spawn.actorID]?.profile.objectID else {
                    continue
                }
                appendObjectID(objectID)
            }
        }

        return ObjectSlotResolution(
            ids: Array(orderedObjectIDs.prefix(19)),
            overflow: orderedObjectIDs.count > 19
        )
    }

    mutating func applyRoomState(
        currentRoomID: Int,
        activeRoomIDs: Set<Int>,
        transitionEffect: SceneTransitionEffect?
    ) {
        let normalizedActiveRoomIDs = Set(activeRoomIDs.prefix(2))
        let objectSlots = Self.resolveObjectSlots(
            scene: scene,
            roomDefinitionsByID: roomDefinitionsByID,
            actorSpawnsByRoomID: actorSpawnsByRoomID,
            actorTableByID: actorTableByID,
            activeRoomIDs: normalizedActiveRoomIDs
        )

        state.currentRoomID = currentRoomID
        state.activeRoomIDs = normalizedActiveRoomIDs
        state.loadedObjectIDs = objectSlots.ids
        state.transitionEffect = transitionEffect
        state.objectSlotOverflow = objectSlots.overflow
    }
}
