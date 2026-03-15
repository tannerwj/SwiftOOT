public struct SceneManifest: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var title: String?
    public var drawConfig: Int?
    public var rooms: [RoomManifest]
    public var collisionPath: String?
    public var actorsPath: String?
    public var spawnsPath: String?
    public var environmentPath: String?
    public var pathsPath: String?
    public var exitsPath: String?
    public var textureDirectories: [String]

    public init(
        id: Int,
        name: String,
        title: String? = nil,
        drawConfig: Int? = nil,
        rooms: [RoomManifest],
        collisionPath: String? = nil,
        actorsPath: String? = nil,
        spawnsPath: String? = nil,
        environmentPath: String? = nil,
        pathsPath: String? = nil,
        exitsPath: String? = nil,
        textureDirectories: [String] = []
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.drawConfig = drawConfig
        self.rooms = rooms
        self.collisionPath = collisionPath
        self.actorsPath = actorsPath
        self.spawnsPath = spawnsPath
        self.environmentPath = environmentPath
        self.pathsPath = pathsPath
        self.exitsPath = exitsPath
        self.textureDirectories = textureDirectories
    }
}

public struct RoomManifest: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var directory: String
    public var textureDirectories: [String]

    public init(
        id: Int,
        name: String,
        directory: String,
        textureDirectories: [String] = []
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.textureDirectories = textureDirectories
    }
}

public struct ActorProfile: Codable, Sendable, Equatable {
    public var id: Int
    public var category: UInt16
    public var flags: UInt32
    public var objectID: Int

    public init(id: Int, category: UInt16, flags: UInt32, objectID: Int) {
        self.id = id
        self.category = category
        self.flags = flags
        self.objectID = objectID
    }
}

public struct SceneTableEntry: Codable, Sendable, Equatable {
    public var index: Int
    public var segmentName: String
    public var enumName: String
    public var title: String?
    public var drawConfig: Int?

    public init(
        index: Int,
        segmentName: String,
        enumName: String,
        title: String? = nil,
        drawConfig: Int? = nil
    ) {
        self.index = index
        self.segmentName = segmentName
        self.enumName = enumName
        self.title = title
        self.drawConfig = drawConfig
    }
}

public struct ActorTableEntry: Codable, Sendable, Equatable {
    public var id: Int
    public var enumName: String
    public var profile: ActorProfile
    public var overlayName: String?

    public init(id: Int, enumName: String, profile: ActorProfile, overlayName: String? = nil) {
        self.id = id
        self.enumName = enumName
        self.profile = profile
        self.overlayName = overlayName
    }
}

public struct ObjectTableEntry: Codable, Sendable, Equatable {
    public var id: Int
    public var enumName: String
    public var assetPath: String

    public init(id: Int, enumName: String, assetPath: String) {
        self.id = id
        self.enumName = enumName
        self.assetPath = assetPath
    }
}
