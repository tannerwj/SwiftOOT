public struct SceneManifest: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var title: String?
    public var rooms: [RoomManifest]
    public var objectIDs: [Int]
    public var collision: CollisionMesh?

    public init(
        id: Int,
        name: String,
        title: String? = nil,
        rooms: [RoomManifest],
        objectIDs: [Int] = [],
        collision: CollisionMesh? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.rooms = rooms
        self.objectIDs = objectIDs
        self.collision = collision
    }
}

public struct RoomManifest: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var objectIDs: [Int]
    public var actors: [ActorProfile]
    public var mesh: MeshData?

    public init(
        id: Int,
        name: String,
        objectIDs: [Int] = [],
        actors: [ActorProfile] = [],
        mesh: MeshData? = nil
    ) {
        self.id = id
        self.name = name
        self.objectIDs = objectIDs
        self.actors = actors
        self.mesh = mesh
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
    public var enumName: String
    public var title: String?
    public var drawConfig: Int?

    public init(index: Int, enumName: String, title: String? = nil, drawConfig: Int? = nil) {
        self.index = index
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
