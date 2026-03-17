import Foundation

public enum RenderPresentationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case n64Aesthetic
    case enhanced

    public var id: Self { self }

    public var title: String {
        switch self {
        case .n64Aesthetic:
            return "N64 Aesthetic"
        case .enhanced:
            return "Enhanced"
        }
    }

    public var detail: String {
        switch self {
        case .n64Aesthetic:
            return "320x240 offscreen rendering with retro composite treatment."
        case .enhanced:
            return "Native-resolution rendering with smoother filtering and post AA."
        }
    }
}

public struct RenderSettings: Codable, Sendable, Equatable {
    public var presentationMode: RenderPresentationMode

    public init(
        presentationMode: RenderPresentationMode = .n64Aesthetic
    ) {
        self.presentationMode = presentationMode
    }
}

struct RenderPresentationParameters: Sendable, Equatable {
    static let n64RenderSize = SIMD2<Int>(320, 240)

    var presentationMode: RenderPresentationMode
    var sceneRenderSize: SIMD2<Int>
    var destinationSize: SIMD2<Int>
    var textureSamplerMode: TextureSamplerMode
    var depthQuantizationSteps: Float
    var subpixelJitter: SIMD2<Float>

    init(
        presentationMode: RenderPresentationMode,
        sceneRenderSize: SIMD2<Int>,
        destinationSize: SIMD2<Int>,
        textureSamplerMode: TextureSamplerMode,
        depthQuantizationSteps: Float = 0,
        subpixelJitter: SIMD2<Float> = .zero
    ) {
        self.presentationMode = presentationMode
        self.sceneRenderSize = sceneRenderSize
        self.destinationSize = destinationSize
        self.textureSamplerMode = textureSamplerMode
        self.depthQuantizationSteps = depthQuantizationSteps
        self.subpixelJitter = subpixelJitter
    }
}

enum TextureSamplerMode: UInt32, Sendable, Equatable {
    case nearest = 0
    case linear = 1
}

struct PostProcessUniforms: Sendable, Equatable {
    var sourceSize: SIMD2<Float>
    var destinationSize: SIMD2<Float>
    var subpixelJitter: SIMD2<Float>
    var edgeSoftness: Float
    var toneMapExposure: Float
    var fxaaSpan: Float
    var presentationMode: UInt32

    init(
        sourceSize: SIMD2<Float>,
        destinationSize: SIMD2<Float>,
        subpixelJitter: SIMD2<Float> = .zero,
        edgeSoftness: Float = 0,
        toneMapExposure: Float = 1.0,
        fxaaSpan: Float = 0,
        presentationMode: RenderPresentationMode
    ) {
        self.sourceSize = sourceSize
        self.destinationSize = destinationSize
        self.subpixelJitter = subpixelJitter
        self.edgeSoftness = edgeSoftness
        self.toneMapExposure = toneMapExposure
        self.fxaaSpan = fxaaSpan
        self.presentationMode = presentationMode == .n64Aesthetic ? 0 : 1
    }
}
