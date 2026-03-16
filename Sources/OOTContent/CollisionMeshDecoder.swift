import Foundation
import OOTDataModel

enum CollisionMeshDecoder {
    private enum BinaryLayout {
        case modern(bgCameraCount: Int, waterBoxCount: Int)
        case legacy(waterBoxCount: Int)
    }

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
        let legacyLayout = legacyLayoutIfAvailable(for: data)
        let modernLayout = modernLayoutIfAvailable(for: data)

        if let modernLayout {
            do {
                return try decode(data, path: path, layout: modernLayout)
            } catch let error as DecodingError {
                if let legacyLayout {
                    return try decode(data, path: path, layout: legacyLayout)
                }
                throw error
            }
        }

        if let legacyLayout {
            return try decode(data, path: path, layout: legacyLayout)
        }

        return try decode(data, path: path, layout: .modern(bgCameraCount: 0, waterBoxCount: 0))
    }

    private static func decode(
        _ data: Data,
        path: String,
        layout: BinaryLayout
    ) throws -> CollisionMesh {
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
        let bgCameraCount: Int
        let waterBoxCount: Int

        switch layout {
        case .modern(let modernBgCameraCount, let modernWaterBoxCount):
            _ = try readInteger(from: data, offset: &offset, as: UInt16.self, path: path)
            _ = try readInteger(from: data, offset: &offset, as: UInt16.self, path: path)
            bgCameraCount = modernBgCameraCount
            waterBoxCount = modernWaterBoxCount
        case .legacy(let legacyWaterBoxCount):
            _ = try readInteger(from: data, offset: &offset, as: UInt16.self, path: path)
            bgCameraCount = 0
            waterBoxCount = legacyWaterBoxCount
        }

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

        var bgCameras: [CollisionBgCamera] = []
        bgCameras.reserveCapacity(bgCameraCount)
        for _ in 0..<bgCameraCount {
            let setting = try readInteger(from: data, offset: &offset, as: UInt16.self, path: path)
            let count = try readInteger(from: data, offset: &offset, as: Int16.self, path: path)
            let hasCameraData = try readInteger(from: data, offset: &offset, as: UInt16.self, path: path) != 0
            let crawlspacePointCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))

            let cameraData: CollisionBgCameraData? = if hasCameraData {
                try CollisionBgCameraData(
                    position: readVector3s(from: data, offset: &offset, path: path),
                    rotation: readVector3s(from: data, offset: &offset, path: path),
                    fov: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    parameter: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    unknown: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                )
            } else {
                nil
            }

            var crawlspacePoints: [Vector3s] = []
            crawlspacePoints.reserveCapacity(crawlspacePointCount)
            for _ in 0..<crawlspacePointCount {
                crawlspacePoints.append(
                    try readVector3s(from: data, offset: &offset, path: path)
                )
            }

            bgCameras.append(
                CollisionBgCamera(
                    setting: setting,
                    count: count,
                    cameraData: cameraData,
                    crawlspacePoints: crawlspacePoints
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
            bgCameras: bgCameras,
            waterBoxes: waterBoxes
        )
    }

    private static func readVector3s(
        from data: Data,
        offset: inout Int,
        path: String
    ) throws -> Vector3s {
        try Vector3s(
            x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
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

    private static func modernLayoutIfAvailable(for data: Data) -> BinaryLayout? {
        guard
            let vertexCount = readUInt16(at: 12, from: data),
            let polygonCount = readUInt16(at: 14, from: data),
            let surfaceTypeCount = readUInt16(at: 16, from: data),
            let bgCameraCount = readUInt16(at: 18, from: data),
            let waterBoxCount = readUInt16(at: 20, from: data)
        else {
            return nil
        }

        let minimumBytes =
            22 +
            (vertexCount * 6) +
            (polygonCount * 16) +
            (surfaceTypeCount * 8) +
            (bgCameraCount * 8) +
            (waterBoxCount * 14)
        guard minimumBytes <= data.count else {
            return nil
        }

        return .modern(bgCameraCount: bgCameraCount, waterBoxCount: waterBoxCount)
    }

    private static func legacyLayoutIfAvailable(for data: Data) -> BinaryLayout? {
        guard
            let vertexCount = readUInt16(at: 12, from: data),
            let polygonCount = readUInt16(at: 14, from: data),
            let surfaceTypeCount = readUInt16(at: 16, from: data),
            let waterBoxCount = readUInt16(at: 18, from: data)
        else {
            return nil
        }

        let exactBytes =
            20 +
            (vertexCount * 6) +
            (polygonCount * 16) +
            (surfaceTypeCount * 8) +
            (waterBoxCount * 14)
        guard exactBytes == data.count else {
            return nil
        }

        return .legacy(waterBoxCount: waterBoxCount)
    }

    private static func readUInt16(at offset: Int, from data: Data) -> Int? {
        guard offset + 2 <= data.count else {
            return nil
        }
        return Int((UInt16(data[offset]) << 8) | UInt16(data[offset + 1]))
    }
}
