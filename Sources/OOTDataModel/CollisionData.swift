public struct CollisionMesh: Codable, Sendable, Equatable {
    public var minimumBounds: Vector3s
    public var maximumBounds: Vector3s
    public var vertices: [Vector3s]
    public var polygons: [CollisionPoly]
    public var surfaceTypes: [CollisionSurfaceType]
    public var bgCameras: [CollisionBgCamera]
    public var waterBoxes: [CollisionWaterBox]

    public init(
        minimumBounds: Vector3s? = nil,
        maximumBounds: Vector3s? = nil,
        vertices: [Vector3s],
        polygons: [CollisionPoly],
        surfaceTypes: [CollisionSurfaceType] = [],
        bgCameras: [CollisionBgCamera] = [],
        waterBoxes: [CollisionWaterBox] = []
    ) {
        let computedBounds = Self.bounds(for: vertices)
        self.minimumBounds = minimumBounds ?? computedBounds.minimum
        self.maximumBounds = maximumBounds ?? computedBounds.maximum
        self.vertices = vertices
        self.polygons = polygons
        self.surfaceTypes = surfaceTypes
        self.bgCameras = bgCameras
        self.waterBoxes = waterBoxes
    }

    public func surfaceType(for polygon: CollisionPoly) -> CollisionSurfaceType? {
        guard Int(polygon.surfaceType) < surfaceTypes.count else {
            return nil
        }

        return surfaceTypes[Int(polygon.surfaceType)]
    }
}

public struct CollisionPoly: Codable, Sendable, Equatable {
    public var surfaceType: UInt16
    public var vertexA: UInt16
    public var vertexB: UInt16
    public var vertexC: UInt16
    public var normal: Vector3s
    public var distance: Int16

    public init(
        surfaceType: UInt16,
        vertexA: UInt16,
        vertexB: UInt16,
        vertexC: UInt16,
        normal: Vector3s,
        distance: Int16
    ) {
        self.surfaceType = surfaceType
        self.vertexA = vertexA
        self.vertexB = vertexB
        self.vertexC = vertexC
        self.normal = normal
        self.distance = distance
    }
}

public struct CollisionSurfaceType: Codable, Sendable, Equatable {
    public var low: UInt32
    public var high: UInt32

    public init(low: UInt32, high: UInt32) {
        self.low = low
        self.high = high
    }

    public var bgCamIndex: UInt32 { low & 0xFF }
    public var exitIndex: UInt32 { (low >> 8) & 0x1F }
    public var floorType: UInt32 { (low >> 13) & 0x1F }
    public var specialBehavior: UInt32 { (low >> 18) & 0x07 }
    public var wallType: UInt32 { (low >> 21) & 0x1F }
    public var floorProperty: UInt32 { (low >> 26) & 0x0F }
    public var isSoft: Bool { ((low >> 30) & 1) != 0 }
    public var isHorseBlocked: Bool { ((low >> 31) & 1) != 0 }

    public var material: UInt32 { high & 0x0F }
    public var floorEffect: UInt32 { (high >> 4) & 0x03 }
    public var lightSetting: UInt32 { (high >> 6) & 0x1F }
    public var echo: UInt32 { (high >> 11) & 0x3F }
    public var canHookshot: Bool { ((high >> 17) & 1) != 0 }
    public var conveyorSpeed: UInt32 { (high >> 18) & 0x07 }
    public var conveyorDirection: UInt32 { (high >> 21) & 0x3F }
    public var hasSpecialConveyorBehavior: Bool { ((high >> 27) & 1) != 0 }
}

public struct CollisionBgCameraData: Codable, Sendable, Equatable {
    public var position: Vector3s
    public var rotation: Vector3s
    public var fov: Int16
    public var parameter: Int16
    public var unknown: Int16

    public init(
        position: Vector3s,
        rotation: Vector3s,
        fov: Int16,
        parameter: Int16,
        unknown: Int16
    ) {
        self.position = position
        self.rotation = rotation
        self.fov = fov
        self.parameter = parameter
        self.unknown = unknown
    }
}

public struct CollisionBgCamera: Codable, Sendable, Equatable {
    public var setting: UInt16
    public var count: Int16
    public var cameraData: CollisionBgCameraData?
    public var crawlspacePoints: [Vector3s]

    public init(
        setting: UInt16,
        count: Int16,
        cameraData: CollisionBgCameraData? = nil,
        crawlspacePoints: [Vector3s] = []
    ) {
        self.setting = setting
        self.count = count
        self.cameraData = cameraData
        self.crawlspacePoints = crawlspacePoints
    }
}

public struct CollisionWaterBox: Codable, Sendable, Equatable {
    public var xMin: Int16
    public var ySurface: Int16
    public var zMin: Int16
    public var xLength: UInt16
    public var zLength: UInt16
    public var properties: UInt32

    public init(
        xMin: Int16,
        ySurface: Int16,
        zMin: Int16,
        xLength: UInt16,
        zLength: UInt16,
        properties: UInt32
    ) {
        self.xMin = xMin
        self.ySurface = ySurface
        self.zMin = zMin
        self.xLength = xLength
        self.zLength = zLength
        self.properties = properties
    }

    public var bgCamIndex: UInt32 { properties & 0xFF }
    public var lightIndex: UInt32 { (properties >> 8) & 0x1F }
    public var roomIndex: UInt32 { (properties >> 13) & 0x3F }
    public var hasFlag19: Bool { ((properties >> 19) & 1) != 0 }
}

private extension CollisionMesh {
    static func bounds(for vertices: [Vector3s]) -> (minimum: Vector3s, maximum: Vector3s) {
        guard let first = vertices.first else {
            let zero = Vector3s(x: 0, y: 0, z: 0)
            return (zero, zero)
        }

        var minimum = first
        var maximum = first

        for vertex in vertices.dropFirst() {
            minimum.x = min(minimum.x, vertex.x)
            minimum.y = min(minimum.y, vertex.y)
            minimum.z = min(minimum.z, vertex.z)
            maximum.x = max(maximum.x, vertex.x)
            maximum.y = max(maximum.y, vertex.y)
            maximum.z = max(maximum.z, vertex.z)
        }

        return (minimum, maximum)
    }
}
