import XCTest
import Metal
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

    func testRendererBundleContainsCompiledShaderLibrary() {
        let shaderLibraryURL = OOTRenderer.resourceBundle.url(
            forResource: "default",
            withExtension: "metallib"
        )

        XCTAssertNotNil(shaderLibraryURL)
    }

    func testRendererDrawsZeldaGreenToTexture() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderer = try OOTRenderer()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared

        guard let texture = renderer.device.makeTexture(descriptor: descriptor) else {
            XCTFail("Failed to create render target texture")
            return
        }

        renderer.renderToTexture(texture)

        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )

        XCTAssertEqual(pixel, [52, 155, 45, 255])
    }
}
