import XCTest
import Metal
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
        XCTAssertEqual(MemoryLayout<CombinerUniforms>.stride, 16)
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
}
