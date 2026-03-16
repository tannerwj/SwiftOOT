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

    public init(
        mvp: simd_float4x4,
        fogParameters: SIMD4<Float> = SIMD4<Float>(0.0, 1.0, 0.0, 0.0),
        ambientColor: SIMD4<Float> = SceneEnvironmentState.default.ambientColor,
        directionalLightColor: SIMD4<Float> = SceneEnvironmentState.default.directionalLightColor,
        directionalLightDirection: SIMD4<Float> = SceneEnvironmentState.default.directionalLightDirection,
        fogColor: SIMD4<Float> = SceneEnvironmentState.default.fogColor
    ) {
        self.mvp = mvp
        self.fogParameters = fogParameters
        self.ambientColor = ambientColor
        self.directionalLightColor = directionalLightColor
        self.directionalLightDirection = directionalLightDirection
        self.fogColor = fogColor
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
            fogColor: environment.fogColor
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
    case combinedAlpha = 7
    case texel0Alpha = 8
    case texel1Alpha = 9
    case primitiveAlpha = 10
    case shadeAlpha = 11
    case environmentAlpha = 12
    case lodFraction = 13
    case primLodFraction = 14
    case k5 = 15
    case noise = 16
    case zero = 31
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
    public var alphaCompareThreshold: Float
    public var alphaCompareMode: UInt32
    public var geometryMode: UInt32
    public var renderMode: UInt32
    public var texel0Clamp: SIMD2<UInt32>
    public var texel1Clamp: SIMD2<UInt32>

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
        alphaCompareThreshold: Float = 0.0,
        alphaCompareMode: UInt32 = 0,
        geometryMode: UInt32 = 0,
        renderMode: UInt32 = 0,
        texel0Clamp: SIMD2<UInt32> = .zero,
        texel1Clamp: SIMD2<UInt32> = .zero
    ) {
        self.cycle1ColorSelectors = cycle1ColorSelectors
        self.cycle1AlphaSelectors = cycle1AlphaSelectors
        self.cycle2ColorSelectors = cycle2ColorSelectors
        self.cycle2AlphaSelectors = cycle2AlphaSelectors
        self.primitiveColor = primitiveColor
        self.environmentColor = environmentColor
        self.fogColor = fogColor
        self.textureScale = textureScale
        self.alphaCompareThreshold = alphaCompareThreshold
        self.alphaCompareMode = alphaCompareMode
        self.geometryMode = geometryMode
        self.renderMode = renderMode
        self.texel0Clamp = texel0Clamp
        self.texel1Clamp = texel1Clamp
    }

    public init(
        rdpState: RDPState,
        geometryMode: GeometryMode = [],
        textureScale: SIMD2<Float> = SIMD2<Float>(repeating: 1.0),
        texel0Clamp: SIMD2<UInt32> = .zero,
        texel1Clamp: SIMD2<UInt32> = .zero
    ) {
        self.init(
            cycle1ColorSelectors: Self.normalizedColorSelectors(for: rdpState.combineMode.firstCycle.color),
            cycle1AlphaSelectors: Self.normalizedAlphaSelectors(for: rdpState.combineMode.firstCycle.alpha),
            cycle2ColorSelectors: Self.normalizedColorSelectors(for: rdpState.combineMode.secondCycle.color),
            cycle2AlphaSelectors: Self.normalizedAlphaSelectors(for: rdpState.combineMode.secondCycle.alpha),
            primitiveColor: normalizedColor(rdpState.primitiveColor.color),
            environmentColor: normalizedColor(rdpState.environmentColor),
            fogColor: normalizedColor(rdpState.fogColor),
            textureScale: textureScale,
            alphaCompareThreshold: Float(rdpState.blendColor.alpha) / 255.0,
            alphaCompareMode: Self.alphaCompareMode(from: rdpState.otherMode),
            geometryMode: geometryMode.rawValue,
            renderMode: rdpState.renderMode.flags,
            texel0Clamp: texel0Clamp,
            texel1Clamp: texel1Clamp
        )
    }

    private static func normalizedColorSelectors(
        for selectors: RDPCombineSelectorGroup
    ) -> SIMD4<UInt32> {
        SIMD4<UInt32>(
            normalizedColorSelectorForA(selectors.a),
            normalizedColorSelectorForB(selectors.b),
            normalizedColorSelectorForC(selectors.c),
            normalizedColorSelectorForD(selectors.d)
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

    private static func normalizedColorSelectorForA(_ selector: UInt8) -> UInt32 {
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
            return CombinerSourceSelector.combinedAlpha.rawValue
        case 15, 31:
            return CombinerSourceSelector.zero.rawValue
        default:
            return CombinerSourceSelector.zero.rawValue
        }
    }

    private static func normalizedColorSelectorForB(_ selector: UInt8) -> UInt32 {
        normalizedColorSelectorForA(selector)
    }

    private static func normalizedColorSelectorForC(_ selector: UInt8) -> UInt32 {
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
            return CombinerSourceSelector.combinedAlpha.rawValue
        case 8:
            return CombinerSourceSelector.texel0Alpha.rawValue
        case 9:
            return CombinerSourceSelector.texel1Alpha.rawValue
        case 10:
            return CombinerSourceSelector.primitiveAlpha.rawValue
        case 11:
            return CombinerSourceSelector.shadeAlpha.rawValue
        case 12:
            return CombinerSourceSelector.environmentAlpha.rawValue
        case 13:
            return CombinerSourceSelector.lodFraction.rawValue
        case 14:
            return CombinerSourceSelector.primLodFraction.rawValue
        case 15:
            return CombinerSourceSelector.k5.rawValue
        case 31:
            return CombinerSourceSelector.zero.rawValue
        default:
            return CombinerSourceSelector.zero.rawValue
        }
    }

    private static func normalizedColorSelectorForD(_ selector: UInt8) -> UInt32 {
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
        case 7, 31:
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
