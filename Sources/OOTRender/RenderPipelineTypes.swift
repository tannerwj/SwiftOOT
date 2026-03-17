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
    public var ambientColor: SIMD4<Float>
    public var directionalLightColor: SIMD4<Float>
    public var directionalLightDirection: SIMD4<Float>
    public var fogColor: SIMD4<Float>
    public var renderTweaks: SIMD4<Float>

    public init(
        mvp: simd_float4x4,
        fogParameters: SIMD4<Float> = SIMD4<Float>(0.0, 1.0, 0.0, 0.0),
        ambientColor: SIMD4<Float> = SceneEnvironmentState.default.ambientColor,
        directionalLightColor: SIMD4<Float> = SceneEnvironmentState.default.directionalLightColor,
        directionalLightDirection: SIMD4<Float> = SceneEnvironmentState.default.directionalLightDirection,
        fogColor: SIMD4<Float> = SceneEnvironmentState.default.fogColor,
        renderTweaks: SIMD4<Float> = .zero
    ) {
        self.mvp = mvp
        self.fogParameters = fogParameters
        self.ambientColor = ambientColor
        self.directionalLightColor = directionalLightColor
        self.directionalLightDirection = directionalLightDirection
        self.fogColor = fogColor
        self.renderTweaks = renderTweaks
    }

    public static var identity: FrameUniforms {
        FrameUniforms(mvp: matrix_identity_float4x4)
    }

    func withEnvironment(_ environment: SceneEnvironmentState) -> FrameUniforms {
        FrameUniforms(
            mvp: mvp,
            fogParameters: SIMD4<Float>(
                environment.fogNear,
                environment.fogFar,
                0.0,
                0.0
            ),
            ambientColor: environment.ambientColor,
            directionalLightColor: environment.directionalLightColor,
            directionalLightDirection: environment.directionalLightDirection,
            fogColor: environment.fogColor,
            renderTweaks: renderTweaks
        )
    }
}

public enum CombinerSourceSelector: UInt32, Sendable {
    case combined = 0
    case texel0 = 1
    case texel1 = 2
    case primitive = 3
    case shade = 4
    case environment = 5
    case one = 6
    case noise = 7
    case zero = 31
}

public struct TextureSamplingState: Sendable, Equatable {
    public var scale: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var dimensions: SIMD2<Float>
    public var tileSpan: SIMD2<Float>
    public var clamp: SIMD2<UInt32>
    public var mirror: SIMD2<UInt32>

    public init(
        scale: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        offset: SIMD2<Float> = .zero,
        dimensions: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        tileSpan: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        clamp: SIMD2<UInt32> = SIMD2<UInt32>(repeating: 1),
        mirror: SIMD2<UInt32> = .zero
    ) {
        self.scale = scale
        self.offset = offset
        self.dimensions = dimensions
        self.tileSpan = tileSpan
        self.clamp = clamp
        self.mirror = mirror
    }
}

public struct CombinerUniforms: Sendable, Equatable {
    public var cycle1ColorSelectors: SIMD4<UInt32>
    public var cycle1AlphaSelectors: SIMD4<UInt32>
    public var cycle2ColorSelectors: SIMD4<UInt32>
    public var cycle2AlphaSelectors: SIMD4<UInt32>
    public var primitiveColor: SIMD4<Float>
    public var environmentColor: SIMD4<Float>
    public var fogColor: SIMD4<Float>
    public var textureScale: SIMD2<Float>
    public var textureOffset: SIMD2<Float>
    public var textureDimensions: SIMD2<Float>
    public var textureTileSpan: SIMD2<Float>
    public var textureClamp: SIMD2<UInt32>
    public var textureMirror: SIMD2<UInt32>
    public var alphaCompareThreshold: Float
    public var alphaCompareMode: UInt32
    public var geometryMode: UInt32
    public var renderMode: UInt32

    public init(
        cycle1ColorSelectors: SIMD4<UInt32> = SIMD4<UInt32>(
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.shade.rawValue
        ),
        cycle1AlphaSelectors: SIMD4<UInt32> = SIMD4<UInt32>(
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.shade.rawValue
        ),
        cycle2ColorSelectors: SIMD4<UInt32> = SIMD4<UInt32>(
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.combined.rawValue
        ),
        cycle2AlphaSelectors: SIMD4<UInt32> = SIMD4<UInt32>(
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.combined.rawValue
        ),
        primitiveColor: SIMD4<Float> = .zero,
        environmentColor: SIMD4<Float> = .zero,
        fogColor: SIMD4<Float> = .zero,
        textureScale: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        textureOffset: SIMD2<Float> = .zero,
        textureDimensions: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        textureTileSpan: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        textureClamp: SIMD2<UInt32> = SIMD2<UInt32>(repeating: 1),
        textureMirror: SIMD2<UInt32> = .zero,
        alphaCompareThreshold: Float = 0.0,
        alphaCompareMode: UInt32 = 0,
        geometryMode: UInt32 = 0,
        renderMode: UInt32 = 0
    ) {
        self.cycle1ColorSelectors = cycle1ColorSelectors
        self.cycle1AlphaSelectors = cycle1AlphaSelectors
        self.cycle2ColorSelectors = cycle2ColorSelectors
        self.cycle2AlphaSelectors = cycle2AlphaSelectors
        self.primitiveColor = primitiveColor
        self.environmentColor = environmentColor
        self.fogColor = fogColor
        self.textureScale = textureScale
        self.textureOffset = textureOffset
        self.textureDimensions = textureDimensions
        self.textureTileSpan = textureTileSpan
        self.textureClamp = textureClamp
        self.textureMirror = textureMirror
        self.alphaCompareThreshold = alphaCompareThreshold
        self.alphaCompareMode = alphaCompareMode
        self.geometryMode = geometryMode
        self.renderMode = renderMode
    }

    public init(
        rdpState: RDPState,
        geometryMode: GeometryMode = [],
        textureSamplingState: TextureSamplingState = TextureSamplingState()
    ) {
        self.init(
            cycle1ColorSelectors: Self.normalizedColorSelectors(for: rdpState.combineMode.firstCycle.color),
            cycle1AlphaSelectors: Self.normalizedAlphaSelectors(for: rdpState.combineMode.firstCycle.alpha),
            cycle2ColorSelectors: Self.normalizedColorSelectors(for: rdpState.combineMode.secondCycle.color),
            cycle2AlphaSelectors: Self.normalizedAlphaSelectors(for: rdpState.combineMode.secondCycle.alpha),
            primitiveColor: normalizedColor(rdpState.primitiveColor.color),
            environmentColor: normalizedColor(rdpState.environmentColor),
            fogColor: normalizedColor(rdpState.fogColor),
            textureScale: textureSamplingState.scale,
            textureOffset: textureSamplingState.offset,
            textureDimensions: textureSamplingState.dimensions,
            textureTileSpan: textureSamplingState.tileSpan,
            textureClamp: textureSamplingState.clamp,
            textureMirror: textureSamplingState.mirror,
            alphaCompareThreshold: Float(rdpState.blendColor.alpha) / 255.0,
            alphaCompareMode: Self.alphaCompareMode(from: rdpState.otherMode),
            geometryMode: geometryMode.rawValue,
            renderMode: rdpState.renderMode.flags
        )
    }

    private static func normalizedColorSelectors(
        for selectors: RDPCombineSelectorGroup
    ) -> SIMD4<UInt32> {
        SIMD4<UInt32>(
            normalizedColorSelectorA(selectors.a),
            normalizedColorSelectorB(selectors.b),
            normalizedColorSelectorC(selectors.c),
            normalizedColorSelectorD(selectors.d)
        )
    }

    private static func normalizedAlphaSelectors(
        for selectors: RDPCombineSelectorGroup
    ) -> SIMD4<UInt32> {
        SIMD4<UInt32>(
            normalizedAlphaSelector(selectors.a),
            normalizedAlphaSelector(selectors.b),
            normalizedAlphaSelector(selectors.c),
            normalizedAlphaSelector(selectors.d)
        )
    }

    private static func normalizedColorSelectorA(_ selector: UInt8) -> UInt32 {
        switch selector {
        case 0:
            return CombinerSourceSelector.combined.rawValue
        case 1:
            return CombinerSourceSelector.texel0.rawValue
        case 2:
            return CombinerSourceSelector.texel1.rawValue
        case 3:
            return CombinerSourceSelector.primitive.rawValue
        case 4:
            return CombinerSourceSelector.shade.rawValue
        case 5:
            return CombinerSourceSelector.environment.rawValue
        case 6:
            return CombinerSourceSelector.one.rawValue
        case 7:
            return CombinerSourceSelector.noise.rawValue
        case 15:
            return CombinerSourceSelector.zero.rawValue
        default:
            return CombinerSourceSelector.zero.rawValue
        }
    }

    private static func normalizedColorSelectorB(_ selector: UInt8) -> UInt32 {
        normalizedColorSelectorA(selector)
    }

    private static func normalizedColorSelectorC(_ selector: UInt8) -> UInt32 {
        switch selector {
        case 31:
            return CombinerSourceSelector.zero.rawValue
        default:
            return normalizedColorSelectorA(selector)
        }
    }

    private static func normalizedColorSelectorD(_ selector: UInt8) -> UInt32 {
        switch selector {
        case 0:
            return CombinerSourceSelector.combined.rawValue
        case 1:
            return CombinerSourceSelector.texel0.rawValue
        case 2:
            return CombinerSourceSelector.texel1.rawValue
        case 3:
            return CombinerSourceSelector.primitive.rawValue
        case 4:
            return CombinerSourceSelector.shade.rawValue
        case 5:
            return CombinerSourceSelector.environment.rawValue
        case 6:
            return CombinerSourceSelector.one.rawValue
        case 7:
            return CombinerSourceSelector.zero.rawValue
        default:
            return CombinerSourceSelector.zero.rawValue
        }
    }

    private static func normalizedAlphaSelector(_ selector: UInt8) -> UInt32 {
        switch selector {
        case 0:
            return CombinerSourceSelector.combined.rawValue
        case 1:
            return CombinerSourceSelector.texel0.rawValue
        case 2:
            return CombinerSourceSelector.texel1.rawValue
        case 3:
            return CombinerSourceSelector.primitive.rawValue
        case 4:
            return CombinerSourceSelector.shade.rawValue
        case 5:
            return CombinerSourceSelector.environment.rawValue
        case 6:
            return CombinerSourceSelector.one.rawValue
        case 7:
            return CombinerSourceSelector.zero.rawValue
        default:
            return CombinerSourceSelector.zero.rawValue
        }
    }

    private static func alphaCompareMode(from otherMode: OtherMode) -> UInt32 {
        let compareBits = otherMode.low & 0x3

        switch compareBits {
        case 1:
            return 1
        case 3:
            return 2
        default:
            return 0
        }
    }
}

private func normalizedColor(_ color: RGBA8) -> SIMD4<Float> {
    SIMD4<Float>(
        Float(color.red) / 255.0,
        Float(color.green) / 255.0,
        Float(color.blue) / 255.0,
        Float(color.alpha) / 255.0
    )
}

enum OOTRenderBufferIndex: Int {
    case vertices = 0
    case frameUniforms = 1
    case combinerUniforms = 2
}

enum OOTRenderSamplerIndex: Int {
    case texel = 0
    case point = 1
    case linear = 2
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

    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].format = .uchar4
    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].offset = 12
    descriptor.attributes[OOTRenderVertexAttribute.color.rawValue].bufferIndex = OOTRenderBufferIndex.vertices.rawValue

    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stride = MemoryLayout<N64Vertex>.stride
    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stepFunction = .perVertex

    return descriptor
}
