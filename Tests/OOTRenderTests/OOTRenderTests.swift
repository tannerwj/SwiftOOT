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
        XCTAssertEqual(MemoryLayout<FrameUniforms>.stride, 80)
        XCTAssertEqual(MemoryLayout<CombinerUniforms>.stride, 144)
    }

    func testRendererUsesN64VertexDescriptorLayout() throws {
        let renderer = try OOTRenderer()

        XCTAssertEqual(renderer.vertexDescriptor.layouts[0].stride, 16)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[0].format, .short3)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[0].offset, 0)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[1].format, .short2)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[1].offset, 8)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[2].format, .uchar4Normalized)
        XCTAssertEqual(renderer.vertexDescriptor.attributes[2].offset, 12)
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
            textureScale: SIMD2<Float>(repeating: 1.0)
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
}
