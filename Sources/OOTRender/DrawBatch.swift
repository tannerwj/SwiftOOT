import Foundation
import Metal
import OOTDataModel
import simd

public struct RenderStateKey: Hashable, Sendable {
    public var combinerHash: UInt64
    public var geometryMode: GeometryMode
    public var renderMode: RenderMode

    public init(
        combinerHash: UInt64,
        geometryMode: GeometryMode,
        renderMode: RenderMode
    ) {
        self.combinerHash = combinerHash
        self.geometryMode = geometryMode
        self.renderMode = renderMode
    }
}

public protocol RenderPipelineStateLookup {
    func renderPipelineState(for key: RenderStateKey) throws -> MTLRenderPipelineState
}

public struct AnyRenderPipelineStateLookup: RenderPipelineStateLookup {
    private let resolver: (RenderStateKey) throws -> MTLRenderPipelineState

    public init(
        _ resolver: @escaping (RenderStateKey) throws -> MTLRenderPipelineState
    ) {
        self.resolver = resolver
    }

    public func renderPipelineState(
        for key: RenderStateKey
    ) throws -> MTLRenderPipelineState {
        try resolver(key)
    }
}

public struct DrawBatchResources {
    public let device: MTLDevice
    public let pipelineLookup: any RenderPipelineStateLookup

    public init(
        device: MTLDevice,
        pipelineLookup: any RenderPipelineStateLookup
    ) {
        self.device = device
        self.pipelineLookup = pipelineLookup
    }
}

public enum DrawBatchError: Error, Equatable {
    case missingResources
    case invalidTriangleIndex(UInt32, vertexCount: Int)
    case vertexBufferAllocationFailed(byteCount: Int)
    case indexBufferAllocationFailed(byteCount: Int)
}

public struct DrawBatch {
    public var renderStateKey: RenderStateKey
    public var texture: MTLTexture?

    public private(set) var totalTriangleCount: Int = 0
    public private(set) var drawCallCount: Int = 0

    private let resources: DrawBatchResources?
    private var vertexStorage: [DrawBatchVertex] = []
    private var indexStorage: [UInt32] = []

    public init(
        renderStateKey: RenderStateKey,
        texture: MTLTexture? = nil,
        resources: DrawBatchResources? = nil
    ) {
        self.renderStateKey = renderStateKey
        self.texture = texture
        self.resources = resources
    }

    public var vertexCount: Int {
        vertexStorage.count
    }

    public var indexCount: Int {
        indexStorage.count
    }

    public var pendingTriangleCount: Int {
        indexStorage.count / 3
    }

    public var isEmpty: Bool {
        indexStorage.isEmpty
    }

    public mutating func append(
        vertices: [TransformedVertex],
        triangles: [SIMD3<UInt32>]
    ) throws {
        guard !vertices.isEmpty, !triangles.isEmpty else {
            return
        }

        let vertexBaseIndex = UInt32(vertexStorage.count)
        let localVertexCount = vertices.count
        vertexStorage.append(
            contentsOf: vertices.map(DrawBatchVertex.init)
        )

        for triangle in triangles {
            try appendTriangleIndex(triangle.x, localVertexCount: localVertexCount, baseIndex: vertexBaseIndex)
            try appendTriangleIndex(triangle.y, localVertexCount: localVertexCount, baseIndex: vertexBaseIndex)
            try appendTriangleIndex(triangle.z, localVertexCount: localVertexCount, baseIndex: vertexBaseIndex)
        }
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        vertexStorage.removeAll(keepingCapacity: keepingCapacity)
        indexStorage.removeAll(keepingCapacity: keepingCapacity)
    }

    @discardableResult
    public mutating func flush(
        encoder: MTLRenderCommandEncoder
    ) throws -> Bool {
        guard !isEmpty else {
            return false
        }

        guard let resources else {
            throw DrawBatchError.missingResources
        }

        let vertexBufferLength = MemoryLayout<DrawBatchVertex>.stride * vertexStorage.count
        guard let vertexBuffer = resources.device.makeBuffer(
            bytes: vertexStorage,
            length: vertexBufferLength
        ) else {
            throw DrawBatchError.vertexBufferAllocationFailed(byteCount: vertexBufferLength)
        }

        let indexBufferLength = MemoryLayout<UInt32>.stride * indexStorage.count
        guard let indexBuffer = resources.device.makeBuffer(
            bytes: indexStorage,
            length: indexBufferLength
        ) else {
            throw DrawBatchError.indexBufferAllocationFailed(byteCount: indexBufferLength)
        }

        let pipelineState = try resources.pipelineLookup.renderPipelineState(for: renderStateKey)
        let flushedTriangleCount = pendingTriangleCount

        encoder.setRenderPipelineState(pipelineState)
        encoder.setCullMode(cullMode(for: renderStateKey.geometryMode))
        encoder.setVertexBuffer(
            vertexBuffer,
            offset: 0,
            index: OOTRenderBufferIndex.vertices.rawValue
        )
        if let texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexStorage.count,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        totalTriangleCount += flushedTriangleCount
        drawCallCount += 1
        removeAll()
        return true
    }

    private mutating func appendTriangleIndex(
        _ index: UInt32,
        localVertexCount: Int,
        baseIndex: UInt32
    ) throws {
        guard index < UInt32(localVertexCount) else {
            throw DrawBatchError.invalidTriangleIndex(index, vertexCount: localVertexCount)
        }

        indexStorage.append(baseIndex + index)
    }
}

struct DrawBatchVertex: Equatable {
    var clipPosition: SIMD4<Float>
    var color: SIMD4<Float>
    var textureCoordinates: SIMD2<Float>
    var fog: Float

    init(_ transformedVertex: TransformedVertex) {
        clipPosition = transformedVertex.clipPosition
        color = transformedVertex.color
        textureCoordinates = transformedVertex.textureCoordinates
        fog = 1.0
    }
}

func makeDrawBatchPipelineState(
    device: MTLDevice,
    bundle: Bundle = OOTRenderer.resourceBundle,
    colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
    renderStateKey: RenderStateKey
) throws -> MTLRenderPipelineState {
    let library = try OOTRenderer.makeLibrary(device: device, bundle: bundle)
    let vertexFunction = try OOTRenderer.makeFunction(
        named: "oot_draw_batch_vertex",
        in: library
    )
    let fragmentFunction = try OOTRenderer.makeFunction(
        named: "oot_flat_color_fragment",
        in: library
    )
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.label = [
        "DrawBatchPipeline",
        String(renderStateKey.combinerHash),
        String(renderStateKey.geometryMode.rawValue),
        String(renderStateKey.renderMode.flags),
    ].joined(separator: "-")
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    descriptor.vertexDescriptor = makeDrawBatchVertexDescriptor()
    descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

    return try device.makeRenderPipelineState(descriptor: descriptor)
}

private func makeDrawBatchVertexDescriptor() -> MTLVertexDescriptor {
    let descriptor = MTLVertexDescriptor()

    descriptor.attributes[0].format = .float4
    descriptor.attributes[0].offset = 0
    descriptor.attributes[0].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.attributes[1].format = .float4
    descriptor.attributes[1].offset = 16
    descriptor.attributes[1].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.attributes[2].format = .float2
    descriptor.attributes[2].offset = 32
    descriptor.attributes[2].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.attributes[3].format = .float
    descriptor.attributes[3].offset = 40
    descriptor.attributes[3].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stride = MemoryLayout<DrawBatchVertex>.stride
    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stepFunction = .perVertex

    return descriptor
}

private func cullMode(for geometryMode: GeometryMode) -> MTLCullMode {
    if geometryMode.contains(.cullFront) {
        return .front
    }

    if geometryMode.contains(.cullBack) {
        return .back
    }

    return .none
}
