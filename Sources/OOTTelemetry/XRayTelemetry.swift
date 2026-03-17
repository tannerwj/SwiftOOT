import OOTDataModel
import simd

public struct XRayVector3: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ vector: Vector3s) {
        self.init(
            x: Float(vector.x),
            y: Float(vector.y),
            z: Float(vector.z)
        )
    }

    public init(_ vector: SIMD3<Float>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }

    public var simd: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

public enum XRayCollisionKind: String, Codable, Sendable, Equatable {
    case walkable
    case wall
    case void
    case climbable
    case other
}

public struct XRayCollisionPolygon: Codable, Sendable, Equatable {
    public var kind: XRayCollisionKind
    public var surfaceTypeIndex: Int
    public var vertices: [XRayVector3]

    public init(
        kind: XRayCollisionKind,
        surfaceTypeIndex: Int,
        vertices: [XRayVector3]
    ) {
        self.kind = kind
        self.surfaceTypeIndex = surfaceTypeIndex
        self.vertices = vertices
    }
}

public struct XRayCylinder: Codable, Sendable, Equatable {
    public var center: XRayVector3
    public var radius: Float
    public var height: Float

    public init(center: XRayVector3, radius: Float, height: Float) {
        self.center = center
        self.radius = max(0, radius)
        self.height = max(0, height)
    }
}

public struct XRayTriangle: Codable, Sendable, Equatable {
    public var a: XRayVector3
    public var b: XRayVector3
    public var c: XRayVector3

    public init(a: XRayVector3, b: XRayVector3, c: XRayVector3) {
        self.a = a
        self.b = b
        self.c = c
    }
}

public enum XRayColliderRole: String, Codable, Sendable, Equatable {
    case actorBounds
    case attack
    case body
}

public enum XRayColliderShapeKind: String, Codable, Sendable, Equatable {
    case cylinder
    case triangles
}

public struct XRayColliderSnapshot: Codable, Sendable, Equatable {
    public var role: XRayColliderRole
    public var kind: XRayColliderShapeKind
    public var cylinder: XRayCylinder?
    public var triangles: [XRayTriangle]

    public init(
        role: XRayColliderRole,
        kind: XRayColliderShapeKind,
        cylinder: XRayCylinder? = nil,
        triangles: [XRayTriangle] = []
    ) {
        self.role = role
        self.kind = kind
        self.cylinder = cylinder
        self.triangles = triangles
    }
}

public struct XRayActorSnapshot: Codable, Sendable, Equatable {
    public var profileID: Int
    public var actorType: String
    public var category: String
    public var roomID: Int?
    public var position: XRayVector3
    public var rotation: XRayVector3
    public var spawnPosition: XRayVector3?
    public var boundsCollider: XRayColliderSnapshot?
    public var bodyCollider: XRayColliderSnapshot?
    public var attackColliders: [XRayColliderSnapshot]

    public init(
        profileID: Int,
        actorType: String,
        category: String,
        roomID: Int?,
        position: XRayVector3,
        rotation: XRayVector3,
        spawnPosition: XRayVector3? = nil,
        boundsCollider: XRayColliderSnapshot? = nil,
        bodyCollider: XRayColliderSnapshot? = nil,
        attackColliders: [XRayColliderSnapshot] = []
    ) {
        self.profileID = profileID
        self.actorType = actorType
        self.category = category
        self.roomID = roomID
        self.position = position
        self.rotation = rotation
        self.spawnPosition = spawnPosition
        self.boundsCollider = boundsCollider
        self.bodyCollider = bodyCollider
        self.attackColliders = attackColliders
    }
}

public struct XRayScenePathSnapshot: Codable, Sendable, Equatable {
    public var index: Int
    public var pointsName: String
    public var points: [XRayVector3]

    public init(index: Int, pointsName: String, points: [XRayVector3]) {
        self.index = index
        self.pointsName = pointsName
        self.points = points
    }
}

public struct XRaySceneTriggerSnapshot: Codable, Sendable, Equatable {
    public var id: Int
    public var kind: String
    public var minimum: XRayVector3
    public var maximum: XRayVector3

    public init(
        id: Int,
        kind: String,
        minimum: XRayVector3,
        maximum: XRayVector3
    ) {
        self.id = id
        self.kind = kind
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct XRaySceneSpawnSnapshot: Codable, Sendable, Equatable {
    public var index: Int
    public var roomID: Int?
    public var position: XRayVector3
    public var rotation: XRayVector3

    public init(
        index: Int,
        roomID: Int?,
        position: XRayVector3,
        rotation: XRayVector3
    ) {
        self.index = index
        self.roomID = roomID
        self.position = position
        self.rotation = rotation
    }
}

public struct XRaySceneActorSpawnSnapshot: Codable, Sendable, Equatable {
    public var actorID: Int
    public var actorName: String
    public var roomName: String
    public var position: XRayVector3
    public var rotation: XRayVector3

    public init(
        actorID: Int,
        actorName: String,
        roomName: String,
        position: XRayVector3,
        rotation: XRayVector3
    ) {
        self.actorID = actorID
        self.actorName = actorName
        self.roomName = roomName
        self.position = position
        self.rotation = rotation
    }
}

public struct XRaySceneWaterBoxSnapshot: Codable, Sendable, Equatable {
    public var minimum: XRayVector3
    public var maximum: XRayVector3
    public var ySurface: Float

    public init(
        minimum: XRayVector3,
        maximum: XRayVector3,
        ySurface: Float
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.ySurface = ySurface
    }
}

public struct XRaySceneBgCameraSnapshot: Codable, Sendable, Equatable {
    public var index: Int
    public var position: XRayVector3
    public var forward: XRayVector3
    public var fieldOfViewRadians: Float
    public var crawlspacePoints: [XRayVector3]

    public init(
        index: Int,
        position: XRayVector3,
        forward: XRayVector3,
        fieldOfViewRadians: Float,
        crawlspacePoints: [XRayVector3]
    ) {
        self.index = index
        self.position = position
        self.forward = forward
        self.fieldOfViewRadians = fieldOfViewRadians
        self.crawlspacePoints = crawlspacePoints
    }
}

public struct XRaySceneSnapshot: Codable, Sendable, Equatable {
    public var collisionPolygons: [XRayCollisionPolygon]
    public var bgCameras: [XRaySceneBgCameraSnapshot]
    public var waterBoxes: [XRaySceneWaterBoxSnapshot]
    public var paths: [XRayScenePathSnapshot]
    public var triggerVolumes: [XRaySceneTriggerSnapshot]
    public var spawnPoints: [XRaySceneSpawnSnapshot]
    public var actorSpawns: [XRaySceneActorSpawnSnapshot]

    public init(
        collisionPolygons: [XRayCollisionPolygon] = [],
        bgCameras: [XRaySceneBgCameraSnapshot] = [],
        waterBoxes: [XRaySceneWaterBoxSnapshot] = [],
        paths: [XRayScenePathSnapshot] = [],
        triggerVolumes: [XRaySceneTriggerSnapshot] = [],
        spawnPoints: [XRaySceneSpawnSnapshot] = [],
        actorSpawns: [XRaySceneActorSpawnSnapshot] = []
    ) {
        self.collisionPolygons = collisionPolygons
        self.bgCameras = bgCameras
        self.waterBoxes = waterBoxes
        self.paths = paths
        self.triggerVolumes = triggerVolumes
        self.spawnPoints = spawnPoints
        self.actorSpawns = actorSpawns
    }
}

public struct XRayTelemetrySnapshot: Codable, Sendable, Equatable {
    public var scene: XRaySceneSnapshot?
    public var activeActors: [XRayActorSnapshot]

    public init(
        scene: XRaySceneSnapshot? = nil,
        activeActors: [XRayActorSnapshot] = []
    ) {
        self.scene = scene
        self.activeActors = activeActors
    }
}
