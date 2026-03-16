public struct RGB8: Codable, Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct Vector3b: Codable, Sendable, Equatable {
    public var x: Int8
    public var y: Int8
    public var z: Int8

    public init(x: Int8, y: Int8, z: Int8) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SceneActorSpawn: Codable, Sendable, Equatable {
    public var actorID: Int
    public var actorName: String
    public var position: Vector3s
    public var rotation: Vector3s
    public var params: Int16

    public init(
        actorID: Int,
        actorName: String,
        position: Vector3s,
        rotation: Vector3s,
        params: Int16
    ) {
        self.actorID = actorID
        self.actorName = actorName
        self.position = position
        self.rotation = rotation
        self.params = params
    }
}

public struct RoomActorSpawns: Codable, Sendable, Equatable {
    public var roomName: String
    public var actors: [SceneActorSpawn]

    public init(roomName: String, actors: [SceneActorSpawn]) {
        self.roomName = roomName
        self.actors = actors
    }
}

public struct SceneActorsFile: Codable, Sendable, Equatable {
    public var sceneName: String
    public var rooms: [RoomActorSpawns]

    public init(sceneName: String, rooms: [RoomActorSpawns]) {
        self.sceneName = sceneName
        self.rooms = rooms
    }
}

public struct SceneSpawnPoint: Codable, Sendable, Equatable {
    public var index: Int
    public var roomID: Int?
    public var position: Vector3s
    public var rotation: Vector3s
    public var params: Int16

    public init(
        index: Int,
        roomID: Int? = nil,
        position: Vector3s,
        rotation: Vector3s,
        params: Int16 = 0
    ) {
        self.index = index
        self.roomID = roomID
        self.position = position
        self.rotation = rotation
        self.params = params
    }
}

public struct SceneSpawnsFile: Codable, Sendable, Equatable {
    public var sceneName: String
    public var spawns: [SceneSpawnPoint]

    public init(sceneName: String, spawns: [SceneSpawnPoint]) {
        self.sceneName = sceneName
        self.spawns = spawns
    }
}

public struct SceneTimeSettings: Codable, Sendable, Equatable {
    public var hour: Int
    public var minute: Int
    public var timeSpeed: Int

    public init(hour: Int, minute: Int, timeSpeed: Int) {
        self.hour = hour
        self.minute = minute
        self.timeSpeed = timeSpeed
    }
}

public struct SceneSkyboxSettings: Codable, Sendable, Equatable {
    public var skyboxID: Int
    public var skyboxConfig: Int
    public var environmentLightingMode: String
    public var skyboxDisabled: Bool
    public var sunMoonDisabled: Bool

    public init(
        skyboxID: Int,
        skyboxConfig: Int,
        environmentLightingMode: String,
        skyboxDisabled: Bool,
        sunMoonDisabled: Bool
    ) {
        self.skyboxID = skyboxID
        self.skyboxConfig = skyboxConfig
        self.environmentLightingMode = environmentLightingMode
        self.skyboxDisabled = skyboxDisabled
        self.sunMoonDisabled = sunMoonDisabled
    }
}

public struct SceneLightSetting: Codable, Sendable, Equatable {
    public var ambientColor: RGB8
    public var light1Direction: Vector3b
    public var light1Color: RGB8
    public var light2Direction: Vector3b
    public var light2Color: RGB8
    public var fogColor: RGB8
    public var blendRate: UInt8
    public var fogNear: Int
    public var zFar: Int16

    public init(
        ambientColor: RGB8,
        light1Direction: Vector3b,
        light1Color: RGB8,
        light2Direction: Vector3b,
        light2Color: RGB8,
        fogColor: RGB8,
        blendRate: UInt8,
        fogNear: Int,
        zFar: Int16
    ) {
        self.ambientColor = ambientColor
        self.light1Direction = light1Direction
        self.light1Color = light1Color
        self.light2Direction = light2Direction
        self.light2Color = light2Color
        self.fogColor = fogColor
        self.blendRate = blendRate
        self.fogNear = fogNear
        self.zFar = zFar
    }
}

public struct SceneEnvironmentFile: Codable, Sendable, Equatable {
    public var sceneName: String
    public var time: SceneTimeSettings
    public var skybox: SceneSkyboxSettings
    public var lightSettings: [SceneLightSetting]

    public init(
        sceneName: String,
        time: SceneTimeSettings,
        skybox: SceneSkyboxSettings,
        lightSettings: [SceneLightSetting]
    ) {
        self.sceneName = sceneName
        self.time = time
        self.skybox = skybox
        self.lightSettings = lightSettings
    }
}

public struct ScenePathDefinition: Codable, Sendable, Equatable {
    public var index: Int
    public var pointsName: String
    public var points: [Vector3s]

    public init(index: Int, pointsName: String, points: [Vector3s]) {
        self.index = index
        self.pointsName = pointsName
        self.points = points
    }
}

public struct ScenePathsFile: Codable, Sendable, Equatable {
    public var sceneName: String
    public var paths: [ScenePathDefinition]

    public init(sceneName: String, paths: [ScenePathDefinition]) {
        self.sceneName = sceneName
        self.paths = paths
    }
}

public struct SceneExitDefinition: Codable, Sendable, Equatable {
    public var index: Int
    public var entranceIndex: Int
    public var entranceName: String

    public init(index: Int, entranceIndex: Int, entranceName: String) {
        self.index = index
        self.entranceIndex = entranceIndex
        self.entranceName = entranceName
    }
}

public struct SceneExitsFile: Codable, Sendable, Equatable {
    public var sceneName: String
    public var exits: [SceneExitDefinition]

    public init(sceneName: String, exits: [SceneExitDefinition]) {
        self.sceneName = sceneName
        self.exits = exits
    }
}
