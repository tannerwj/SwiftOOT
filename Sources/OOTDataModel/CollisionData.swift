public struct CollisionMesh: Codable, Sendable, Equatable {
    public var vertices: [Vector3s]
    public var polygons: [CollisionPoly]

    public init(vertices: [Vector3s], polygons: [CollisionPoly]) {
        self.vertices = vertices
        self.polygons = polygons
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
