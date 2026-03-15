import Dispatch
import Foundation
import Metal
import MetalKit
import OOTDataModel
import simd

public enum OOTRendererError: Error {
    case metalUnavailable
    case shaderLibraryUnavailable
    case shaderFunctionUnavailable(name: String)
    case uniformBufferAllocationFailed(length: Int)
    case depthTextureAllocationFailed(width: Int, height: Int)
}

public struct SceneFrameStats: Sendable, Equatable {
    public var roomCount: Int
    public var vertexCount: Int
    public var triangleCount: Int
    public var drawCallCount: Int

    public init(
        roomCount: Int = 0,
        vertexCount: Int = 0,
        triangleCount: Int = 0,
        drawCallCount: Int = 0
    ) {
        self.roomCount = roomCount
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.drawCallCount = drawCallCount
    }
}

public final class OOTRenderer: NSObject, MTKViewDelegate {
    public static let preferredFramesPerSecond = 60
    public static let depthPixelFormat: MTLPixelFormat = .depth32Float
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

    private static let inFlightFrameCount = 3

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let renderPipelineState: MTLRenderPipelineState
    public let sceneBounds: SceneBounds
    let vertexDescriptor: MTLVertexDescriptor
    let orbitCameraController: OrbitCameraController

    private let renderScene: OOTRenderScene
    private let textureBindings: [UInt32: MTLTexture]
    private let fallbackTexture: MTLTexture
    private let opaqueDepthStencilState: MTLDepthStencilState
    private let translucentDepthStencilState: MTLDepthStencilState
    private let sceneVertices: [N64Vertex]
    private let inFlightSemaphore = DispatchSemaphore(value: OOTRenderer.inFlightFrameCount)

    private var frameUniformBuffers: [MTLBuffer]
    private var frameUniformBufferIndex = 0
    private var renderPipelineCache: [RenderStateKey: MTLRenderPipelineState]
    private var frameStatsHandler: (SceneFrameStats) -> Void

    public init(
        bundle: Bundle = resourceBundle,
        sceneVertices: [N64Vertex]? = nil,
        scene: OOTRenderScene? = nil,
        textureBindings: [UInt32: MTLTexture] = [:],
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) throws {
        let sceneVertices = sceneVertices ?? OOTRenderer.defaultTriangleVertices
        let renderScene = scene ?? OOTRenderScene.syntheticScene(vertices: sceneVertices)

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
        pipelineDescriptor.label = "OOTRawVertexPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = Self.depthPixelFormat

        let fallbackTexture = try Self.makeFallbackTexture(device: device)
        let opaqueDepthStencilState = try Self.makeDepthStencilState(
            device: device,
            compareFunction: .lessEqual,
            depthWriteEnabled: true,
            label: "OOTDepthOpaque"
        )
        let translucentDepthStencilState = try Self.makeDepthStencilState(
            device: device,
            compareFunction: .lessEqual,
            depthWriteEnabled: false,
            label: "OOTDepthTranslucent"
        )
        let frameUniformBuffers = try Self.makeFrameUniformBuffers(device: device)
        let sceneBounds = renderScene.sceneBounds

        self.device = device
        self.commandQueue = commandQueue
        self.renderScene = renderScene
        self.textureBindings = textureBindings
        self.sceneVertices = sceneVertices
        self.sceneBounds = sceneBounds
        self.vertexDescriptor = vertexDescriptor
        self.orbitCameraController = OrbitCameraController(sceneBounds: sceneBounds)
        self.fallbackTexture = fallbackTexture
        self.opaqueDepthStencilState = opaqueDepthStencilState
        self.translucentDepthStencilState = translucentDepthStencilState
        self.frameUniformBuffers = frameUniformBuffers
        self.renderPipelineCache = [:]
        self.frameStatsHandler = frameStatsHandler
        self.renderPipelineState = try device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        )
        super.init()
    }

    @MainActor
    public func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = Self.depthPixelFormat
        view.clearColor = clearColor(for: renderScene.skyColor)
        view.preferredFramesPerSecond = Self.preferredFramesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.delegate = self
        orbitCameraController.updateViewportSize(view.drawableSize)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        orbitCameraController.updateViewportSize(size)
    }

    public func setFrameStatsHandler(_ handler: @escaping (SceneFrameStats) -> Void) {
        frameStatsHandler = handler
    }

    public func draw(in view: MTKView) {
        inFlightSemaphore.wait()

        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        let frameUniforms = orbitCameraController.frameUniforms()
        advanceFrameUniformBuffer(with: frameUniforms)
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor(for: renderScene.skyColor)
        configureDepthAttachment(for: renderPassDescriptor)

        do {
            try encodeSceneFrame(
                with: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                viewportSize: view.drawableSize,
                frameUniforms: frameUniforms
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            commandBuffer.commit()
        }
    }

    func renderToTexture(_ texture: MTLTexture) {
        renderToTexture(
            texture,
            vertices: sceneVertices,
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
            vertices: sceneVertices,
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
        inFlightSemaphore.wait()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = Self.clearColor

        do {
            renderPassDescriptor.depthAttachment.texture = try makeDepthTexture(
                width: texture.width,
                height: texture.height
            )
        } catch {
            inFlightSemaphore.signal()
            return
        }

        configureDepthAttachment(for: renderPassDescriptor)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        advanceFrameUniformBuffer(with: frameUniforms)
        encodeRawVertexFrame(
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

    func renderCurrentSceneToTexture(
        _ texture: MTLTexture,
        frameUniforms: FrameUniforms = FrameUniforms.identity
    ) throws {
        inFlightSemaphore.wait()
        defer { inFlightSemaphore.signal() }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor(for: renderScene.skyColor)
        renderPassDescriptor.depthAttachment.texture = try makeDepthTexture(
            width: texture.width,
            height: texture.height
        )
        configureDepthAttachment(for: renderPassDescriptor)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        advanceFrameUniformBuffer(with: frameUniforms)
        try encodeSceneFrame(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewportSize: CGSize(width: texture.width, height: texture.height),
            frameUniforms: frameUniforms
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    var cachedRenderPipelineStateCount: Int {
        renderPipelineCache.count
    }

    var inFlightUniformBufferCount: Int {
        frameUniformBuffers.count
    }

    func cachedRenderPipelineState(
        for key: RenderStateKey
    ) throws -> MTLRenderPipelineState {
        try renderPipelineState(for: key)
    }

    func depthStencilState(for key: RenderStateKey) -> MTLDepthStencilState {
        key.renderMode.isTranslucent
            ? translucentDepthStencilState
            : opaqueDepthStencilState
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

            guard let shaderSource = try? String(contentsOf: shaderSourceURL, encoding: .utf8) else {
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

    private static func makeDepthStencilState(
        device: MTLDevice,
        compareFunction: MTLCompareFunction,
        depthWriteEnabled: Bool,
        label: String
    ) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = label
        descriptor.depthCompareFunction = compareFunction
        descriptor.isDepthWriteEnabled = depthWriteEnabled

        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw OOTRendererError.metalUnavailable
        }

        return state
    }

    private static func makeFrameUniformBuffers(device: MTLDevice) throws -> [MTLBuffer] {
        try (0..<inFlightFrameCount).map { index in
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<FrameUniforms>.stride,
                options: .storageModeShared
            ) else {
                throw OOTRendererError.uniformBufferAllocationFailed(
                    length: MemoryLayout<FrameUniforms>.stride
                )
            }

            buffer.label = "OOTFrameUniforms-\(index)"
            return buffer
        }
    }
}

private extension OOTRenderer {
    func encodeSceneFrame(
        with commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewportSize: CGSize,
        frameUniforms: FrameUniforms
    ) throws {
        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return
        }

        renderCommandEncoder.setViewport(
            MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(viewportSize.width),
                height: Double(viewportSize.height),
                znear: 0,
                zfar: 1
            )
        )
        renderCommandEncoder.setDepthStencilState(opaqueDepthStencilState)
        let drawBatchResources = makeDrawBatchResources()

        var frameStats = SceneFrameStats(roomCount: renderScene.visibleRooms.count)

        for room in renderScene.visibleRooms {
            let interpreter = F3DEX2Interpreter(
                segmentTable: makeSegmentTable(for: room),
                projectionMatrix: frameUniforms.mvp,
                drawBatchResources: drawBatchResources,
                textureResolver: { [textureBindings] assetID in
                    textureBindings[assetID]
                }
            )
            try interpreter.interpret(room.displayList, encoder: renderCommandEncoder)
            try interpreter.flush(encoder: renderCommandEncoder)
            frameStats.vertexCount += room.vertexCount
            frameStats.triangleCount += interpreter.drawBatch.totalTriangleCount
            frameStats.drawCallCount += interpreter.drawBatch.drawCallCount
        }

        let skelAnimeRenderer = SkelAnimeRenderer(drawBatchResources: drawBatchResources)
        for skeleton in renderScene.skeletons {
            try skelAnimeRenderer.render(
                skeleton,
                encoder: renderCommandEncoder,
                projectionMatrix: frameUniforms.mvp
            )
        }

        renderCommandEncoder.endEncoding()
        frameStatsHandler(frameStats)
    }

    func encodeRawVertexFrame(
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
        renderCommandEncoder.setDepthStencilState(opaqueDepthStencilState)
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

        renderCommandEncoder.setVertexBuffer(
            currentFrameUniformBuffer,
            offset: 0,
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

    func advanceFrameUniformBuffer(with frameUniforms: FrameUniforms) {
        frameUniformBufferIndex = (frameUniformBufferIndex + 1) % frameUniformBuffers.count
        let buffer = currentFrameUniformBuffer
        var frameUniforms = frameUniforms
        memcpy(
            buffer.contents(),
            &frameUniforms,
            MemoryLayout<FrameUniforms>.stride
        )
    }

    var currentFrameUniformBuffer: MTLBuffer {
        frameUniformBuffers[frameUniformBufferIndex]
    }

    func configureDepthAttachment(for renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
    }

    func makeDepthTexture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.depthPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw OOTRendererError.depthTextureAllocationFailed(width: width, height: height)
        }

        return texture
    }

    func makeSegmentTable(for room: OOTRenderRoom) -> SegmentTable {
        var segmentTable = SegmentTable()
        for (segmentID, data) in room.segmentData {
            try? segmentTable.setSegment(segmentID, data: data)
        }
        return segmentTable
    }

    func makeDrawBatchResources() -> DrawBatchResources {
        let opaqueDepthStencilState = self.opaqueDepthStencilState
        return DrawBatchResources(
            device: device,
            pipelineLookup: AnyRenderPipelineStateLookup { [weak self] key in
                guard let self else {
                    throw OOTRendererError.metalUnavailable
                }
                return try self.renderPipelineState(for: key)
            },
            depthStencilLookup: AnyDepthStencilStateLookup { [weak self] key in
                self?.depthStencilState(for: key) ?? opaqueDepthStencilState
            },
            fallbackTexture: fallbackTexture
        )
    }

    func renderPipelineState(
        for key: RenderStateKey
    ) throws -> MTLRenderPipelineState {
        if let pipelineState = renderPipelineCache[key] {
            return pipelineState
        }

        let pipelineState = try makeDrawBatchPipelineState(
            device: device,
            renderStateKey: key
        )
        renderPipelineCache[key] = pipelineState
        return pipelineState
    }

    func clearColor(for skyColor: SIMD4<Float>) -> MTLClearColor {
        MTLClearColor(
            red: Double(skyColor.x),
            green: Double(skyColor.y),
            blue: Double(skyColor.z),
            alpha: Double(skyColor.w)
        )
    }

    static func makeResourceBundle() -> Bundle {
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

private final class BundleToken {}

enum OOTRenderTextureIndex: Int {
    case texel0 = 0
    case texel1 = 1
}
