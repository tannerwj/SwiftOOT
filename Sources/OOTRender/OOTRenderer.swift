import Foundation
import Metal
import MetalKit
import OOTDataModel
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
    private let fallbackTexture: MTLTexture
    let vertexDescriptor: MTLVertexDescriptor

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
            named: "oot_combiner_fragment",
            in: library
        )
        let vertexDescriptor = makeN64VertexDescriptor()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "OOTRenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.device = device
        self.commandQueue = commandQueue
        self.fallbackTexture = try Self.makeFallbackTexture(device: device)
        self.vertexDescriptor = vertexDescriptor
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

        encodeFrame(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            vertices: Self.defaultTriangleVertices,
            frameUniforms: Self.defaultFrameUniforms,
            combinerUniforms: CombinerUniforms()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func renderToTexture(_ texture: MTLTexture) {
        renderToTexture(
            texture,
            vertices: Self.defaultTriangleVertices,
            frameUniforms: Self.defaultFrameUniforms
        )
    }

    func renderToTexture(
        _ texture: MTLTexture,
        frameUniforms: FrameUniforms,
        combinerUniforms: CombinerUniforms = CombinerUniforms()
    ) {
        renderToTexture(
            texture,
            vertices: Self.defaultTriangleVertices,
            frameUniforms: frameUniforms,
            combinerUniforms: combinerUniforms
        )
    }

    func renderToTexture(
        _ texture: MTLTexture,
        vertices: [N64Vertex],
        frameUniforms: FrameUniforms,
        combinerUniforms: CombinerUniforms = CombinerUniforms(),
        texel0Texture: MTLTexture? = nil,
        texel1Texture: MTLTexture? = nil
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = Self.clearColor

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        encodeFrame(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            vertices: vertices,
            frameUniforms: frameUniforms,
            combinerUniforms: combinerUniforms,
            texel0Texture: texel0Texture,
            texel1Texture: texel1Texture
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    static func makeLibrary(
        device: MTLDevice,
        bundle: Bundle
    ) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: bundle) {
            return library
        }

        guard let library = device.makeDefaultLibrary() else {
            let shaderSourceURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("OOTShaders.metal")

            guard let shaderSource = try? String(contentsOf: shaderSourceURL) else {
                throw OOTRendererError.shaderLibraryUnavailable
            }

            return try device.makeLibrary(source: shaderSource, options: nil)
        }

        return library
    }

    static func makeFunction(
        named name: String,
        in library: MTLLibrary
    ) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw OOTRendererError.shaderFunctionUnavailable(name: name)
        }

        return function
    }

    private static func makeFallbackTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw OOTRendererError.metalUnavailable
        }

        var texel = [UInt8](repeating: 0, count: 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &texel,
            bytesPerRow: 4
        )
        return texture
    }

    private func encodeFrame(
        with commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        vertices: [N64Vertex],
        frameUniforms: FrameUniforms,
        combinerUniforms: CombinerUniforms,
        texel0Texture: MTLTexture? = nil,
        texel1Texture: MTLTexture? = nil
    ) {
        guard !vertices.isEmpty else {
            return
        }

        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return
        }

        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }

            renderCommandEncoder.setVertexBytes(
                baseAddress,
                length: bytes.count,
                index: OOTRenderBufferIndex.vertices.rawValue
            )
        }

        var frameUniforms = frameUniforms
        renderCommandEncoder.setVertexBytes(
            &frameUniforms,
            length: MemoryLayout<FrameUniforms>.stride,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )

        var combinerUniforms = combinerUniforms
        renderCommandEncoder.setVertexBytes(
            &combinerUniforms,
            length: MemoryLayout<CombinerUniforms>.stride,
            index: OOTRenderBufferIndex.combinerUniforms.rawValue
        )
        renderCommandEncoder.setFragmentBytes(
            &combinerUniforms,
            length: MemoryLayout<CombinerUniforms>.stride,
            index: OOTRenderBufferIndex.combinerUniforms.rawValue
        )
        renderCommandEncoder.setFragmentTexture(
            texel0Texture ?? fallbackTexture,
            index: OOTRenderTextureIndex.texel0.rawValue
        )
        renderCommandEncoder.setFragmentTexture(
            texel1Texture ?? fallbackTexture,
            index: OOTRenderTextureIndex.texel1.rawValue
        )
        renderCommandEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: vertices.count
        )
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

        return Bundle(for: BundleToken.self)
    }
}

private final class BundleToken {}

private extension OOTRenderer {
    static let defaultTriangleVertices: [N64Vertex] = [
        N64Vertex(
            position: Vector3s(x: -1, y: -1, z: 0),
            flag: 0,
            textureCoordinate: Vector2s(x: 0, y: 0),
            colorOrNormal: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
        ),
        N64Vertex(
            position: Vector3s(x: 1, y: -1, z: 0),
            flag: 0,
            textureCoordinate: Vector2s(x: 32, y: 0),
            colorOrNormal: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
        ),
        N64Vertex(
            position: Vector3s(x: 0, y: 1, z: 0),
            flag: 0,
            textureCoordinate: Vector2s(x: 16, y: 32),
            colorOrNormal: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
        ),
    ]

    static let defaultFrameUniforms = FrameUniforms(
        mvp: simd_float4x4(diagonal: SIMD4<Float>(0.5, 0.5, 1.0, 1.0))
    )
}

enum OOTRenderTextureIndex: Int {
    case texel0 = 0
    case texel1 = 1
}
