import Metal
import OOTDataModel
import simd

public struct VertexIn: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var texCoord: SIMD2<Float>
    public var color: SIMD4<Float>
    public var normal: SIMD3<Float>

    public init(
        position: SIMD3<Float>,
        texCoord: SIMD2<Float>,
        color: SIMD4<Float>,
        normal: SIMD3<Float>
    ) {
        self.position = position
        self.texCoord = texCoord
        self.color = color
        self.normal = normal
    }
}

public struct VertexOut: Sendable, Equatable {
    public var position: SIMD4<Float>
    public var texCoord: SIMD2<Float>
    public var color: SIMD4<Float>
    public var fog: Float

    public init(
        position: SIMD4<Float>,
        texCoord: SIMD2<Float>,
        color: SIMD4<Float>,
        fog: Float
    ) {
        self.position = position
        self.texCoord = texCoord
        self.color = color
        self.fog = fog
    }
}

public struct FrameUniforms: Sendable, Equatable {
    public var mvp: simd_float4x4
    public var fogParameters: SIMD4<Float>

    public init(
        mvp: simd_float4x4,
        fogParameters: SIMD4<Float> = SIMD4<Float>(0.0, 1.0, 0.0, 0.0)
    ) {
        self.mvp = mvp
        self.fogParameters = fogParameters
    }

    public static var identity: FrameUniforms {
        FrameUniforms(mvp: matrix_identity_float4x4)
    }
}

public struct CombinerUniforms: Sendable, Equatable {
    public var textureScale: SIMD2<Float>
    public var reserved: SIMD2<Float>

    public init(
        textureScale: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        reserved: SIMD2<Float> = .zero
    ) {
        self.textureScale = textureScale
        self.reserved = reserved
    }
}

enum OOTRenderBufferIndex: Int {
    case vertices = 0
    case frameUniforms = 1
    case combinerUniforms = 2
}

enum OOTRenderVertexAttribute: Int {
    case position = 0
    case texCoord = 1
    case color = 2
}

func makeN64VertexDescriptor() -> MTLVertexDescriptor {
    let descriptor = MTLVertexDescriptor()

    descriptor.attributes[OOTRenderVertexAttribute.position.rawValue].format = .short3
    descriptor.attributes[OOTRenderVertexAttribute.position.rawValue].offset = 0
    descriptor.attributes[OOTRenderVertexAttribute.position.rawValue].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.attributes[OOTRenderVertexAttribute.texCoord.rawValue].format = .short2
    descriptor.attributes[OOTRenderVertexAttribute.texCoord.rawValue].offset = 8
    descriptor.attributes[OOTRenderVertexAttribute.texCoord.rawValue].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].format = .uchar4Normalized
    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].offset = 12
    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stride = MemoryLayout<N64Vertex>.stride
    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stepFunction = .perVertex

    return descriptor
}
