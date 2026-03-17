import XCTest
import Metal
import OOTDataModel
import simd
@testable import OOTRender

final class OOTRenderTests: XCTestCase {
    func testRendererUsesZeldaGreenClearColor() {
        XCTAssertEqual(OOTRenderer.clearColor.red, 45.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(OOTRenderer.clearColor.green, 155.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(OOTRenderer.clearColor.blue, 52.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(OOTRenderer.clearColor.alpha, 1.0, accuracy: 0.000_1)
    }

    func testRendererTargetsSixtyFramesPerSecond() {
        XCTAssertEqual(OOTRenderer.preferredFramesPerSecond, 60)
    }

    func testRendererCanLoadShaderLibrary() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let library = try OOTRenderer.makeLibrary(
            device: device,
            bundle: OOTRenderer.resourceBundle
        )

        XCTAssertNotNil(library.makeFunction(name: "oot_passthrough_vertex"))
    }

    func testFrameUniformsAndCombinerUniformsMatchMetalPacking() {
        XCTAssertEqual(MemoryLayout<FrameUniforms>.stride, 160)
        XCTAssertEqual(MemoryLayout<CombinerUniforms>.stride, 176)
    }

    func testRendererStoresCurrentRenderSettings() throws {
        let renderer = try OOTRenderer(
            renderSettings: RenderSettings(presentationMode: .enhanced)
        )

        XCTAssertEqual(renderer.currentRenderSettings.presentationMode, .enhanced)
    }

    func testRendererUsesN64VertexDescriptorLayout() throws {
        let renderer = try OOTRenderer()

        XCTAssertEqual(renderer.vertexDescriptor.layouts[0].stride, 16)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[0].format, .short3)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[0].offset, 0)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[1].format, .short2)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[1].offset, 8)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[2].format, .uchar4)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[2].offset, 12)
    }

    func testEnvironmentRendererInterpolatesBetweenTimeKeyframes() {
        let renderer = EnvironmentRenderer(
            environment: makeTimeOfDayEnvironment(
                lightSettings: [
                    makeLightSetting(ambient: 0, light: 0, fog: 0),
                    makeLightSetting(ambient: 255, light: 128, fog: 255),
                    makeLightSetting(ambient: 128, light: 255, fog: 128),
                    makeLightSetting(ambient: 0, light: 0, fog: 0),
                ]
            )
        )

        let state = renderer.currentState(timeOfDay: 7.0)

        XCTAssertEqual(state.ambientColor.x, 0.5, accuracy: 0.05)
        XCTAssertEqual(state.directionalLightColor.x, 0.25, accuracy: 0.05)
        XCTAssertEqual(state.fogColor.x, 0.5, accuracy: 0.05)
    }

    func testEnvironmentRendererInterpolatesDirectionalLightDirectionBetweenTimeKeyframes() {
        let renderer = EnvironmentRenderer(
            environment: makeTimeOfDayEnvironment(
                lightSettings: [
                    makeLightSetting(ambient: 0, light: 0, fog: 0, direction: Vector3b(x: 0, y: 0, z: 127)),
                    makeLightSetting(ambient: 0, light: 0, fog: 0, direction: Vector3b(x: 127, y: 0, z: 0)),
                    makeLightSetting(ambient: 0, light: 0, fog: 0),
                    makeLightSetting(ambient: 0, light: 0, fog: 0),
                ]
            )
        )

        let state = renderer.currentState(timeOfDay: 7.0)

        XCTAssertEqual(state.directionalLightDirection.x, 0.7, accuracy: 0.1)
        XCTAssertEqual(state.directionalLightDirection.z, 0.7, accuracy: 0.1)
        XCTAssertEqual(state.directionalLightDirection.w, 0.0, accuracy: 0.000_1)
    }

    func testEnvironmentRendererUsesFirstLightSettingWhenSceneIsNotTimeDriven() {
        let renderer = EnvironmentRenderer(
            environment: makeEnvironment(
                lightingMode: "false",
                lightSettings: [
                    makeLightSetting(ambient: 16, light: 32, fog: 48, direction: Vector3b(x: 0, y: 127, z: 0)),
                    makeLightSetting(ambient: 255, light: 255, fog: 255, direction: Vector3b(x: 127, y: 0, z: 0)),
                ]
            )
        )

        let state = renderer.currentState(timeOfDay: 18.0)

        XCTAssertEqual(state.ambientColor.x, 16.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(state.directionalLightColor.x, 32.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(state.fogColor.x, 48.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(state.directionalLightDirection.y, 1.0, accuracy: 0.000_1)
    }

    func testRendererAllocatesTripleBufferedFrameResources() throws {
        let renderer = try OOTRenderer()

        XCTAssertEqual(renderer.inFlightUniformBufferCount, 3)
    }

    func testRendererCachesPipelineStatesPerRenderStateKey() throws {
        let renderer = try OOTRenderer()
        let key = RenderStateKey(
            combinerHash: 0xCAFE_BABE,
            geometryMode: [.zBuffer],
            renderMode: RenderMode(flags: 0)
        )

        let firstPipeline = try renderer.cachedRenderPipelineState(for: key)
        let secondPipeline = try renderer.cachedRenderPipelineState(for: key)

        XCTAssertTrue(firstPipeline === secondPipeline)
        XCTAssertEqual(renderer.cachedRenderPipelineStateCount, 1)
    }

    func testRendererRendersSyntheticSceneThroughInterpreter() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let skyColor = SIMD4<Float>(0.2, 0.3, 0.4, 1.0)
        let renderer = try OOTRenderer(
            scene: OOTRenderScene.syntheticScene(
                vertices: makeTriangleVertices(
                    color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
                ),
                skyColor: skyColor
            )
        )
        let texture = try makeRenderTargetTexture(renderer: renderer)

        try renderer.renderCurrentSceneToTexture(texture)

        assertPixel(in: texture, x: 32, y: 32, equals: [0, 0, 255, 255])
        assertPixel(in: texture, x: 4, y: 4, equals: [102, 77, 51, 255])
    }

    func testRendererDrawsFlatColorTriangleToTexture() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)

        renderer.renderToTexture(texture)

        XCTAssertEqual(pixel(in: texture, x: 32, y: 32), [0, 0, 255, 255])
        XCTAssertEqual(pixel(in: texture, x: 4, y: 4), [52, 155, 45, 255])
    }

    func testRendererAppliesMVPTransformToTriangle() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let translatedUniforms = FrameUniforms(
            mvp: makeTranslationMatrix(x: 0.5, y: 0.0) * makeScaleMatrix(x: 0.25, y: 0.25),
            fogParameters: SIMD4<Float>(0.0, 1.0, 0.0, 0.0)
        )

        renderer.renderToTexture(texture, frameUniforms: translatedUniforms)

        XCTAssertEqual(pixel(in: texture, x: 48, y: 32), [0, 0, 255, 255])
        XCTAssertEqual(pixel(in: texture, x: 20, y: 32), [52, 155, 45, 255])
    }

    func testRendererCombinesTexel0AndShadeColor() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let texel0Texture = try makeSolidColorTexture(
            renderer: renderer,
            color: [128, 64, 255, 255]
        )
        let rdpState = makeRDPState(
            firstCycleColor: RDPCombineSelectorGroup(a: 1, b: 31, c: 4, d: 31),
            firstCycleAlpha: RDPCombineSelectorGroup(a: 1, b: 7, c: 4, d: 7)
        )
        let combinerUniforms = CombinerUniforms(
            rdpState: rdpState,
            textureSamplingState: TextureSamplingState(
                scale: SIMD2<Float>(repeating: 1.0)
            )
        )

        renderer.renderToTexture(
            texture,
            vertices: makeTriangleVertices(color: RGBA8(red: 255, green: 128, blue: 64, alpha: 255)),
            frameUniforms: defaultFrameUniforms,
            combinerUniforms: combinerUniforms,
            texel0Texture: texel0Texture
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [64, 32, 128, 255])
    }

    func testRendererCombinesPrimitiveAndEnvironmentColor() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let rdpState = makeRDPState(
            firstCycleColor: RDPCombineSelectorGroup(a: 3, b: 31, c: 5, d: 31),
            firstCycleAlpha: RDPCombineSelectorGroup(a: 3, b: 7, c: 5, d: 7),
            primitiveColor: RGBA8(red: 255, green: 128, blue: 64, alpha: 255),
            environmentColor: RGBA8(red: 128, green: 255, blue: 255, alpha: 255)
        )
        let combinerUniforms = CombinerUniforms(rdpState: rdpState)

        renderer.renderToTexture(
            texture,
            vertices: makeTriangleVertices(color: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)),
            frameUniforms: defaultFrameUniforms,
            combinerUniforms: combinerUniforms
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [64, 128, 128, 255])
    }

    func testRendererBlendsTowardFogColorAtMaximumFogFactor() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let frameUniforms = FrameUniforms(
            mvp: simd_float4x4(diagonal: SIMD4<Float>(0.5, 0.5, 1.0, 1.0)),
            fogParameters: SIMD4<Float>(0.0, 0.1, 0.0, 0.0)
        )
        let rdpState = makeRDPState(
            firstCycleColor: RDPCombineSelectorGroup(a: 31, b: 31, c: 31, d: 3),
            firstCycleAlpha: RDPCombineSelectorGroup(a: 7, b: 7, c: 7, d: 3),
            primitiveColor: RGBA8(red: 255, green: 0, blue: 0, alpha: 255),
            fogColor: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)
        )
        let combinerUniforms = CombinerUniforms(
            rdpState: rdpState,
            geometryMode: [.fog]
        )

        renderer.renderToTexture(
            texture,
            vertices: makeTriangleVertices(color: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)),
            frameUniforms: frameUniforms,
            combinerUniforms: combinerUniforms
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [255, 0, 0, 255])
    }

    func testRendererDiscardsFragmentsBelowAlphaCompareThreshold() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let rdpState = makeRDPState(
            firstCycleColor: RDPCombineSelectorGroup(a: 31, b: 31, c: 31, d: 3),
            firstCycleAlpha: RDPCombineSelectorGroup(a: 7, b: 7, c: 7, d: 3),
            primitiveColor: RGBA8(red: 255, green: 0, blue: 0, alpha: 64),
            blendColor: RGBA8(red: 0, green: 0, blue: 0, alpha: 128),
            otherMode: OtherMode(high: 0, low: 1)
        )
        let combinerUniforms = CombinerUniforms(rdpState: rdpState)

        renderer.renderToTexture(
            texture,
            vertices: makeTriangleVertices(color: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)),
            frameUniforms: defaultFrameUniforms,
            combinerUniforms: combinerUniforms
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [52, 155, 45, 255])
    }

    func testRendererAppliesDirectionalLightingWhenGeometryModeLightingEnabled() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let frameUniforms = FrameUniforms(
            mvp: simd_float4x4(diagonal: SIMD4<Float>(0.5, 0.5, 1.0, 1.0)),
            ambientColor: SIMD4<Float>(0.2, 0.2, 0.2, 1.0),
            directionalLightColor: SIMD4<Float>(0.6, 0.5, 0.4, 1.0),
            directionalLightDirection: SIMD4<Float>(0.0, 0.0, -1.0, 0.0)
        )
        let combinerUniforms = CombinerUniforms(geometryMode: GeometryMode.lighting.rawValue)

        renderer.renderToTexture(
            texture,
            vertices: makeTriangleVertices(color: RGBA8(red: 0, green: 0, blue: 127, alpha: 255)),
            frameUniforms: frameUniforms,
            combinerUniforms: combinerUniforms
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [153, 179, 204, 255], accuracy: 2)
    }

    func testRendererUsesSceneEnvironmentForBackgroundClearColor() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let environment = makeTimeOfDayEnvironment(
            lightSettings: [
                makeLightSetting(ambient: 0, light: 0, fog: 0),
                makeLightSetting(ambient: 255, light: 0, fog: 255),
                makeLightSetting(ambient: 128, light: 0, fog: 128),
                makeLightSetting(ambient: 0, light: 0, fog: 0),
            ]
        )
        let scene = OOTRenderScene.syntheticScene(
            vertices: makeTriangleVertices(color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)),
            environment: environment
        )
        let renderer = try OOTRenderer(scene: scene)
        renderer.setTimeOfDay(7.0)
        let texture = try makeRenderTargetTexture(renderer: renderer)

        try renderer.renderCurrentSceneToTexture(texture)

        assertPixel(in: texture, x: 4, y: 4, equals: [102, 102, 102, 255], accuracy: 4)
    }

    func testRendererDrawsResolvedSkyboxTexturesBehindSceneGeometry() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let environment = SceneEnvironmentFile(
            sceneName: "spot02",
            time: SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 0),
            skybox: SceneSkyboxSettings(
                skyboxID: 1,
                skyboxConfig: 1,
                environmentLightingMode: "LIGHT_MODE_TIME",
                skyboxDisabled: false,
                sunMoonDisabled: false
            ),
            lightSettings: [makeLightSetting(ambient: 0, light: 0, fog: 0)],
            resolvedSkybox: SceneResolvedSkybox(
                textureDirectories: ["Textures/vr_cloud1_static"],
                states: [
                    SceneSkyboxAssetState(
                        id: "day-overcast",
                        sourceName: "vr_cloud1_static",
                        faces: [
                            SceneSkyboxFaceAsset(face: .front, assetName: "gDayOvercastSkybox1Tex"),
                        ]
                    )
                ]
            )
        )
        let scene = OOTRenderScene(rooms: [], environment: environment)
        let renderer = try OOTRenderer(scene: scene)
        let skyboxTexture = try makeSolidColorTexture(
            renderer: renderer,
            color: [32, 160, 224, 255]
        )
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let camera = OrbitCamera(
            sceneBounds: SceneBounds(
                minimum: SIMD3<Float>(-1, -1, -1),
                maximum: SIMD3<Float>(1, 1, 1)
            ),
            azimuth: 0,
            elevation: 0
        )

        renderer.updateScene(
            scene,
            textureBindings: [
                OOTAssetID.stableID(for: "gDayOvercastSkybox1Tex"): skyboxTexture
            ]
        )
        try renderer.renderCurrentSceneToTexture(
            texture,
            frameUniforms: camera.frameUniforms(aspectRatio: 1.0),
            skyboxViewProjection: renderer.skyboxViewProjection(
                from: CameraMatrices(
                    viewMatrix: camera.viewMatrix,
                    projectionMatrix: camera.projectionMatrix(aspectRatio: 1.0)
                )
            )
        )

        assertPixel(in: texture, x: 32, y: 32, equals: [224, 160, 32, 255], accuracy: 2)
    }

    func testRendererReportsSceneFrameStats() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        var reportedStats = SceneFrameStats()
        let renderer = try OOTRenderer(
            scene: OOTRenderScene.syntheticScene(
                vertices: makeTriangleVertices(
                    color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
                )
            )
        ) { stats in
            reportedStats = stats
        }
        let texture = try makeRenderTargetTexture(renderer: renderer)

        try renderer.renderCurrentSceneToTexture(texture)

        XCTAssertEqual(reportedStats.roomCount, 1)
        XCTAssertEqual(reportedStats.vertexCount, 3)
        XCTAssertEqual(reportedStats.triangleCount, 1)
        XCTAssertEqual(reportedStats.drawCallCount, 1)
        XCTAssertEqual(reportedStats.pipelineStateCount, 1)
        XCTAssertEqual(reportedStats.textureMemoryBytes, 0)
        XCTAssertGreaterThanOrEqual(reportedStats.cpuRenderTimeMilliseconds, 0)
    }

    func testRendererSwitchesPresentationModeWithoutReinitialization() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer(
            scene: OOTRenderScene.syntheticScene(
                vertices: makeTriangleVertices(
                    color: RGBA8(red: 255, green: 96, blue: 32, alpha: 255)
                ),
                skyColor: SIMD4<Float>(0.12, 0.18, 0.28, 1.0)
            ),
            renderSettings: RenderSettings(presentationMode: .n64Aesthetic)
        )

        let n64Capture = try renderer.captureCurrentScene(size: CGSize(width: 640, height: 480))
        renderer.updateRenderSettings(RenderSettings(presentationMode: .enhanced))
        let enhancedCapture = try renderer.captureCurrentScene(size: CGSize(width: 640, height: 480))

        XCTAssertNotEqual(n64Capture.pixelsBGRA, enhancedCapture.pixelsBGRA)
        XCTAssertGreaterThan(
            differingByteCount(
                lhs: n64Capture.pixelsBGRA,
                rhs: enhancedCapture.pixelsBGRA
            ),
            10_000
        )
    }

    func testRendererCompositesXRayOverlayInSeparatePass() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        var reportedStats = SceneFrameStats()
        let overlayScene = OOTRenderScene(
            rooms: OOTRenderScene.syntheticScene(
                vertices: makeTriangleVertices(
                    color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
                )
            ).rooms,
            xrayDebugScene: XRayDebugScene(
                filledTriangles: [
                    XRayDebugTriangle(
                        a: SIMD3<Float>(-0.45, -0.35, 0),
                        b: SIMD3<Float>(0.45, -0.35, 0),
                        c: SIMD3<Float>(0.0, 0.55, 0),
                        color: SIMD4<Float>(0.0, 0.2, 1.0, 0.6)
                    )
                ]
            )
        )
        let renderer = try OOTRenderer(scene: overlayScene) { stats in
            reportedStats = stats
        }
        let texture = try makeRenderTargetTexture(renderer: renderer)

        try renderer.renderCurrentSceneToTexture(
            texture,
            frameUniforms: .identity
        )

        let blendedPixel = pixel(in: texture, x: 32, y: 32)
        XCTAssertGreaterThan(blendedPixel[0], 120)
        XCTAssertGreaterThan(blendedPixel[2], 80)
        XCTAssertEqual(reportedStats.triangleCount, 2)
        XCTAssertEqual(reportedStats.drawCallCount, 2)
    }

    private func makeRenderTargetTexture(
        renderer: OOTRenderer,
        width: Int = 64,
        height: Int = 64
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared

        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Failed to create render target texture")
        }

        return texture
    }

    private func pixel(in texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return pixel
    }

    private func assertPixel(
        in texture: MTLTexture,
        x: Int,
        y: Int,
        equals expected: [UInt8],
        accuracy: UInt8 = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = pixel(in: texture, x: x, y: y)

        for (actualChannel, expectedChannel) in zip(actual, expected) {
            let delta = actualChannel > expectedChannel
                ? actualChannel - expectedChannel
                : expectedChannel - actualChannel
            XCTAssertLessThanOrEqual(delta, accuracy, file: file, line: line)
        }
    }

    private func differingByteCount(lhs: [UInt8], rhs: [UInt8]) -> Int {
        zip(lhs, rhs).reduce(into: 0) { count, bytes in
            if bytes.0 != bytes.1 {
                count += 1
            }
        }
    }

    private func makeSolidColorTexture(
        renderer: OOTRenderer,
        color: [UInt8]
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Failed to create source texture")
        }

        var texel = color
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &texel,
            bytesPerRow: 4
        )
        return texture
    }

    private func makeTriangleVertices(color: RGBA8) -> [N64Vertex] {
        [
            N64Vertex(
                position: Vector3s(x: -1, y: -1, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 0),
                colorOrNormal: color
            ),
            N64Vertex(
                position: Vector3s(x: 1, y: -1, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 1, y: 0),
                colorOrNormal: color
            ),
            N64Vertex(
                position: Vector3s(x: 0, y: 1, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 1),
                colorOrNormal: color
            ),
        ]
    }

    private var defaultFrameUniforms: FrameUniforms {
        FrameUniforms(
            mvp: simd_float4x4(diagonal: SIMD4<Float>(0.5, 0.5, 1.0, 1.0))
        )
    }

    private func makeScaleMatrix(x: Float, y: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(x, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, y, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        )
    }

    private func makeTranslationMatrix(x: Float, y: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1.0, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 1.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0, 0.0),
            SIMD4<Float>(x, y, 0.0, 1.0)
        )
    }

    private func makeRDPState(
        firstCycleColor: RDPCombineSelectorGroup,
        firstCycleAlpha: RDPCombineSelectorGroup,
        primitiveColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        environmentColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        fogColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        blendColor: RGBA8 = RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
        otherMode: OtherMode = OtherMode(high: 0, low: 0)
    ) -> RDPState {
        RDPState(
            combineMode: RDPCombineState(
                firstCycle: RDPCombineCycle(
                    color: firstCycleColor,
                    alpha: firstCycleAlpha
                )
            ),
            primitiveColor: PrimitiveColor(
                minimumLOD: 0,
                level: 0,
                color: primitiveColor
            ),
            environmentColor: environmentColor,
            fogColor: fogColor,
            blendColor: blendColor,
            renderMode: RenderMode(flags: 0x1234_5678),
            otherMode: otherMode
        )
    }

    private func makeTimeOfDayEnvironment(lightSettings: [SceneLightSetting]) -> SceneEnvironmentFile {
        makeEnvironment(lightingMode: "LIGHT_MODE_TIME", lightSettings: lightSettings)
    }

    private func makeEnvironment(
        lightingMode: String,
        lightSettings: [SceneLightSetting]
    ) -> SceneEnvironmentFile {
        SceneEnvironmentFile(
            sceneName: "spot04",
            time: SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 0),
            skybox: SceneSkyboxSettings(
                skyboxID: 29,
                skyboxConfig: 0,
                environmentLightingMode: lightingMode,
                skyboxDisabled: false,
                sunMoonDisabled: false
            ),
            lightSettings: lightSettings
        )
    }

    private func makeLightSetting(
        ambient: UInt8,
        light: UInt8,
        fog: UInt8,
        direction: Vector3b = Vector3b(x: 0, y: 0, z: 127)
    ) -> SceneLightSetting {
        SceneLightSetting(
            ambientColor: RGB8(red: ambient, green: ambient, blue: ambient),
            light1Direction: direction,
            light1Color: RGB8(red: light, green: light, blue: light),
            light2Direction: Vector3b(x: 0, y: 0, z: -127),
            light2Color: RGB8(red: 0, green: 0, blue: 0),
            fogColor: RGB8(red: fog, green: fog, blue: fog),
            blendRate: 0,
            fogNear: 0,
            zFar: 1_000
        )
    }
}
