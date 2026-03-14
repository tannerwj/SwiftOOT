import Foundation
import Metal
import MetalKit
import simd

public enum OOTRendererError: Error {
    case metalUnavailable
    case shaderLibraryUnavailable
    case shaderFunctionUnavailable(name: String)
}

public final class OOTRenderer: NSObject, MTKViewDelegate {
    public static let preferredFramesPerSecond = 60
    public static let zeldaGreen = SIMD4<Float>(
        45.0 / 255.0,
        155.0 / 255.0,
        52.0 / 255.0,
        1.0
    )
    public static let clearColor = MTLClearColor(
        red: Double(zeldaGreen.x),
        green: Double(zeldaGreen.y),
        blue: Double(zeldaGreen.z),
        alpha: Double(zeldaGreen.w)
    )
    public static let resourceBundle = makeResourceBundle()

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let renderPipelineState: MTLRenderPipelineState

    public init(bundle: Bundle = resourceBundle) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OOTRendererError.metalUnavailable
        }

        guard let commandQueue = device.makeCommandQueue() else {
            throw OOTRendererError.metalUnavailable
        }

        let library = try Self.makeLibrary(device: device, bundle: bundle)
        let vertexFunction = try Self.makeFunction(
            named: "oot_passthrough_vertex",
            in: library
        )
        let fragmentFunction = try Self.makeFunction(
            named: "oot_solid_color_fragment",
            in: library
        )
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "OOTRenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.device = device
        self.commandQueue = commandQueue
        self.renderPipelineState = try device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        )
        super.init()
    }

    @MainActor
    public func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = Self.clearColor
        view.preferredFramesPerSecond = Self.preferredFramesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.delegate = self
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        encodeFrame(with: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func renderToTexture(_ texture: MTLTexture) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = Self.clearColor

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        encodeFrame(with: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private static func makeLibrary(
        device: MTLDevice,
        bundle: Bundle
    ) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: bundle) {
            return library
        }

        guard let library = device.makeDefaultLibrary() else {
            throw OOTRendererError.shaderLibraryUnavailable
        }

        return library
    }

    private static func makeFunction(
        named name: String,
        in library: MTLLibrary
    ) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw OOTRendererError.shaderFunctionUnavailable(name: name)
        }

        return function
    }

    private func encodeFrame(
        with commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor
    ) {
        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return
        }

        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderCommandEncoder.endEncoding()
    }

    private static func makeResourceBundle() -> Bundle {
        let bundleName = "SwiftOOT_OOTRender"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleToken.self).resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleToken.self).bundleURL,
        ]

        for candidate in candidates {
            guard let bundleURL = candidate?.appendingPathComponent("\(bundleName).bundle") else {
                continue
            }

            if let bundle = Bundle(url: bundleURL) {
                return bundle
            }
        }

        fatalError("Missing \(bundleName).bundle")
    }
}

private final class BundleToken {}
