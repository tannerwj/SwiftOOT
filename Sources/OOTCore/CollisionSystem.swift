import OOTContent
import OOTDataModel
import OSLog
import simd

public protocol DynamicCollisionProviding: Sendable {
    func collisionMeshes() -> [CollisionMesh]
}

public enum CollisionSource: String, Sendable, Equatable {
    case staticWorld
    case dynamic
}

public struct CollisionPolygonReference: Sendable, Equatable {
    public var source: CollisionSource
    public var polygonIndex: Int
    public var polygon: CollisionPoly
    public var surfaceType: CollisionSurfaceType?

    public init(
        source: CollisionSource,
        polygonIndex: Int,
        polygon: CollisionPoly,
        surfaceType: CollisionSurfaceType?
    ) {
        self.source = source
        self.polygonIndex = polygonIndex
        self.polygon = polygon
        self.surfaceType = surfaceType
    }
}

public struct CollisionFloorHit: Sendable, Equatable {
    public var floorY: Float
    public var polygon: CollisionPolygonReference

    public init(floorY: Float, polygon: CollisionPolygonReference) {
        self.floorY = floorY
        self.polygon = polygon
    }
}

public struct CollisionCeilingHit: Sendable, Equatable {
    public var ceilingY: Float
    public var polygon: CollisionPolygonReference

    public init(ceilingY: Float, polygon: CollisionPolygonReference) {
        self.ceilingY = ceilingY
        self.polygon = polygon
    }
}

public struct CollisionWallHit: Sendable, Equatable {
    public var displacement: SIMD3<Float>
    public var polygon: CollisionPolygonReference

    public init(displacement: SIMD3<Float>, polygon: CollisionPolygonReference) {
        self.displacement = displacement
        self.polygon = polygon
    }
}

public struct CollisionSystem: Sendable {
    private let staticMeshes: [IndexedCollisionMesh]
    private let dynamicProviders: [any DynamicCollisionProviding]

    public init(
        staticMeshes: [CollisionMesh] = [],
        dynamicProviders: [any DynamicCollisionProviding] = []
    ) {
        self.staticMeshes = staticMeshes.map { IndexedCollisionMesh(mesh: $0, source: .staticWorld) }
        self.dynamicProviders = dynamicProviders
    }

    public init(
        scene: LoadedScene,
        dynamicProviders: [any DynamicCollisionProviding] = []
    ) {
        self.init(
            staticMeshes: scene.collision.map { [$0] } ?? [],
            dynamicProviders: dynamicProviders
        )
    }

    public func findFloor(
        at position: SIMD3<Float>,
        diagnosticContext: String? = nil
    ) -> CollisionFloorHit? {
        var bestHit: CollisionFloorHit?

        for mesh in indexedMeshes() {
            for triangle in mesh.candidates(at: position) where triangle.isFloorCandidate {
                guard let floorY = triangle.verticalIntersectionY(x: position.x, z: position.z) else {
                    continue
                }
                guard floorY <= position.y + Self.planeEpsilon else {
                    continue
                }
                guard bestHit == nil || floorY > bestHit!.floorY else {
                    continue
                }

                bestHit = CollisionFloorHit(
                    floorY: floorY,
                    polygon: triangle.reference(source: mesh.source)
                )
            }
        }

        if bestHit == nil, let diagnosticContext {
            os_log(
                .error,
                log: collisionSystemLog,
                "%{public}@",
                "No floor collision found for \(diagnosticContext) at position (\(position.x), \(position.y), \(position.z))."
            )
        }

        return bestHit
    }

    public func checkCeiling(at position: SIMD3<Float>) -> CollisionCeilingHit? {
        var bestHit: CollisionCeilingHit?

        for mesh in indexedMeshes() {
            for triangle in mesh.candidates(at: position) where triangle.isCeilingCandidate {
                guard let ceilingY = triangle.verticalIntersectionY(x: position.x, z: position.z) else {
                    continue
                }
                guard ceilingY >= position.y - Self.planeEpsilon else {
                    continue
                }
                guard bestHit == nil || ceilingY < bestHit!.ceilingY else {
                    continue
                }

                bestHit = CollisionCeilingHit(
                    ceilingY: ceilingY,
                    polygon: triangle.reference(source: mesh.source)
                )
            }
        }

        return bestHit
    }

    public func checkWall(
        at position: SIMD3<Float>,
        radius: Float,
        displacement: SIMD3<Float>
    ) -> CollisionWallHit? {
        guard radius > 0 else {
            return nil
        }

        let target = position + displacement
        let sweepBounds = AABB(
            minimum: simd_min(position, target) - SIMD3<Float>(repeating: radius),
            maximum: simd_max(position, target) + SIMD3<Float>(repeating: radius)
        )

        var corrected = target
        var blockingTriangle: (triangle: IndexedTriangle, source: CollisionSource)?

        for _ in 0..<4 {
            var adjusted = false

            for mesh in indexedMeshes() {
                for triangle in mesh.candidates(overlapping: sweepBounds) where triangle.isWallCandidate {
                    let closestPoint = triangle.closestPoint(to: corrected)
                    let separation = corrected - closestPoint
                    let distance = simd_length(separation)

                    guard distance < radius - Self.planeEpsilon else {
                        continue
                    }

                    let correctionDirection = triangle.wallCorrectionDirection(
                        from: position,
                        to: corrected,
                        fallbackSeparation: separation,
                        requestedDisplacement: displacement
                    )
                    corrected += correctionDirection * (radius - distance)
                    blockingTriangle = (triangle, mesh.source)
                    adjusted = true
                }
            }

            if adjusted == false {
                break
            }
        }

        guard let blockingTriangle else {
            return nil
        }

        let correction = corrected - target
        guard simd_length_squared(correction) > Self.planeEpsilon else {
            return nil
        }

        return CollisionWallHit(
            displacement: correction,
            polygon: blockingTriangle.triangle.reference(source: blockingTriangle.source)
        )
    }

    public func checkLineOcclusion(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let bounds = AABB(
            minimum: simd_min(start, end),
            maximum: simd_max(start, end)
        )

        for mesh in indexedMeshes() {
            for triangle in mesh.candidates(overlapping: bounds) {
                if triangle.intersectsSegment(from: start, to: end) {
                    return true
                }
            }
        }

        return false
    }
}

private extension CollisionSystem {
    static let planeEpsilon: Float = 0.001
    static let wallNormalYThreshold: Float = 0.8

    func indexedMeshes() -> [IndexedCollisionMesh] {
        var meshes = staticMeshes

        for provider in dynamicProviders {
            meshes.append(
                contentsOf: provider.collisionMeshes().map {
                    IndexedCollisionMesh(mesh: $0, source: .dynamic)
                }
            )
        }

        return meshes
    }
}

private struct IndexedCollisionMesh: Sendable {
    let source: CollisionSource
    let triangles: [IndexedTriangle]
    let grid: BucketGrid

    init(mesh: CollisionMesh, source: CollisionSource) {
        self.source = source
        self.triangles = mesh.polygons.enumerated().compactMap { index, polygon in
            IndexedTriangle(mesh: mesh, polygon: polygon, polygonIndex: index)
        }
        self.grid = BucketGrid(bounds: mesh.bounds, triangles: triangles)
    }

    func candidates(at point: SIMD3<Float>) -> [IndexedTriangle] {
        grid.candidates(at: point, from: triangles)
    }

    func candidates(overlapping bounds: AABB) -> [IndexedTriangle] {
        grid.candidates(overlapping: bounds, from: triangles)
    }
}

private struct IndexedTriangle: Sendable {
    let polygon: CollisionPoly
    let polygonIndex: Int
    let surfaceType: CollisionSurfaceType?
    let a: SIMD3<Float>
    let b: SIMD3<Float>
    let c: SIMD3<Float>
    let normal: SIMD3<Float>
    let bounds: AABB

    init?(mesh: CollisionMesh, polygon: CollisionPoly, polygonIndex: Int) {
        guard
            Int(polygon.vertexA) < mesh.vertices.count,
            Int(polygon.vertexB) < mesh.vertices.count,
            Int(polygon.vertexC) < mesh.vertices.count
        else {
            return nil
        }

        let a = SIMD3<Float>(mesh.vertices[Int(polygon.vertexA)])
        let b = SIMD3<Float>(mesh.vertices[Int(polygon.vertexB)])
        let c = SIMD3<Float>(mesh.vertices[Int(polygon.vertexC)])
        let geometricNormal = simd_cross(b - a, c - a)
        let geometricLength = simd_length(geometricNormal)
        let fallbackNormal = SIMD3<Float>(polygon.normal)
        let fallbackLength = simd_length(fallbackNormal)

        let resolvedNormal: SIMD3<Float>
        if fallbackLength > CollisionSystem.planeEpsilon {
            resolvedNormal = fallbackNormal / fallbackLength
        } else if geometricLength > CollisionSystem.planeEpsilon {
            resolvedNormal = geometricNormal / geometricLength
        } else {
            return nil
        }

        self.polygon = polygon
        self.polygonIndex = polygonIndex
        self.surfaceType = mesh.surfaceType(for: polygon)
        self.a = a
        self.b = b
        self.c = c
        self.normal = resolvedNormal
        self.bounds = AABB(containing: [a, b, c])
    }

    var isFloorCandidate: Bool {
        normal.y > CollisionSystem.planeEpsilon
    }

    var isCeilingCandidate: Bool {
        normal.y < -CollisionSystem.planeEpsilon
    }

    var isWallCandidate: Bool {
        abs(normal.y) < CollisionSystem.wallNormalYThreshold
    }

    func reference(source: CollisionSource) -> CollisionPolygonReference {
        CollisionPolygonReference(
            source: source,
            polygonIndex: polygonIndex,
            polygon: polygon,
            surfaceType: surfaceType
        )
    }

    func verticalIntersectionY(x: Float, z: Float) -> Float? {
        guard abs(normal.y) > CollisionSystem.planeEpsilon else {
            return nil
        }

        let y = a.y - ((normal.x * (x - a.x)) + (normal.z * (z - a.z))) / normal.y
        let point = SIMD3<Float>(x, y, z)
        return contains(point) ? y : nil
    }

    func contains(_ point: SIMD3<Float>) -> Bool {
        let edge0 = simd_dot(simd_cross(b - a, point - a), normal)
        let edge1 = simd_dot(simd_cross(c - b, point - b), normal)
        let edge2 = simd_dot(simd_cross(a - c, point - c), normal)

        let positive = edge0 >= -CollisionSystem.planeEpsilon &&
            edge1 >= -CollisionSystem.planeEpsilon &&
            edge2 >= -CollisionSystem.planeEpsilon
        let negative = edge0 <= CollisionSystem.planeEpsilon &&
            edge1 <= CollisionSystem.planeEpsilon &&
            edge2 <= CollisionSystem.planeEpsilon

        return positive || negative
    }

    func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a
        let ac = c - a
        let ap = point - a
        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0, d2 <= 0 {
            return a
        }

        let bp = point - b
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0, d4 <= d3 {
            return b
        }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            let v = d1 / (d1 - d3)
            return a + (ab * v)
        }

        let cp = point - c
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0, d5 <= d6 {
            return c
        }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            let w = d2 / (d2 - d6)
            return a + (ac * w)
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0, (d4 - d3) >= 0, (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return b + ((c - b) * w)
        }

        let denominator = 1 / (va + vb + vc)
        let v = vb * denominator
        let w = vc * denominator
        return a + (ab * v) + (ac * w)
    }

    func wallCorrectionDirection(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        fallbackSeparation: SIMD3<Float>,
        requestedDisplacement: SIMD3<Float>
    ) -> SIMD3<Float> {
        let horizontalNormal = horizontalized(normal)
        let planeDistanceAtStart = simd_dot(normal, start - a)
        if abs(planeDistanceAtStart) > CollisionSystem.planeEpsilon {
            return planeDistanceAtStart >= 0 ? horizontalNormal : -horizontalNormal
        }

        let planeDistanceAtEnd = simd_dot(normal, end - a)
        if abs(planeDistanceAtEnd) > CollisionSystem.planeEpsilon {
            return planeDistanceAtEnd >= 0 ? horizontalNormal : -horizontalNormal
        }

        let horizontalSeparation = horizontalized(fallbackSeparation)
        if simd_length_squared(horizontalSeparation) > CollisionSystem.planeEpsilon {
            return simd_normalize(horizontalSeparation)
        }

        let horizontalDisplacement = horizontalized(requestedDisplacement)
        if simd_length_squared(horizontalDisplacement) > CollisionSystem.planeEpsilon {
            return -simd_normalize(horizontalDisplacement)
        }

        return horizontalNormal
    }

    func intersectsSegment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let direction = end - start
        let edge1 = b - a
        let edge2 = c - a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)

        guard abs(determinant) > CollisionSystem.planeEpsilon else {
            return false
        }

        let inverseDeterminant = 1 / determinant
        let tVector = start - a
        let u = simd_dot(tVector, p) * inverseDeterminant
        guard u >= 0, u <= 1 else {
            return false
        }

        let q = simd_cross(tVector, edge1)
        let v = simd_dot(direction, q) * inverseDeterminant
        guard v >= 0, u + v <= 1 else {
            return false
        }

        let t = simd_dot(edge2, q) * inverseDeterminant
        return t >= CollisionSystem.planeEpsilon && t <= 1 - CollisionSystem.planeEpsilon
    }
}

private let collisionSystemLog = OSLog(subsystem: "com.swiftoot", category: "OOTCore")

private struct BucketGrid: Sendable {
    let bounds: AABB
    let cellsX: Int
    let cellsZ: Int
    let cellSizeX: Float
    let cellSizeZ: Float
    let cellMap: [Int: [Int]]

    init(bounds: AABB, triangles: [IndexedTriangle]) {
        self.bounds = bounds

        let gridDimension = max(1, min(16, Int(ceil(sqrt(Double(max(triangles.count, 1)))))))
        let extent = bounds.maximum - bounds.minimum
        let safeExtentX = max(extent.x, 1)
        let safeExtentZ = max(extent.z, 1)

        self.cellsX = gridDimension
        self.cellsZ = gridDimension
        self.cellSizeX = safeExtentX / Float(gridDimension)
        self.cellSizeZ = safeExtentZ / Float(gridDimension)

        func coordinate(_ value: Float, minimum: Float, cellSize: Float, limit: Int) -> Int {
            let rawIndex = Int(floor((value - minimum) / max(cellSize, 1)))
            return min(max(rawIndex, 0), limit - 1)
        }

        var cellMap: [Int: [Int]] = [:]
        for (index, triangle) in triangles.enumerated() {
            let lowerX = coordinate(
                triangle.bounds.minimum.x,
                minimum: bounds.minimum.x,
                cellSize: cellSizeX,
                limit: cellsX
            )
            let upperX = coordinate(
                triangle.bounds.maximum.x,
                minimum: bounds.minimum.x,
                cellSize: cellSizeX,
                limit: cellsX
            )
            let lowerZ = coordinate(
                triangle.bounds.minimum.z,
                minimum: bounds.minimum.z,
                cellSize: cellSizeZ,
                limit: cellsZ
            )
            let upperZ = coordinate(
                triangle.bounds.maximum.z,
                minimum: bounds.minimum.z,
                cellSize: cellSizeZ,
                limit: cellsZ
            )

            for z in lowerZ...upperZ {
                for x in lowerX...upperX {
                    cellMap[(z * cellsX) + x, default: []].append(index)
                }
            }
        }

        self.cellMap = cellMap
    }

    func candidates(at point: SIMD3<Float>, from triangles: [IndexedTriangle]) -> [IndexedTriangle] {
        let x = cellCoordinate(point.x, minimum: bounds.minimum.x, cellSize: cellSizeX, limit: cellsX)
        let z = cellCoordinate(point.z, minimum: bounds.minimum.z, cellSize: cellSizeZ, limit: cellsZ)
        let indices = cellMap[(z * cellsX) + x] ?? []
        return indices.map { triangles[$0] }
    }

    func candidates(overlapping queryBounds: AABB, from triangles: [IndexedTriangle]) -> [IndexedTriangle] {
        let range = cellRange(for: queryBounds)
        var indices: Set<Int> = []

        for z in range.zRange {
            for x in range.xRange {
                indices.formUnion(cellMap[(z * cellsX) + x] ?? [])
            }
        }

        return indices.map { triangles[$0] }
    }

    private func cellRange(for queryBounds: AABB) -> (xRange: ClosedRange<Int>, zRange: ClosedRange<Int>) {
        let lowerX = cellCoordinate(queryBounds.minimum.x, minimum: bounds.minimum.x, cellSize: cellSizeX, limit: cellsX)
        let upperX = cellCoordinate(queryBounds.maximum.x, minimum: bounds.minimum.x, cellSize: cellSizeX, limit: cellsX)
        let lowerZ = cellCoordinate(queryBounds.minimum.z, minimum: bounds.minimum.z, cellSize: cellSizeZ, limit: cellsZ)
        let upperZ = cellCoordinate(queryBounds.maximum.z, minimum: bounds.minimum.z, cellSize: cellSizeZ, limit: cellsZ)

        return (lowerX...upperX, lowerZ...upperZ)
    }

    private func cellCoordinate(
        _ value: Float,
        minimum: Float,
        cellSize: Float,
        limit: Int
    ) -> Int {
        let rawIndex = Int(floor((value - minimum) / max(cellSize, 1)))
        return min(max(rawIndex, 0), limit - 1)
    }
}

private struct AABB: Sendable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    init(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        self.minimum = minimum
        self.maximum = maximum
    }

    init(containing points: [SIMD3<Float>]) {
        let first = points[0]
        var minimum = first
        var maximum = first

        for point in points.dropFirst() {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        self.minimum = minimum
        self.maximum = maximum
    }
}

private extension CollisionMesh {
    var bounds: AABB {
        AABB(
            minimum: SIMD3<Float>(minimumBounds),
            maximum: SIMD3<Float>(maximumBounds)
        )
    }
}

private func horizontalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
    let horizontal = SIMD3<Float>(vector.x, 0, vector.z)
    if simd_length_squared(horizontal) > CollisionSystem.planeEpsilon {
        return simd_normalize(horizontal)
    }

    if simd_length_squared(vector) > CollisionSystem.planeEpsilon {
        return simd_normalize(vector)
    }

    return SIMD3<Float>(1, 0, 0)
}

private extension SIMD3 where Scalar == Float {
    init(_ vector: Vector3s) {
        self.init(Float(vector.x), Float(vector.y), Float(vector.z))
    }
}
