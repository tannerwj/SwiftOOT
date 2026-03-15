import Foundation
import OOTDataModel
import simd

public struct OOTRenderRoom: Sendable, Equatable {
    public var name: String
    public var displayList: [F3DEX2Command]
    public var vertexData: Data
    public var vertexSegment: UInt8
    public var additionalSegments: [UInt8: Data]
    public var isVisible: Bool

    public init(
        name: String,
        displayList: [F3DEX2Command],
        vertexData: Data,
        vertexSegment: UInt8 = 0x03,
        additionalSegments: [UInt8: Data] = [:],
        isVisible: Bool = true
    ) {
        self.name = name
        self.displayList = displayList
        self.vertexData = vertexData
        self.vertexSegment = vertexSegment
        self.additionalSegments = additionalSegments
        self.isVisible = isVisible
    }

    public var segmentData: [UInt8: Data] {
        var segments = additionalSegments
        segments[vertexSegment] = vertexData
        return segments
    }

    public var vertexCount: Int {
        vertexData.count / MemoryLayout<N64Vertex>.stride
    }

    public var vertices: [N64Vertex] {
        Self.decodeVertices(from: vertexData)
    }
}

public struct OOTRenderScene: Sendable, Equatable {
    public var rooms: [OOTRenderRoom]
    public var skeletons: [OOTRenderSkeleton]
    public var skyColor: SIMD4<Float>

    public init(
        rooms: [OOTRenderRoom],
        skeletons: [OOTRenderSkeleton] = [],
        skyColor: SIMD4<Float> = SIMD4<Float>(
            45.0 / 255.0,
            155.0 / 255.0,
            52.0 / 255.0,
            1.0
        )
    ) {
        self.rooms = rooms
        self.skeletons = skeletons
        self.skyColor = skyColor
    }

    public var visibleRooms: [OOTRenderRoom] {
        rooms.filter(\.isVisible)
    }

    public var sceneBounds: SceneBounds {
        let vertices = rooms.flatMap(\.vertices)
        return SceneBounds(vertices: vertices)
    }

    public static func syntheticScene(
        name: String = "DebugRoom",
        vertices: [N64Vertex],
        skyColor: SIMD4<Float> = SIMD4<Float>(
            45.0 / 255.0,
            155.0 / 255.0,
            52.0 / 255.0,
            1.0
        )
    ) -> OOTRenderScene {
        OOTRenderScene(
            rooms: [
                OOTRenderRoom(
                    name: name,
                    displayList: makeDisplayList(for: vertices.count),
                    vertexData: encodeVertices(vertices)
                )
            ],
            skeletons: [],
            skyColor: skyColor
        )
    }
}

private extension OOTRenderRoom {
    static func decodeVertices(from data: Data) -> [N64Vertex] {
        guard data.count >= MemoryLayout<N64Vertex>.stride else {
            return []
        }

        let vertexCount = data.count / MemoryLayout<N64Vertex>.stride
        var vertices: [N64Vertex] = []
        vertices.reserveCapacity(vertexCount)

        for vertexIndex in 0..<vertexCount {
            let base = vertexIndex * MemoryLayout<N64Vertex>.stride
            vertices.append(
                N64Vertex(
                    position: Vector3s(
                        x: readInteger(from: data, offset: base, as: Int16.self),
                        y: readInteger(from: data, offset: base + 2, as: Int16.self),
                        z: readInteger(from: data, offset: base + 4, as: Int16.self)
                    ),
                    flag: readInteger(from: data, offset: base + 6, as: UInt16.self),
                    textureCoordinate: Vector2s(
                        x: readInteger(from: data, offset: base + 8, as: Int16.self),
                        y: readInteger(from: data, offset: base + 10, as: Int16.self)
                    ),
                    colorOrNormal: RGBA8(
                        red: readInteger(from: data, offset: base + 12, as: UInt8.self),
                        green: readInteger(from: data, offset: base + 13, as: UInt8.self),
                        blue: readInteger(from: data, offset: base + 14, as: UInt8.self),
                        alpha: readInteger(from: data, offset: base + 15, as: UInt8.self)
                    )
                )
            )
        }

        return vertices
    }

    static func readInteger<T: FixedWidthInteger>(
        from data: Data,
        offset: Int,
        as type: T.Type
    ) -> T {
        let range = offset..<(offset + MemoryLayout<T>.size)
        return data[range].withUnsafeBytes { rawBuffer in
            T(bigEndian: rawBuffer.load(as: T.self))
        }
    }
}

private func makeDisplayList(for vertexCount: Int) -> [F3DEX2Command] {
    guard vertexCount >= 3 else {
        return [.spEndDisplayList]
    }

    let limitedVertexCount = min(vertexCount, Int(UInt8.max) + 1, 32)
    var commands: [F3DEX2Command] = [
        .spVertex(
            VertexCommand(
                address: 0x0300_0000,
                count: UInt16(limitedVertexCount),
                destinationIndex: 0
            )
        )
    ]

    for triangleStart in stride(from: 0, to: limitedVertexCount - 2, by: 3) {
        commands.append(
            .sp1Triangle(
                TriangleCommand(
                    vertex0: UInt8(triangleStart),
                    vertex1: UInt8(triangleStart + 1),
                    vertex2: UInt8(triangleStart + 2),
                    flag: 0
                )
            )
        )
    }

    commands.append(.spEndDisplayList)
    return commands
}

private func encodeVertices(_ vertices: [N64Vertex]) -> Data {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(vertices.count * MemoryLayout<N64Vertex>.stride)

    for vertex in vertices {
        append(&bytes, vertex.position.x)
        append(&bytes, vertex.position.y)
        append(&bytes, vertex.position.z)
        append(&bytes, vertex.flag)
        append(&bytes, vertex.textureCoordinate.x)
        append(&bytes, vertex.textureCoordinate.y)
        bytes.append(vertex.colorOrNormal.red)
        bytes.append(vertex.colorOrNormal.green)
        bytes.append(vertex.colorOrNormal.blue)
        bytes.append(vertex.colorOrNormal.alpha)
    }

    return Data(bytes)
}

private func append<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ value: T) {
    let bigEndianValue = value.bigEndian
    withUnsafeBytes(of: bigEndianValue) { buffer in
        bytes.append(contentsOf: buffer)
    }
}
