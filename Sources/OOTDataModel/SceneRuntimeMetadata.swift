public enum SceneTransitionEffect: String, Codable, Sendable, Equatable {
    case circleIris
    case fade
    case wipe
}

public enum SceneTransitionTriggerKind: String, Codable, Sendable, Equatable {
    case door
    case loadingZone
}

public enum SceneRoomShape: String, Codable, Sendable, Equatable {
    case normal
    case image
    case cullable
}

public struct SceneTriggerVolume: Codable, Sendable, Equatable {
    public var minimum: Vector3s
    public var maximum: Vector3s

    public init(minimum: Vector3s, maximum: Vector3s) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ point: Vector3s) -> Bool {
        point.x >= minimum.x && point.x <= maximum.x &&
            point.y >= minimum.y && point.y <= maximum.y &&
            point.z >= minimum.z && point.z <= maximum.z
    }
}

public struct SceneEntranceDefinition: Codable, Sendable, Equatable {
    public var index: Int
    public var spawnIndex: Int

    public init(index: Int, spawnIndex: Int) {
        self.index = index
        self.spawnIndex = spawnIndex
    }
}

public struct SceneRoomBehavior: Codable, Sendable, Equatable {
    public var disableWarpSongs: Bool
    public var showInvisibleActors: Bool

    public init(
        disableWarpSongs: Bool,
        showInvisibleActors: Bool
    ) {
        self.disableWarpSongs = disableWarpSongs
        self.showInvisibleActors = showInvisibleActors
    }
}

public struct SceneRoomDefinition: Codable, Sendable, Equatable {
    public var id: Int
    public var shape: SceneRoomShape
    public var objectIDs: [Int]
    public var echo: Int?
    public var behavior: SceneRoomBehavior?

    public init(
        id: Int,
        shape: SceneRoomShape,
        objectIDs: [Int] = [],
        echo: Int? = nil,
        behavior: SceneRoomBehavior? = nil
    ) {
        self.id = id
        self.shape = shape
        self.objectIDs = objectIDs
        self.echo = echo
        self.behavior = behavior
    }
}

public struct SceneTransitionTrigger: Codable, Sendable, Equatable {
    public var id: Int
    public var kind: SceneTransitionTriggerKind
    public var roomID: Int
    public var destinationRoomID: Int?
    public var exitIndex: Int?
    public var effect: SceneTransitionEffect
    public var volume: SceneTriggerVolume

    public init(
        id: Int,
        kind: SceneTransitionTriggerKind,
        roomID: Int,
        destinationRoomID: Int? = nil,
        exitIndex: Int? = nil,
        effect: SceneTransitionEffect,
        volume: SceneTriggerVolume
    ) {
        self.id = id
        self.kind = kind
        self.roomID = roomID
        self.destinationRoomID = destinationRoomID
        self.exitIndex = exitIndex
        self.effect = effect
        self.volume = volume
    }
}

public struct SceneCylinderTriggerVolume: Codable, Sendable, Equatable {
    public var center: Vector3s
    public var radius: Int16
    public var minimumY: Int16?
    public var maximumY: Int16?

    public init(
        center: Vector3s,
        radius: Int16,
        minimumY: Int16? = nil,
        maximumY: Int16? = nil
    ) {
        self.center = center
        self.radius = max(0, radius)
        self.minimumY = minimumY
        self.maximumY = maximumY
    }
}

public struct SceneCutsceneTrigger: Codable, Sendable, Equatable {
    public var id: Int
    public var roomID: Int
    public var actorName: String
    public var params: Int16
    public var kind: String
    public var volume: SceneCylinderTriggerVolume

    public init(
        id: Int,
        roomID: Int,
        actorName: String,
        params: Int16,
        kind: String,
        volume: SceneCylinderTriggerVolume
    ) {
        self.id = id
        self.roomID = roomID
        self.actorName = actorName
        self.params = params
        self.kind = kind
        self.volume = volume
    }
}

public struct SceneEventRegionTrigger: Codable, Sendable, Equatable {
    public var id: Int
    public var roomID: Int
    public var actorName: String
    public var params: Int16
    public var kind: String
    public var volume: SceneCylinderTriggerVolume

    public init(
        id: Int,
        roomID: Int,
        actorName: String,
        params: Int16,
        kind: String,
        volume: SceneCylinderTriggerVolume
    ) {
        self.id = id
        self.roomID = roomID
        self.actorName = actorName
        self.params = params
        self.kind = kind
        self.volume = volume
    }
}

public struct SceneSoundSettings: Codable, Sendable, Equatable {
    public var specID: Int
    public var natureAmbienceID: Int
    public var sequenceID: Int

    public init(specID: Int, natureAmbienceID: Int, sequenceID: Int) {
        self.specID = specID
        self.natureAmbienceID = natureAmbienceID
        self.sequenceID = sequenceID
    }
}

public struct SceneSpecialFiles: Codable, Sendable, Equatable {
    public var naviHintName: String?
    public var keepObjectName: String?

    public init(
        naviHintName: String? = nil,
        keepObjectName: String? = nil
    ) {
        self.naviHintName = naviHintName
        self.keepObjectName = keepObjectName
    }
}

public struct SceneHeaderDefinition: Codable, Sendable, Equatable {
    public var sceneName: String
    public var sceneObjectIDs: [Int]
    public var spawns: [SceneSpawnPoint]
    public var entrances: [SceneEntranceDefinition]
    public var rooms: [SceneRoomDefinition]
    public var transitionTriggers: [SceneTransitionTrigger]
    public var cutsceneTriggers: [SceneCutsceneTrigger]
    public var eventRegionTriggers: [SceneEventRegionTrigger]
    public var soundSettings: SceneSoundSettings?
    public var specialFiles: SceneSpecialFiles?
    public var cutsceneIDs: [Int]

    private enum CodingKeys: String, CodingKey {
        case sceneName
        case sceneObjectIDs
        case spawns
        case entrances
        case rooms
        case transitionTriggers
        case cutsceneTriggers
        case eventRegionTriggers
        case soundSettings
        case specialFiles
        case cutsceneIDs
    }

    public init(
        sceneName: String,
        sceneObjectIDs: [Int] = [],
        spawns: [SceneSpawnPoint] = [],
        entrances: [SceneEntranceDefinition] = [],
        rooms: [SceneRoomDefinition] = [],
        transitionTriggers: [SceneTransitionTrigger] = [],
        cutsceneTriggers: [SceneCutsceneTrigger] = [],
        eventRegionTriggers: [SceneEventRegionTrigger] = [],
        soundSettings: SceneSoundSettings? = nil,
        specialFiles: SceneSpecialFiles? = nil,
        cutsceneIDs: [Int] = []
    ) {
        self.sceneName = sceneName
        self.sceneObjectIDs = sceneObjectIDs
        self.spawns = spawns
        self.entrances = entrances
        self.rooms = rooms
        self.transitionTriggers = transitionTriggers
        self.cutsceneTriggers = cutsceneTriggers
        self.eventRegionTriggers = eventRegionTriggers
        self.soundSettings = soundSettings
        self.specialFiles = specialFiles
        self.cutsceneIDs = cutsceneIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sceneName: try container.decode(String.self, forKey: .sceneName),
            sceneObjectIDs: try container.decodeIfPresent([Int].self, forKey: .sceneObjectIDs) ?? [],
            spawns: try container.decodeIfPresent([SceneSpawnPoint].self, forKey: .spawns) ?? [],
            entrances: try container.decodeIfPresent([SceneEntranceDefinition].self, forKey: .entrances) ?? [],
            rooms: try container.decodeIfPresent([SceneRoomDefinition].self, forKey: .rooms) ?? [],
            transitionTriggers: try container.decodeIfPresent([SceneTransitionTrigger].self, forKey: .transitionTriggers) ?? [],
            cutsceneTriggers: try container.decodeIfPresent([SceneCutsceneTrigger].self, forKey: .cutsceneTriggers) ?? [],
            eventRegionTriggers: try container.decodeIfPresent([SceneEventRegionTrigger].self, forKey: .eventRegionTriggers) ?? [],
            soundSettings: try container.decodeIfPresent(SceneSoundSettings.self, forKey: .soundSettings),
            specialFiles: try container.decodeIfPresent(SceneSpecialFiles.self, forKey: .specialFiles),
            cutsceneIDs: try container.decodeIfPresent([Int].self, forKey: .cutsceneIDs) ?? []
        )
    }
}

public struct EntranceTableEntry: Codable, Sendable, Equatable {
    public var index: Int
    public var name: String
    public var sceneID: Int
    public var spawnIndex: Int
    public var continueBGM: Bool
    public var displayTitleCard: Bool
    public var transitionIn: SceneTransitionEffect
    public var transitionOut: SceneTransitionEffect

    public init(
        index: Int,
        name: String,
        sceneID: Int,
        spawnIndex: Int,
        continueBGM: Bool,
        displayTitleCard: Bool,
        transitionIn: SceneTransitionEffect,
        transitionOut: SceneTransitionEffect
    ) {
        self.index = index
        self.name = name
        self.sceneID = sceneID
        self.spawnIndex = spawnIndex
        self.continueBGM = continueBGM
        self.displayTitleCard = displayTitleCard
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
    }
}
