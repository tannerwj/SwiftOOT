import Foundation
import Metal

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
            return "Native-resolution rendering with smoother filtering, post AA, and EDR output on supported displays."
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

enum RenderOutputMode: UInt32, Sendable, Equatable {
    case standardDynamicRange = 0
    case extendedDynamicRange = 1
}

struct RenderOutputTargetCapabilities: Sendable, Equatable {
    var maximumPotentialEDRComponentValue: Float

    init(maximumPotentialEDRComponentValue: Float = 1.0) {
        self.maximumPotentialEDRComponentValue = max(maximumPotentialEDRComponentValue, 1.0)
    }

    var supportsExtendedDynamicRange: Bool {
        maximumPotentialEDRComponentValue > 1.0
    }
}

struct RenderPresentationParameters: Sendable, Equatable {
    static let n64RenderSize = SIMD2<Int>(320, 240)

    var presentationMode: RenderPresentationMode
    var outputMode: RenderOutputMode
    var sceneRenderSize: SIMD2<Int>
    var destinationSize: SIMD2<Int>
    var sceneColorPixelFormat: MTLPixelFormat
    var textureSamplerMode: TextureSamplerMode
    var depthQuantizationSteps: Float
    var subpixelJitter: SIMD2<Float>
    var edrHeadroom: Float

    init(
        presentationMode: RenderPresentationMode,
        outputMode: RenderOutputMode = .standardDynamicRange,
        sceneRenderSize: SIMD2<Int>,
        destinationSize: SIMD2<Int>,
        sceneColorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        textureSamplerMode: TextureSamplerMode,
        depthQuantizationSteps: Float = 0,
        subpixelJitter: SIMD2<Float> = .zero,
        edrHeadroom: Float = 1.0
    ) {
        self.presentationMode = presentationMode
        self.outputMode = outputMode
        self.sceneRenderSize = sceneRenderSize
        self.destinationSize = destinationSize
        self.sceneColorPixelFormat = sceneColorPixelFormat
        self.textureSamplerMode = textureSamplerMode
        self.depthQuantizationSteps = depthQuantizationSteps
        self.subpixelJitter = subpixelJitter
        self.edrHeadroom = max(edrHeadroom, 1.0)
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
    var outputMode: UInt32
    var edrHeadroom: Float

    init(
        sourceSize: SIMD2<Float>,
        destinationSize: SIMD2<Float>,
        subpixelJitter: SIMD2<Float> = .zero,
        edgeSoftness: Float = 0,
        toneMapExposure: Float = 1.0,
        fxaaSpan: Float = 0,
        presentationMode: RenderPresentationMode,
        outputMode: RenderOutputMode = .standardDynamicRange,
        edrHeadroom: Float = 1.0
    ) {
        self.sourceSize = sourceSize
        self.destinationSize = destinationSize
        self.subpixelJitter = subpixelJitter
        self.edgeSoftness = edgeSoftness
        self.toneMapExposure = toneMapExposure
        self.fxaaSpan = fxaaSpan
        self.presentationMode = presentationMode == .n64Aesthetic ? 0 : 1
        self.outputMode = outputMode.rawValue
        self.edrHeadroom = max(edrHeadroom, 1.0)
    }
}
