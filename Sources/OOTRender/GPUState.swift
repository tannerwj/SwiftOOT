import Foundation
import OOTDataModel
import simd

public enum GPUStateError: Error, Sendable, Equatable {
    case matrixStackOverflow(maxDepth: Int)
    case matrixStackUnderflow
    case vertexIndexOutOfRange(Int)
    case vertexRangeOutOfRange(start: Int, count: Int, capacity: Int)
    case segmentIndexOutOfRange(UInt8)
    case tileIndexOutOfRange(Int)
}

public struct TransformedVertex: Sendable, Equatable {
    public var clipPosition: SIMD4<Float>
    public var textureCoordinates: SIMD2<Float>
    public var color: SIMD4<Float>

    public init(
        clipPosition: SIMD4<Float>,
        textureCoordinates: SIMD2<Float>,
        color: SIMD4<Float>
    ) {
        self.clipPosition = clipPosition
        self.textureCoordinates = textureCoordinates
        self.color = color
    }
}

public struct GeometryMode: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let zBuffer = Self(rawValue: 0x0000_0001)
    public static let cullFront = Self(rawValue: 0x0000_0200)
    public static let cullBack = Self(rawValue: 0x0000_0400)
    public static let cull: Self = [.cullFront, .cullBack]
    public static let fog = Self(rawValue: 0x0001_0000)
    public static let lighting = Self(rawValue: 0x0002_0000)
    public static let smoothShading = Self(rawValue: 0x0020_0000)
}

public struct MatrixStack: Sendable {
    public static let maximumDepth = 18

    private var storage: [simd_float4x4]

    public init(initialMatrix: simd_float4x4 = matrix_identity_float4x4) {
        self.storage = [initialMatrix]
    }

    public var depth: Int {
        storage.count
    }

    public var currentMatrix: simd_float4x4 {
        storage[storage.count - 1]
    }

    public mutating func push() throws {
        guard storage.count < Self.maximumDepth else {
            throw GPUStateError.matrixStackOverflow(maxDepth: Self.maximumDepth)
        }

        storage.append(currentMatrix)
    }

    @discardableResult
    public mutating func pop() throws -> simd_float4x4 {
        guard storage.count > 1 else {
            throw GPUStateError.matrixStackUnderflow
        }

        return storage.removeLast()
    }

    public mutating func load(_ matrix: simd_float4x4) {
        storage[storage.count - 1] = matrix
    }

    public mutating func multiply(by matrix: simd_float4x4) {
        storage[storage.count - 1] = simd_mul(currentMatrix, matrix)
    }
}

public struct RSPState: Sendable {
    public static let vertexCapacity = 32

    public private(set) var vertexBuffer: [TransformedVertex?]
    public private(set) var matrixStack: MatrixStack
    public private(set) var geometryMode: GeometryMode
    public private(set) var textureState: TextureState

    public init(
        vertexBuffer: [TransformedVertex?] = Array(repeating: nil, count: Self.vertexCapacity),
        matrixStack: MatrixStack = MatrixStack(),
        geometryMode: GeometryMode = [],
        textureState: TextureState = TextureState(
            scaleS: 0,
            scaleT: 0,
            level: 0,
            tile: 0,
            enabled: false
        )
    ) {
        self.vertexBuffer = Array(vertexBuffer.prefix(Self.vertexCapacity))
        if self.vertexBuffer.count < Self.vertexCapacity {
            self.vertexBuffer.append(
                contentsOf: Array(repeating: nil, count: Self.vertexCapacity - self.vertexBuffer.count)
            )
        }
        self.matrixStack = matrixStack
        self.geometryMode = geometryMode
        self.textureState = textureState
    }

    public var currentMatrix: simd_float4x4 {
        matrixStack.currentMatrix
    }

    public mutating func pushMatrix() throws {
        try matrixStack.push()
    }

    @discardableResult
    public mutating func popMatrix() throws -> simd_float4x4 {
        try matrixStack.pop()
    }

    public mutating func loadMatrix(_ matrix: simd_float4x4) {
        matrixStack.load(matrix)
    }

    public mutating func multiplyMatrix(by matrix: simd_float4x4) {
        matrixStack.multiply(by: matrix)
    }

    public mutating func loadVertex(_ vertex: TransformedVertex, at index: Int) throws {
        try validateVertexIndex(index)
        vertexBuffer[index] = vertex
    }

    public mutating func loadVertices(
        _ vertices: [TransformedVertex],
        startingAt index: Int
    ) throws {
        guard index >= 0, index + vertices.count <= Self.vertexCapacity else {
            throw GPUStateError.vertexRangeOutOfRange(
                start: index,
                count: vertices.count,
                capacity: Self.vertexCapacity
            )
        }

        for (offset, vertex) in vertices.enumerated() {
            vertexBuffer[index + offset] = vertex
        }
    }

    public func vertex(at index: Int) throws -> TransformedVertex? {
        try validateVertexIndex(index)
        return vertexBuffer[index]
    }

    public mutating func setGeometryMode(_ flags: GeometryMode) {
        geometryMode.formUnion(flags)
    }

    public mutating func clearGeometryMode(_ flags: GeometryMode) {
        geometryMode.subtract(flags)
    }

    public mutating func applyGeometryMode(clearBits: UInt32, setBits: UInt32) {
        geometryMode = GeometryMode(rawValue: (geometryMode.rawValue & ~clearBits) | setBits)
    }

    public mutating func setTextureState(
        enabled: Bool,
        scaleS: UInt16,
        scaleT: UInt16,
        level: UInt8 = 0,
        tile: UInt8 = 0
    ) {
        textureState = TextureState(
            scaleS: scaleS,
            scaleT: scaleT,
            level: level,
            tile: tile,
            enabled: enabled
        )
    }

    private func validateVertexIndex(_ index: Int) throws {
        guard (0..<Self.vertexCapacity).contains(index) else {
            throw GPUStateError.vertexIndexOutOfRange(index)
        }
    }
}

public struct RDPCombineSelectorGroup: Sendable, Equatable {
    public var a: UInt8
    public var b: UInt8
    public var c: UInt8
    public var d: UInt8

    public init(a: UInt8, b: UInt8, c: UInt8, d: UInt8) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }
}

public struct RDPCombineCycle: Sendable, Equatable {
    public var color: RDPCombineSelectorGroup
    public var alpha: RDPCombineSelectorGroup

    public init(
        color: RDPCombineSelectorGroup,
        alpha: RDPCombineSelectorGroup
    ) {
        self.color = color
        self.alpha = alpha
    }
}

public struct RDPCombineState: Sendable, Equatable {
    public var firstCycle: RDPCombineCycle
    public var secondCycle: RDPCombineCycle

    public init(
        firstCycle: RDPCombineCycle = RDPCombineCycle(
            color: RDPCombineSelectorGroup(a: 0, b: 0, c: 0, d: 0),
            alpha: RDPCombineSelectorGroup(a: 0, b: 0, c: 0, d: 0)
        ),
        secondCycle: RDPCombineCycle = RDPCombineCycle(
            color: RDPCombineSelectorGroup(a: 0, b: 0, c: 0, d: 0),
            alpha: RDPCombineSelectorGroup(a: 0, b: 0, c: 0, d: 0)
        )
    ) {
        self.firstCycle = firstCycle
        self.secondCycle = secondCycle
    }
}

public struct RDPState: Sendable {
    public static let tileCount = 8

    public var combineMode: RDPCombineState
    public private(set) var tileDescriptors: [TileDescriptor]
    public var primitiveColor: PrimitiveColor
    public var environmentColor: RGBA8
    public var fogColor: RGBA8
    public var blendColor: RGBA8
    public var fillColor: UInt32
    public var renderMode: RenderMode
    public var otherMode: OtherMode

    public init(
        combineMode: RDPCombineState = RDPCombineState(),
        tileDescriptors: [TileDescriptor]? = nil,
        primitiveColor: PrimitiveColor = PrimitiveColor(
            minimumLOD: 0,
            level: 0,
            color: RGBA8(red: 0, green: 0, blue: 0, alpha: 0)
        ),
        environmentColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        fogColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        blendColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        fillColor: UInt32 = 0,
        renderMode: RenderMode = RenderMode(flags: 0),
        otherMode: OtherMode = OtherMode(high: 0, low: 0)
    ) {
        self.combineMode = combineMode
        self.tileDescriptors = tileDescriptors ?? (0..<Self.tileCount).map(Self.defaultTileDescriptor)
        self.primitiveColor = primitiveColor
        self.environmentColor = environmentColor
        self.fogColor = fogColor
        self.blendColor = blendColor
        self.fillColor = fillColor
        self.renderMode = renderMode
        self.otherMode = otherMode
    }

    public mutating func setCombineMode(_ combineMode: RDPCombineState) {
        self.combineMode = combineMode
    }

    public mutating func setTileDescriptor(_ descriptor: TileDescriptor) throws {
        let tileIndex = Int(descriptor.tile)
        try validateTileIndex(tileIndex)
        tileDescriptors[tileIndex] = descriptor
    }

    public func tileDescriptor(at index: Int) throws -> TileDescriptor {
        try validateTileIndex(index)
        return tileDescriptors[index]
    }

    private func validateTileIndex(_ index: Int) throws {
        guard (0..<Self.tileCount).contains(index) else {
            throw GPUStateError.tileIndexOutOfRange(index)
        }
    }

    private static func defaultTileDescriptor(for tile: Int) -> TileDescriptor {
        TileDescriptor(
            format: .rgba16,
            texelSize: .bits16,
            line: 0,
            tmem: 0,
            tile: UInt8(tile),
            palette: 0,
            clampS: false,
            mirrorS: false,
            maskS: 0,
            shiftS: 0,
            clampT: false,
            mirrorT: false,
            maskT: 0,
            shiftT: 0
        )
    }
}

public struct SegmentTable: Sendable {
    public static let segmentCount = 16

    private var storage: [Data?]

    public init(storage: [Data?] = Array(repeating: nil, count: Self.segmentCount)) {
        self.storage = Array(storage.prefix(Self.segmentCount))
        if self.storage.count < Self.segmentCount {
            self.storage.append(
                contentsOf: Array(repeating: nil, count: Self.segmentCount - self.storage.count)
            )
        }
    }

    public mutating func setSegment(_ segment: UInt8, data: Data?) throws {
        let index = try validatedSegmentIndex(segment)
        storage[index] = data
    }

    public func data(for segment: UInt8) throws -> Data? {
        let index = try validatedSegmentIndex(segment)
        return storage[index]
    }

    private func validatedSegmentIndex(_ segment: UInt8) throws -> Int {
        let index = Int(segment)
        guard (0..<Self.segmentCount).contains(index) else {
            throw GPUStateError.segmentIndexOutOfRange(segment)
        }

        return index
    }
}
