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
    public var pipelineStateCount: Int
    public var textureMemoryBytes: Int
    public var cpuRenderTimeMilliseconds: Double

    public init(
        roomCount: Int = 0,
        vertexCount: Int = 0,
        triangleCount: Int = 0,
        drawCallCount: Int = 0,
        pipelineStateCount: Int = 0,
        textureMemoryBytes: Int = 0,
        cpuRenderTimeMilliseconds: Double = 0
    ) {
        self.roomCount = roomCount
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.drawCallCount = drawCallCount
        self.pipelineStateCount = pipelineStateCount
        self.textureMemoryBytes = textureMemoryBytes
        self.cpuRenderTimeMilliseconds = cpuRenderTimeMilliseconds
    }
}

public struct RenderedSceneCapture: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixelsBGRA: [UInt8]
    public var frameStats: SceneFrameStats

    public init(
        width: Int,
        height: Int,
        pixelsBGRA: [UInt8],
        frameStats: SceneFrameStats
    ) {
        self.width = width
        self.height = height
        self.pixelsBGRA = pixelsBGRA
        self.frameStats = frameStats
    }
}

private struct XRayDebugVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

struct XRayOverlayPassStats {
    var drawCallCount: Int = 0
    var triangleCount: Int = 0
}

struct CachedSceneRenderTargets {
    var size: SIMD2<Int>
    var colorPixelFormat: MTLPixelFormat
    var colorTexture: MTLTexture
    var depthTexture: MTLTexture
}

struct SceneRenderPipelineKey: Hashable {
    var renderStateKey: RenderStateKey
    var colorPixelFormat: MTLPixelFormat
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
    private let xrayDebugPipelineState: MTLRenderPipelineState
    private let postProcessPipelineState: MTLComputePipelineState
    private let shaderBundle: Bundle
    public let sceneBounds: SceneBounds
    let vertexDescriptor: MTLVertexDescriptor
    let orbitCameraController: OrbitCameraController
    let gameplayCameraController: GameplayCameraController?

    private var renderScene: OOTRenderScene
    private var textureBindings: [UInt32: MTLTexture]
    private let fallbackTexture: MTLTexture
    private let opaqueDepthStencilState: MTLDepthStencilState
    private let translucentDepthStencilState: MTLDepthStencilState
    private let skyboxDepthStencilState: MTLDepthStencilState
    private let sceneVertices: [N64Vertex]
    private let inFlightSemaphore = DispatchSemaphore(value: OOTRenderer.inFlightFrameCount)
    private var environmentRenderer: EnvironmentRenderer

    private var frameUniformBuffers: [MTLBuffer]
    private var frameUniformBufferIndex = 0
    private var renderPipelineCache: [SceneRenderPipelineKey: MTLRenderPipelineState]
    private var frameStatsHandler: (SceneFrameStats) -> Void
    private(set) var isDebugCameraEnabled = false
    private var frameTickHandler: @MainActor () -> Void
    private var timeOfDay: Double
    private let nearestTextureSamplerState: MTLSamplerState
    private let linearTextureSamplerState: MTLSamplerState
    private var renderSettings: RenderSettings
    private var presentationFrameIndex: UInt32 = 0
    private(set) var currentOutputMode: RenderOutputMode = .standardDynamicRange
    private var currentOutputTargetCapabilities = RenderOutputTargetCapabilities()
    private var cachedSceneRenderTargets: CachedSceneRenderTargets?
    private var sceneRenderPipelineStates: [MTLPixelFormat: MTLRenderPipelineState]
    private var xrayDebugPipelineStates: [MTLPixelFormat: MTLRenderPipelineState]

    public init(
        bundle: Bundle = resourceBundle,
        sceneVertices: [N64Vertex]? = nil,
        scene: OOTRenderScene? = nil,
        textureBindings: [UInt32: MTLTexture] = [:],
        renderSettings: RenderSettings = RenderSettings(),
        gameplayCameraConfiguration: GameplayCameraConfiguration? = nil,
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in },
        frameTickHandler: @escaping @MainActor () -> Void = {}
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
        let xrayDebugVertexFunction = try Self.makeFunction(
            named: "oot_xray_debug_vertex",
            in: library
        )
        let flatColorFragmentFunction = try Self.makeFunction(
            named: "oot_flat_color_fragment",
            in: library
        )
        let postProcessFunction = try Self.makeFunction(
            named: "oot_post_process",
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
        let skyboxDepthStencilState = try Self.makeDepthStencilState(
            device: device,
            compareFunction: .always,
            depthWriteEnabled: false,
            label: "OOTDepthSkybox"
        )
        let frameUniformBuffers = try Self.makeFrameUniformBuffers(device: device)
        let sceneBounds = renderScene.sceneBounds

        self.device = device
        self.commandQueue = commandQueue
        self.shaderBundle = bundle
        self.renderScene = renderScene
        self.textureBindings = textureBindings
        self.sceneVertices = sceneVertices
        self.sceneBounds = sceneBounds
        self.vertexDescriptor = vertexDescriptor
        self.orbitCameraController = OrbitCameraController(sceneBounds: sceneBounds)
        self.gameplayCameraController = gameplayCameraConfiguration.map {
            GameplayCameraController(sceneBounds: sceneBounds, configuration: $0)
        }
        self.fallbackTexture = fallbackTexture
        self.opaqueDepthStencilState = opaqueDepthStencilState
        self.translucentDepthStencilState = translucentDepthStencilState
        self.skyboxDepthStencilState = skyboxDepthStencilState
        self.frameUniformBuffers = frameUniformBuffers
        self.renderPipelineCache = [:]
        self.sceneRenderPipelineStates = [:]
        self.xrayDebugPipelineStates = [:]
        self.frameStatsHandler = frameStatsHandler
        self.frameTickHandler = frameTickHandler
        self.environmentRenderer = EnvironmentRenderer(environment: renderScene.environment)
        self.timeOfDay = 6.0
        self.renderSettings = renderSettings
        self.renderPipelineState = try device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        )
        self.xrayDebugPipelineState = try Self.makeXRayDebugPipelineState(
            device: device,
            vertexFunction: xrayDebugVertexFunction,
            fragmentFunction: flatColorFragmentFunction
        )
        self.postProcessPipelineState = try device.makeComputePipelineState(
            function: postProcessFunction
        )
        self.nearestTextureSamplerState = try Self.makeTextureSamplerState(
            device: device,
            filter: .nearest,
            maxAnisotropy: 1,
            label: "OOTTextureNearest"
        )
        self.linearTextureSamplerState = try Self.makeTextureSamplerState(
            device: device,
            filter: .linear,
            maxAnisotropy: 8,
            label: "OOTTextureLinear"
        )
        super.init()
    }

    @MainActor
    public func configure(_ view: MTKView) {
        view.device = device
        view.depthStencilPixelFormat = Self.depthPixelFormat
        view.clearColor = clearColorForCurrentEnvironment()
        view.preferredFramesPerSecond = Self.preferredFramesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.delegate = self
        refreshPresentationConfiguration(for: view)
        orbitCameraController.updateViewportSize(view.drawableSize)
        gameplayCameraController?.updateViewportSize(view.drawableSize)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        orbitCameraController.updateViewportSize(size)
        gameplayCameraController?.updateViewportSize(size)
    }

    public func setFrameStatsHandler(_ handler: @escaping (SceneFrameStats) -> Void) {
        frameStatsHandler = handler
    }

    public func setFrameTickHandler(_ handler: @escaping @MainActor () -> Void) {
        frameTickHandler = handler
    }

    public func updateScene(_ scene: OOTRenderScene, textureBindings: [UInt32: MTLTexture]) {
        renderScene = scene
        self.textureBindings = textureBindings
        environmentRenderer = EnvironmentRenderer(environment: scene.environment)
    }

    public func updateGameplayCameraConfiguration(_ configuration: GameplayCameraConfiguration?) {
        guard let gameplayCameraController, let configuration else {
            return
        }

        gameplayCameraController.updateConfiguration(configuration)
    }

    public func updateRenderSettings(_ settings: RenderSettings) {
        renderSettings = settings
    }

    public var currentRenderSettings: RenderSettings {
        renderSettings
    }

    public func toggleDebugCamera() {
        guard gameplayCameraController != nil else {
            return
        }

        isDebugCameraEnabled.toggle()
    }

    public func handlePrimaryDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isDebugCameraEnabled else {
            return
        }

        orbitCameraController.orbit(deltaX: deltaX, deltaY: deltaY)
    }

    public func handleSecondaryDrag(deltaX: CGFloat, deltaY: CGFloat) {
        if isDebugCameraEnabled || gameplayCameraController == nil {
            orbitCameraController.pan(deltaX: deltaX, deltaY: deltaY)
            return
        }

        gameplayCameraController?.orbit(deltaX: deltaX, deltaY: deltaY)
    }

    public func handleScroll(scrollDeltaY: CGFloat) {
        guard isDebugCameraEnabled || gameplayCameraController == nil else {
            return
        }

        orbitCameraController.zoom(scrollDeltaY: scrollDeltaY)
    }

    public func handlePan(direction: OrbitPanDirection) {
        guard isDebugCameraEnabled || gameplayCameraController == nil else {
            return
        }

        orbitCameraController.pan(direction: direction)
    }

    public func snapGameplayCameraBehindPlayer() {
        guard isDebugCameraEnabled == false else {
            return
        }

        gameplayCameraController?.snapBehindPlayer()
    }

    public func setTimeOfDay(_ timeOfDay: Double) {
        self.timeOfDay = timeOfDay
    }

    public func currentGameplayMovementYaw() -> Float? {
        guard isDebugCameraEnabled == false else {
            return nil
        }

        return gameplayCameraController?.movementReferenceYaw
    }

    public func clearColorForCurrentEnvironment() -> MTLClearColor {
        guard renderScene.environment != nil else {
            return clearColor(for: renderScene.skyColor)
        }
        let environmentState = environmentRenderer.currentState(timeOfDay: timeOfDay)
        return clearColor(for: environmentState.skyColor)
    }

    public func draw(in view: MTKView) {
        inFlightSemaphore.wait()

        guard
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        MainActor.assumeIsolated {
            frameTickHandler()
        }
        let renderStartUptime = DispatchTime.now().uptimeNanoseconds
        do {
            let frameStats = try renderPresentedScene(
                with: commandBuffer,
                destinationTexture: drawable.texture,
                destinationSize: view.drawableSize,
                outputMode: currentOutputMode,
                edrHeadroom: currentOutputTargetCapabilities.maximumPotentialEDRComponentValue,
                renderStartUptime: renderStartUptime
            )
            frameStatsHandler(frameStats)
            commandBuffer.present(drawable)
            commandBuffer.commit()
            presentationFrameIndex &+= 1
        } catch {
            commandBuffer.commit()
        }
    }

    public func captureCurrentScene(size: CGSize) throws -> RenderedSceneCapture {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        textureDescriptor.storageMode = .shared

        guard let renderTarget = device.makeTexture(descriptor: textureDescriptor) else {
            throw OOTRendererError.metalUnavailable
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw OOTRendererError.metalUnavailable
        }

        let capturedStats = try renderPresentedScene(
            with: commandBuffer,
            destinationTexture: renderTarget,
            destinationSize: CGSize(width: width, height: height),
            outputMode: .standardDynamicRange,
            edrHeadroom: 1.0,
            renderStartUptime: DispatchTime.now().uptimeNanoseconds
        )
        frameStatsHandler(capturedStats)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        renderTarget.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        return RenderedSceneCapture(
            width: width,
            height: height,
            pixelsBGRA: pixels,
            frameStats: capturedStats
        )
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
        renderPassDescriptor.colorAttachments[0].clearColor = clearColorForCurrentEnvironment()

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
        frameUniforms: FrameUniforms = FrameUniforms.identity,
        skyboxViewProjection: simd_float4x4? = nil
    ) throws {
        inFlightSemaphore.wait()
        defer { inFlightSemaphore.signal() }

        let frameUniforms = frameUniforms.withEnvironment(
            environmentRenderer.currentState(timeOfDay: timeOfDay)
        )

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColorForCurrentEnvironment()
        renderPassDescriptor.depthAttachment.texture = try makeDepthTexture(
            width: texture.width,
            height: texture.height
        )
        configureDepthAttachment(for: renderPassDescriptor)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        advanceFrameUniformBuffer(with: frameUniforms)
        var frameStats = try encodeSceneFrame(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewportSize: CGSize(width: texture.width, height: texture.height),
            frameUniforms: frameUniforms,
            colorPixelFormat: texture.pixelFormat,
            skyboxViewProjection: skyboxViewProjection,
            renderStartUptime: DispatchTime.now().uptimeNanoseconds
        )
        if
            let colorTexture = renderPassDescriptor.colorAttachments[0].texture,
            let xrayDebugScene = renderScene.xrayDebugScene,
            xrayDebugScene.isEmpty == false
        {
            let overlayStats = try encodeXRayOverlayPass(
                with: commandBuffer,
                colorTexture: colorTexture,
                viewportSize: CGSize(width: texture.width, height: texture.height),
                frameUniforms: frameUniforms,
                colorPixelFormat: texture.pixelFormat,
                xrayDebugScene: xrayDebugScene
            )
            frameStats.drawCallCount += overlayStats.drawCallCount
            frameStats.triangleCount += overlayStats.triangleCount
        }
        frameStatsHandler(frameStats)
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
        try renderPipelineState(for: key, colorPixelFormat: .bgra8Unorm)
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

    private static func makeXRayDebugPipelineState(
        device: MTLDevice,
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "OOTXRayDebugPipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = makeXRayDebugVertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeTextureSamplerState(
        device: MTLDevice,
        filter: MTLSamplerMinMagFilter,
        maxAnisotropy: Int,
        label: String
    ) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = label
        descriptor.minFilter = filter
        descriptor.magFilter = filter
        descriptor.mipFilter = .notMipmapped
        descriptor.maxAnisotropy = max(maxAnisotropy, 1)
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge

        guard let state = device.makeSamplerState(descriptor: descriptor) else {
            throw OOTRendererError.metalUnavailable
        }

        return state
    }
}

extension OOTRenderer {
    func skyboxViewProjection(from cameraMatrices: CameraMatrices) -> simd_float4x4 {
        makeSkyboxViewProjection(from: cameraMatrices)
    }
}

extension OOTRenderer {
    func encodeSceneFrame(
        with commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewportSize: CGSize,
        frameUniforms: FrameUniforms,
        colorPixelFormat: MTLPixelFormat,
        skyboxViewProjection: simd_float4x4? = nil,
        renderStartUptime: UInt64
    ) throws -> SceneFrameStats {
        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return SceneFrameStats()
        }
        defer {
            renderCommandEncoder.endEncoding()
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
        renderCommandEncoder.setVertexBuffer(
            currentFrameUniformBuffer,
            offset: 0,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )
        renderCommandEncoder.setFragmentBuffer(
            currentFrameUniformBuffer,
            offset: 0,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )
        renderCommandEncoder.setFragmentSamplerState(
            textureSamplerState(
                for: renderSettings.presentationMode == .enhanced ? .linear : .nearest
            ),
            index: OOTRenderSamplerIndex.texel.rawValue
        )
        encodeSkyboxIfNeeded(
            with: renderCommandEncoder,
            frameUniforms: frameUniforms,
            colorPixelFormat: colorPixelFormat,
            skyboxViewProjection: skyboxViewProjection
        )
        let drawBatchResources = makeDrawBatchResources(colorPixelFormat: colorPixelFormat)
        let environmentState = environmentRenderer.currentState(timeOfDay: timeOfDay)

        var frameStats = SceneFrameStats(
            roomCount: renderScene.visibleRooms.count,
            pipelineStateCount: cachedRenderPipelineStateCount + 1,
            textureMemoryBytes: estimatedTextureMemoryBytes()
        )

        for room in renderScene.visibleRooms {
            let interpreter = F3DEX2Interpreter(
                segmentTable: makeSegmentTable(for: room),
                projectionMatrix: frameUniforms.mvp,
                drawBatchResources: drawBatchResources,
                environmentFogColor: environmentState.fogColor,
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
                projectionMatrix: frameUniforms.mvp,
                environmentFogColor: environmentState.fogColor
            )
        }

        let renderEndUptime = DispatchTime.now().uptimeNanoseconds
        frameStats.cpuRenderTimeMilliseconds = Double(renderEndUptime - renderStartUptime) / 1_000_000
        return frameStats
    }

    func encodeXRayOverlayPass(
        with commandBuffer: MTLCommandBuffer,
        colorTexture: MTLTexture,
        viewportSize: CGSize,
        frameUniforms: FrameUniforms,
        colorPixelFormat: MTLPixelFormat,
        xrayDebugScene: XRayDebugScene
    ) throws -> XRayOverlayPassStats {
        var lineSegments = xrayDebugScene.lineSegments
        if let frustumColor = xrayDebugScene.cameraFrustumColor {
            lineSegments.append(
                contentsOf: makeCameraFrustumLineSegments(
                    inverseViewProjection: simd_inverse(frameUniforms.mvp),
                    color: frustumColor
                )
            )
        }

        let lineVertices = lineSegments.flatMap { segment in
            [
                XRayDebugVertex(position: segment.start, color: segment.color),
                XRayDebugVertex(position: segment.end, color: segment.color),
            ]
        }
        let triangleVertices = xrayDebugScene.filledTriangles.flatMap { triangle in
            [
                XRayDebugVertex(position: triangle.a, color: triangle.color),
                XRayDebugVertex(position: triangle.b, color: triangle.color),
                XRayDebugVertex(position: triangle.c, color: triangle.color),
            ]
        }

        guard lineVertices.isEmpty == false || triangleVertices.isEmpty == false else {
            return XRayOverlayPassStats()
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return XRayOverlayPassStats()
        }
        defer {
            renderCommandEncoder.endEncoding()
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
        renderCommandEncoder.setRenderPipelineState(
            try xrayDebugPipelineState(for: colorPixelFormat)
        )
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setVertexBuffer(
            currentFrameUniformBuffer,
            offset: 0,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )

        var stats = XRayOverlayPassStats()

        if lineVertices.isEmpty == false {
            let bufferLength = MemoryLayout<XRayDebugVertex>.stride * lineVertices.count
            guard let lineBuffer = device.makeBuffer(bytes: lineVertices, length: bufferLength) else {
                throw OOTRendererError.metalUnavailable
            }
            renderCommandEncoder.setVertexBuffer(
                lineBuffer,
                offset: 0,
                index: OOTRenderBufferIndex.vertices.rawValue
            )
            renderCommandEncoder.drawPrimitives(
                type: .line,
                vertexStart: 0,
                vertexCount: lineVertices.count
            )
            stats.drawCallCount += 1
        }

        if triangleVertices.isEmpty == false {
            let bufferLength = MemoryLayout<XRayDebugVertex>.stride * triangleVertices.count
            guard let triangleBuffer = device.makeBuffer(bytes: triangleVertices, length: bufferLength) else {
                throw OOTRendererError.metalUnavailable
            }
            renderCommandEncoder.setVertexBuffer(
                triangleBuffer,
                offset: 0,
                index: OOTRenderBufferIndex.vertices.rawValue
            )
            renderCommandEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: triangleVertices.count
            )
            stats.drawCallCount += 1
            stats.triangleCount += triangleVertices.count / 3
        }

        return stats
    }

    func estimatedTextureMemoryBytes() -> Int {
        textureBindings.values.reduce(0) { partialResult, texture in
            partialResult + estimatedTextureMemoryBytes(for: texture)
        }
    }

    func estimatedTextureMemoryBytes(for texture: MTLTexture) -> Int {
        let bytesPerPixel: Int

        switch texture.pixelFormat {
        case .a8Unorm,
             .r8Unorm,
             .r8Uint,
             .r8Sint:
            bytesPerPixel = 1
        case .rg8Unorm,
             .rg8Uint,
             .rg8Sint:
            bytesPerPixel = 2
        case .rgba16Unorm,
             .rgba16Uint,
             .rgba16Sint,
             .rgba16Float,
             .depth32Float:
            bytesPerPixel = 8
        case .rgba32Float:
            bytesPerPixel = 16
        default:
            bytesPerPixel = 4
        }

        var totalBytes = 0
        let arrayLength = max(texture.arrayLength, 1)
        let sampleCount = max(texture.sampleCount, 1)

        for level in 0..<max(texture.mipmapLevelCount, 1) {
            let width = max(texture.width >> level, 1)
            let height = max(texture.height >> level, 1)
            let depth = max(texture.depth >> level, 1)
            totalBytes += width * height * depth * bytesPerPixel * arrayLength * sampleCount
        }

        return totalBytes
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
        renderCommandEncoder.setFragmentBuffer(
            currentFrameUniformBuffer,
            offset: 0,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )
        renderCommandEncoder.setFragmentSamplerState(
            textureSamplerState(for: renderSettings.presentationMode == .enhanced ? .linear : .nearest),
            index: OOTRenderSamplerIndex.texel.rawValue
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

    func encodeSkyboxIfNeeded(
        with renderCommandEncoder: MTLRenderCommandEncoder,
        frameUniforms: FrameUniforms,
        colorPixelFormat: MTLPixelFormat,
        skyboxViewProjection: simd_float4x4?
    ) {
        let selector = SceneSkyboxSelector(skybox: renderScene.environment?.resolvedSkybox)
        guard let selection = selector.selection(timeOfDay: timeOfDay) else {
            return
        }

        var skyboxFrameUniforms = FrameUniforms(
            mvp: skyboxViewProjection ?? frameUniforms.mvp
        )
        var combinerUniforms = Self.skyboxCombinerUniforms

        guard let pipelineState = try? sceneRenderPipelineState(for: colorPixelFormat) else {
            return
        }

        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setDepthStencilState(skyboxDepthStencilState)
        renderCommandEncoder.setVertexBytes(
            &skyboxFrameUniforms,
            length: MemoryLayout<FrameUniforms>.stride,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )
        renderCommandEncoder.setFragmentBytes(
            &skyboxFrameUniforms,
            length: MemoryLayout<FrameUniforms>.stride,
            index: OOTRenderBufferIndex.frameUniforms.rawValue
        )
        renderCommandEncoder.setFragmentSamplerState(
            textureSamplerState(
                for: renderSettings.presentationMode == .enhanced ? .linear : .nearest
            ),
            index: OOTRenderSamplerIndex.texel.rawValue
        )
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
            fallbackTexture,
            index: OOTRenderTextureIndex.texel1.rawValue
        )

        for face in Self.skyboxFaceDrawOrder {
            guard
                let assetID = selection.assetIDsByFace[face],
                let texture = textureBindings[assetID]
            else {
                continue
            }

            let vertices = Self.skyboxVertices(for: face)
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
            renderCommandEncoder.setFragmentTexture(
                texture,
                index: OOTRenderTextureIndex.texel0.rawValue
            )
            renderCommandEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: vertices.count
            )
        }
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

    func makeDrawBatchResources(colorPixelFormat: MTLPixelFormat) -> DrawBatchResources {
        let opaqueDepthStencilState = self.opaqueDepthStencilState
        return DrawBatchResources(
            device: device,
            pipelineLookup: AnyRenderPipelineStateLookup { [weak self] key in
                guard let self else {
                    throw OOTRendererError.metalUnavailable
                }
                return try self.renderPipelineState(for: key, colorPixelFormat: colorPixelFormat)
            },
            depthStencilLookup: AnyDepthStencilStateLookup { [weak self] key in
                self?.depthStencilState(for: key) ?? opaqueDepthStencilState
            },
            fallbackTexture: fallbackTexture
        )
    }

    func renderPipelineState(
        for key: RenderStateKey,
        colorPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let pipelineKey = SceneRenderPipelineKey(
            renderStateKey: key,
            colorPixelFormat: colorPixelFormat
        )
        if let pipelineState = renderPipelineCache[pipelineKey] {
            return pipelineState
        }

        let pipelineState = try makeDrawBatchPipelineState(
            device: device,
            colorPixelFormat: colorPixelFormat,
            renderStateKey: key
        )
        renderPipelineCache[pipelineKey] = pipelineState
        return pipelineState
    }

    func renderPresentedScene(
        with commandBuffer: MTLCommandBuffer,
        destinationTexture: MTLTexture,
        destinationSize: CGSize,
        outputMode: RenderOutputMode,
        edrHeadroom: Float,
        renderStartUptime: UInt64
    ) throws -> SceneFrameStats {
        let parameters = presentationParameters(
            for: destinationSize,
            outputMode: outputMode,
            edrHeadroom: edrHeadroom
        )
        let sceneViewportSize = CGSize(
            width: parameters.sceneRenderSize.x,
            height: parameters.sceneRenderSize.y
        )
        orbitCameraController.updateViewportSize(sceneViewportSize)
        gameplayCameraController?.updateViewportSize(sceneViewportSize)

        let cameraMatrices = activeCameraMatrices()
        let frameUniforms = frameUniforms(
            for: parameters,
            cameraMatrices: cameraMatrices
        )
        advanceFrameUniformBuffer(with: frameUniforms)

        let sceneTargets = try sceneRenderTargets(
            for: parameters.sceneRenderSize,
            colorPixelFormat: parameters.sceneColorPixelFormat
        )
        let renderPassDescriptor = sceneRenderPassDescriptor(
            colorTexture: sceneTargets.colorTexture,
            depthTexture: sceneTargets.depthTexture
        )

        var frameStats = try encodeSceneFrame(
            with: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            viewportSize: sceneViewportSize,
            frameUniforms: frameUniforms,
            colorPixelFormat: parameters.sceneColorPixelFormat,
            skyboxViewProjection: makeSkyboxViewProjection(from: cameraMatrices),
            renderStartUptime: renderStartUptime
        )

        if
            let xrayDebugScene = renderScene.xrayDebugScene,
            xrayDebugScene.isEmpty == false
        {
            let overlayStats = try encodeXRayOverlayPass(
                with: commandBuffer,
                colorTexture: sceneTargets.colorTexture,
                viewportSize: sceneViewportSize,
                frameUniforms: frameUniforms,
                colorPixelFormat: parameters.sceneColorPixelFormat,
                xrayDebugScene: xrayDebugScene
            )
            frameStats.drawCallCount += overlayStats.drawCallCount
            frameStats.triangleCount += overlayStats.triangleCount
        }

        try encodePostProcessPass(
            with: commandBuffer,
            sourceTexture: sceneTargets.colorTexture,
            destinationTexture: destinationTexture,
            parameters: parameters
        )
        return frameStats
    }

    func presentationParameters(
        for destinationSize: CGSize,
        outputMode: RenderOutputMode,
        edrHeadroom: Float
    ) -> RenderPresentationParameters {
        let destination = SIMD2<Int>(
            max(Int(destinationSize.width.rounded(.up)), 1),
            max(Int(destinationSize.height.rounded(.up)), 1)
        )
        switch renderSettings.presentationMode {
        case .n64Aesthetic:
            let jitterSequence: [SIMD2<Float>] = [
                SIMD2<Float>(0.25, -0.25),
                SIMD2<Float>(-0.25, 0.25),
                SIMD2<Float>(-0.25, -0.25),
                SIMD2<Float>(0.25, 0.25),
            ]
            let jitter = jitterSequence[Int(presentationFrameIndex % UInt32(jitterSequence.count))]
            return RenderPresentationParameters(
                presentationMode: .n64Aesthetic,
                outputMode: .standardDynamicRange,
                sceneRenderSize: RenderPresentationParameters.n64RenderSize,
                destinationSize: destination,
                sceneColorPixelFormat: .bgra8Unorm,
                textureSamplerMode: .nearest,
                depthQuantizationSteps: 2048,
                subpixelJitter: jitter / SIMD2<Float>(320, 240)
            )
        case .enhanced:
            return RenderPresentationParameters(
                presentationMode: .enhanced,
                outputMode: outputMode,
                sceneRenderSize: destination,
                destinationSize: destination,
                sceneColorPixelFormat: sceneColorPixelFormat(for: outputMode),
                textureSamplerMode: .linear,
                edrHeadroom: outputMode == .extendedDynamicRange ? edrHeadroom : 1.0
            )
        }
    }

    func frameUniforms(
        for parameters: RenderPresentationParameters,
        cameraMatrices: CameraMatrices
    ) -> FrameUniforms {
        FrameUniforms(
            mvp: cameraMatrices.viewProjectionMatrix,
            renderTweaks: SIMD4<Float>(
                parameters.depthQuantizationSteps,
                parameters.subpixelJitter.x,
                parameters.subpixelJitter.y,
                0.0
            )
        )
        .withEnvironment(environmentRenderer.currentState(timeOfDay: timeOfDay))
    }

    func sceneRenderTargets(
        for size: SIMD2<Int>,
        colorPixelFormat: MTLPixelFormat
    ) throws -> CachedSceneRenderTargets {
        if
            let cachedSceneRenderTargets,
            cachedSceneRenderTargets.size == size,
            cachedSceneRenderTargets.colorPixelFormat == colorPixelFormat
        {
            return cachedSceneRenderTargets
        }

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private

        guard let colorTexture = device.makeTexture(descriptor: colorDescriptor) else {
            throw OOTRendererError.metalUnavailable
        }

        let depthTexture = try makeDepthTexture(width: size.x, height: size.y)
        let renderTargets = CachedSceneRenderTargets(
            size: size,
            colorPixelFormat: colorPixelFormat,
            colorTexture: colorTexture,
            depthTexture: depthTexture
        )
        cachedSceneRenderTargets = renderTargets
        return renderTargets
    }

    func sceneRenderPassDescriptor(
        colorTexture: MTLTexture,
        depthTexture: MTLTexture
    ) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColorForCurrentEnvironment()
        renderPassDescriptor.depthAttachment.texture = depthTexture
        configureDepthAttachment(for: renderPassDescriptor)
        return renderPassDescriptor
    }

    func encodePostProcessPass(
        with commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        parameters: RenderPresentationParameters
    ) throws {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw OOTRendererError.metalUnavailable
        }
        defer {
            computeEncoder.endEncoding()
        }

        computeEncoder.setComputePipelineState(postProcessPipelineState)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)

        var uniforms = PostProcessUniforms(
            sourceSize: SIMD2<Float>(
                Float(parameters.sceneRenderSize.x),
                Float(parameters.sceneRenderSize.y)
            ),
            destinationSize: SIMD2<Float>(
                Float(parameters.destinationSize.x),
                Float(parameters.destinationSize.y)
            ),
            subpixelJitter: parameters.presentationMode == .n64Aesthetic ? parameters.subpixelJitter : .zero,
            edgeSoftness: parameters.presentationMode == .n64Aesthetic ? 0.7 : 0.0,
            toneMapExposure: parameters.presentationMode == .enhanced ? 1.15 : 1.0,
            fxaaSpan: parameters.presentationMode == .enhanced ? 1.5 : 0.0,
            presentationMode: parameters.presentationMode,
            outputMode: parameters.outputMode,
            edrHeadroom: parameters.edrHeadroom
        )
        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<PostProcessUniforms>.stride,
            index: 0
        )

        let threadWidth = postProcessPipelineState.threadExecutionWidth
        let threadHeight = max(postProcessPipelineState.maxTotalThreadsPerThreadgroup / threadWidth, 1)
        let threadsPerThreadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let threadsPerGrid = MTLSize(
            width: parameters.destinationSize.x,
            height: parameters.destinationSize.y,
            depth: 1
        )
        computeEncoder.dispatchThreads(
            threadsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
    }

    func textureSamplerState(for mode: TextureSamplerMode) -> MTLSamplerState {
        switch mode {
        case .nearest:
            return nearestTextureSamplerState
        case .linear:
            return linearTextureSamplerState
        }
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

    @MainActor
    func refreshPresentationConfiguration(
        for view: MTKView,
        targetCapabilities: RenderOutputTargetCapabilities? = nil
    ) {
        let targetCapabilities = targetCapabilities ?? presentationTargetCapabilities(
            for: view.window?.screen
        )
        currentOutputTargetCapabilities = targetCapabilities
        currentOutputMode = outputMode(for: targetCapabilities)

        view.colorPixelFormat = drawablePixelFormat(for: currentOutputMode)
        if currentOutputMode == .extendedDynamicRange {
            view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        } else {
            view.colorspace = nil
        }

        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.preferredDynamicRange = currentOutputMode == .extendedDynamicRange
                ? .high
                : .standard
            metalLayer.toneMapMode = currentOutputMode == .extendedDynamicRange
                ? .never
                : .automatic
        }
    }

    func presentationTargetCapabilities(
        for screen: NSScreen?
    ) -> RenderOutputTargetCapabilities {
        RenderOutputTargetCapabilities(
            maximumPotentialEDRComponentValue: Float(
                screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
            )
        )
    }

    func outputMode(
        for targetCapabilities: RenderOutputTargetCapabilities
    ) -> RenderOutputMode {
        guard
            renderSettings.presentationMode == .enhanced,
            targetCapabilities.supportsExtendedDynamicRange
        else {
            return .standardDynamicRange
        }

        return .extendedDynamicRange
    }

    func drawablePixelFormat(for outputMode: RenderOutputMode) -> MTLPixelFormat {
        switch outputMode {
        case .standardDynamicRange:
            return .bgra8Unorm
        case .extendedDynamicRange:
            return .rgba16Float
        }
    }

    func sceneColorPixelFormat(for outputMode: RenderOutputMode) -> MTLPixelFormat {
        switch outputMode {
        case .standardDynamicRange:
            return .bgra8Unorm
        case .extendedDynamicRange:
            return .rgba16Float
        }
    }

    func sceneRenderPipelineState(
        for colorPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        if colorPixelFormat == .bgra8Unorm {
            return renderPipelineState
        }
        if let pipelineState = sceneRenderPipelineStates[colorPixelFormat] {
            return pipelineState
        }

        let library = try Self.makeLibrary(device: device, bundle: shaderBundle)
        let vertexFunction = try Self.makeFunction(named: "oot_passthrough_vertex", in: library)
        let fragmentFunction = try Self.makeFunction(named: "oot_combiner_fragment", in: library)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "OOTRawVertexPipeline-\(colorPixelFormat.rawValue)"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = Self.depthPixelFormat

        let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        sceneRenderPipelineStates[colorPixelFormat] = pipelineState
        return pipelineState
    }

    func xrayDebugPipelineState(
        for colorPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        if colorPixelFormat == .bgra8Unorm {
            return xrayDebugPipelineState
        }
        if let pipelineState = xrayDebugPipelineStates[colorPixelFormat] {
            return pipelineState
        }

        let library = try Self.makeLibrary(device: device, bundle: shaderBundle)
        let vertexFunction = try Self.makeFunction(named: "oot_xray_debug_vertex", in: library)
        let fragmentFunction = try Self.makeFunction(named: "oot_flat_color_fragment", in: library)
        let pipelineState = try Self.makeXRayDebugPipelineState(
            device: device,
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            colorPixelFormat: colorPixelFormat
        )
        xrayDebugPipelineStates[colorPixelFormat] = pipelineState
        return pipelineState
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

    static let skyboxCombinerUniforms = CombinerUniforms(
        cycle1ColorSelectors: SIMD4<UInt32>(
            CombinerSourceSelector.texel0.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.one.rawValue,
            CombinerSourceSelector.zero.rawValue
        ),
        cycle1AlphaSelectors: SIMD4<UInt32>(
            CombinerSourceSelector.texel0.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.one.rawValue,
            CombinerSourceSelector.zero.rawValue
        ),
        cycle2ColorSelectors: SIMD4<UInt32>(
            CombinerSourceSelector.combined.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.one.rawValue,
            CombinerSourceSelector.zero.rawValue
        ),
        cycle2AlphaSelectors: SIMD4<UInt32>(
            CombinerSourceSelector.combined.rawValue,
            CombinerSourceSelector.zero.rawValue,
            CombinerSourceSelector.one.rawValue,
            CombinerSourceSelector.zero.rawValue
        )
    )

    static let skyboxFaceDrawOrder: [SceneSkyboxFace] = [.front, .right, .back, .left, .top]

    func activeCameraMatrices() -> CameraMatrices {
        if let gameplayCameraController, isDebugCameraEnabled == false {
            return gameplayCameraController.cameraMatrices()
        }

        return orbitCameraController.cameraMatrices()
    }

    func activeFrameUniforms() -> FrameUniforms {
        FrameUniforms(mvp: activeCameraMatrices().viewProjectionMatrix)
    }

    func makeSkyboxViewProjection(from cameraMatrices: CameraMatrices) -> simd_float4x4 {
        var rotationOnlyView = cameraMatrices.viewMatrix
        rotationOnlyView.columns.3 = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        return cameraMatrices.projectionMatrix * rotationOnlyView
    }

    func makeCameraFrustumLineSegments(
        inverseViewProjection: simd_float4x4,
        color: SIMD4<Float>
    ) -> [XRayDebugLineSegment] {
        let near0 = unproject(ndc: SIMD3<Float>(-1, -1, -1), inverseViewProjection: inverseViewProjection)
        let near1 = unproject(ndc: SIMD3<Float>(1, -1, -1), inverseViewProjection: inverseViewProjection)
        let near2 = unproject(ndc: SIMD3<Float>(1, 1, -1), inverseViewProjection: inverseViewProjection)
        let near3 = unproject(ndc: SIMD3<Float>(-1, 1, -1), inverseViewProjection: inverseViewProjection)
        let far0 = unproject(ndc: SIMD3<Float>(-1, -1, 1), inverseViewProjection: inverseViewProjection)
        let far1 = unproject(ndc: SIMD3<Float>(1, -1, 1), inverseViewProjection: inverseViewProjection)
        let far2 = unproject(ndc: SIMD3<Float>(1, 1, 1), inverseViewProjection: inverseViewProjection)
        let far3 = unproject(ndc: SIMD3<Float>(-1, 1, 1), inverseViewProjection: inverseViewProjection)

        return [
            XRayDebugLineSegment(start: near0, end: near1, color: color),
            XRayDebugLineSegment(start: near1, end: near2, color: color),
            XRayDebugLineSegment(start: near2, end: near3, color: color),
            XRayDebugLineSegment(start: near3, end: near0, color: color),
            XRayDebugLineSegment(start: far0, end: far1, color: color),
            XRayDebugLineSegment(start: far1, end: far2, color: color),
            XRayDebugLineSegment(start: far2, end: far3, color: color),
            XRayDebugLineSegment(start: far3, end: far0, color: color),
            XRayDebugLineSegment(start: near0, end: far0, color: color),
            XRayDebugLineSegment(start: near1, end: far1, color: color),
            XRayDebugLineSegment(start: near2, end: far2, color: color),
            XRayDebugLineSegment(start: near3, end: far3, color: color),
        ]
    }

    func unproject(
        ndc: SIMD3<Float>,
        inverseViewProjection: simd_float4x4
    ) -> SIMD3<Float> {
        let world = inverseViewProjection * SIMD4<Float>(ndc, 1.0)
        guard abs(world.w) > 0.000_1 else {
            return .zero
        }

        return SIMD3<Float>(world.x / world.w, world.y / world.w, world.z / world.w)
    }

    static func skyboxVertices(for face: SceneSkyboxFace) -> [N64Vertex] {
        let size: Int16 = 64
        switch face {
        case .front:
            return makeSkyboxQuad(
                bottomLeft: (-size, -size, -size),
                bottomRight: (size, -size, -size),
                topRight: (size, size, -size),
                topLeft: (-size, size, -size)
            )
        case .right:
            return makeSkyboxQuad(
                bottomLeft: (size, -size, -size),
                bottomRight: (size, -size, size),
                topRight: (size, size, size),
                topLeft: (size, size, -size)
            )
        case .back:
            return makeSkyboxQuad(
                bottomLeft: (size, -size, size),
                bottomRight: (-size, -size, size),
                topRight: (-size, size, size),
                topLeft: (size, size, size)
            )
        case .left:
            return makeSkyboxQuad(
                bottomLeft: (-size, -size, size),
                bottomRight: (-size, -size, -size),
                topRight: (-size, size, -size),
                topLeft: (-size, size, size)
            )
        case .top:
            return makeSkyboxQuad(
                bottomLeft: (-size, size, size),
                bottomRight: (size, size, size),
                topRight: (size, size, -size),
                topLeft: (-size, size, -size)
            )
        case .bottom:
            return makeSkyboxQuad(
                bottomLeft: (-size, -size, -size),
                bottomRight: (size, -size, -size),
                topRight: (size, -size, size),
                topLeft: (-size, -size, size)
            )
        }
    }

    static func makeSkyboxQuad(
        bottomLeft: (Int16, Int16, Int16),
        bottomRight: (Int16, Int16, Int16),
        topRight: (Int16, Int16, Int16),
        topLeft: (Int16, Int16, Int16)
    ) -> [N64Vertex] {
        [
            skyboxVertex(position: bottomLeft, texCoord: (0, 1)),
            skyboxVertex(position: bottomRight, texCoord: (1, 1)),
            skyboxVertex(position: topRight, texCoord: (1, 0)),
            skyboxVertex(position: bottomLeft, texCoord: (0, 1)),
            skyboxVertex(position: topRight, texCoord: (1, 0)),
            skyboxVertex(position: topLeft, texCoord: (0, 0)),
        ]
    }

    static func skyboxVertex(
        position: (Int16, Int16, Int16),
        texCoord: (Int16, Int16)
    ) -> N64Vertex {
        N64Vertex(
            position: Vector3s(x: position.0, y: position.1, z: position.2),
            flag: 0,
            textureCoordinate: Vector2s(x: texCoord.0, y: texCoord.1),
            colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
        )
    }
}

private final class BundleToken {}

private func makeXRayDebugVertexDescriptor() -> MTLVertexDescriptor {
    let descriptor = MTLVertexDescriptor()
    descriptor.attributes[0].format = .float3
    descriptor.attributes[0].offset = 0
    descriptor.attributes[0].bufferIndex = OOTRenderBufferIndex.vertices.rawValue
    descriptor.attributes[1].format = .float4
    descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
    descriptor.attributes[1].bufferIndex = OOTRenderBufferIndex.vertices.rawValue
    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stride = MemoryLayout<XRayDebugVertex>.stride
    descriptor.layouts[OOTRenderBufferIndex.vertices.rawValue].stepFunction = .perVertex
    return descriptor
}

enum OOTRenderTextureIndex: Int {
    case texel0 = 0
    case texel1 = 1
}
