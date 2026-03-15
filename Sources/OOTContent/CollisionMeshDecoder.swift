import Foundation
import OOTDataModel

enum CollisionMeshDecoder {
    enum DecodingError: Error, LocalizedError, Equatable {
        case invalidBinarySize(String, Int, Int)
        case invalidVertexReference(String, String, Int, Int)
        case invalidSurfaceTypeReference(String, Int, Int)

        var errorDescription: String? {
            switch self {
            case .invalidBinarySize(let path, let actualSize, let consumedBytes):
                "Collision binary '\(path)' has invalid size \(actualSize) bytes after consuming \(consumedBytes) bytes."
            case .invalidVertexReference(let path, let field, let index, let count):
                "Collision binary '\(path)' has \(field) index \(index) outside \(count) available vertices."
            case .invalidSurfaceTypeReference(let path, let index, let count):
                "Collision binary '\(path)' has surfaceType index \(index) outside \(count) available surface types."
            }
        }
    }

    static func decode(_ data: Data, path: String = "<memory>") throws -> CollisionMesh {
        var offset = data.startIndex
        let minimumBounds = try Vector3s(
            x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
        )
        let maximumBounds = try Vector3s(
            x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
        )
        let vertexCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let polygonCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let surfaceTypeCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let waterBoxCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))

        var vertices: [Vector3s] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            vertices.append(
                try Vector3s(
                    x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                )
            )
        }

        var polygons: [CollisionPoly] = []
        polygons.reserveCapacity(polygonCount)
        for _ in 0..<polygonCount {
            polygons.append(
                try CollisionPoly(
                    surfaceType: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexA: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexB: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexC: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    normal: Vector3s(
                        x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                        y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                        z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                    ),
                    distance: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                )
            )
        }

        var surfaceTypes: [CollisionSurfaceType] = []
        surfaceTypes.reserveCapacity(surfaceTypeCount)
        for _ in 0..<surfaceTypeCount {
            surfaceTypes.append(
                try CollisionSurfaceType(
                    low: readInteger(from: data, offset: &offset, as: UInt32.self, path: path),
                    high: readInteger(from: data, offset: &offset, as: UInt32.self, path: path)
                )
            )
        }

        var waterBoxes: [CollisionWaterBox] = []
        waterBoxes.reserveCapacity(waterBoxCount)
        for _ in 0..<waterBoxCount {
            waterBoxes.append(
                try CollisionWaterBox(
                    xMin: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    ySurface: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    zMin: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    xLength: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    zLength: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    properties: readInteger(from: data, offset: &offset, as: UInt32.self, path: path)
                )
            )
        }

        guard offset == data.endIndex else {
            throw DecodingError.invalidBinarySize(path, data.count, offset)
        }

        for polygon in polygons {
            try validateVertexReference(polygon.vertexA, field: "vertexA", vertices: vertices, path: path)
            try validateVertexReference(polygon.vertexB, field: "vertexB", vertices: vertices, path: path)
            try validateVertexReference(polygon.vertexC, field: "vertexC", vertices: vertices, path: path)
            if surfaceTypes.isEmpty == false, Int(polygon.surfaceType) >= surfaceTypes.count {
                throw DecodingError.invalidSurfaceTypeReference(path, Int(polygon.surfaceType), surfaceTypes.count)
            }
        }

        return CollisionMesh(
            minimumBounds: minimumBounds,
            maximumBounds: maximumBounds,
            vertices: vertices,
            polygons: polygons,
            surfaceTypes: surfaceTypes,
            waterBoxes: waterBoxes
        )
    }

    private static func validateVertexReference(
        _ index: UInt16,
        field: String,
        vertices: [Vector3s],
        path: String
    ) throws {
        guard Int(index) < vertices.count else {
            throw DecodingError.invalidVertexReference(path, field, Int(index), vertices.count)
        }
    }

    private static func readInteger<T: FixedWidthInteger>(
        from data: Data,
        offset: inout Int,
        as type: T.Type,
        path: String
    ) throws -> T {
        let byteCount = MemoryLayout<T>.size
        guard offset + byteCount <= data.endIndex else {
            throw DecodingError.invalidBinarySize(path, data.count, offset)
        }

        let value = data[offset ..< offset + byteCount].reduce(T.zero) { partial, byte in
            (partial << 8) | T(byte)
        }
        offset += byteCount
        return value
    }
}
