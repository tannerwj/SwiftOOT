import Metal
import XCTest
@testable import OOTDataModel
@testable import OOTRender

final class DrawBatchTests: XCTestCase {
    func testAccumulatesOneHundredTrianglesAcrossMultipleAppendCalls() throws {
        var batch = DrawBatch(renderStateKey: makeRenderStateKey())

        for triangleIndex in 0..<100 {
            try batch.append(
                vertices: makeTriangleVertices(xOffset: Float(triangleIndex) * 0.001),
                triangles: [SIMD3<UInt32>(0, 1, 2)]
            )
        }

        XCTAssertEqual(batch.vertexCount, 300)
        XCTAssertEqual(batch.indexCount, 300)
        XCTAssertEqual(batch.pendingTriangleCount, 100)
        XCTAssertEqual(batch.totalTriangleCount, 0)
        XCTAssertEqual(batch.drawCallCount, 0)
    }

    func testFlushRendersColoredTriangleIntoOffscreenTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderStateKey = makeRenderStateKey()
        let pipelineState = try makeDrawBatchPipelineState(
            device: device,
            renderStateKey: renderStateKey
        )
        let resources = DrawBatchResources(
            device: device,
            pipelineLookup: AnyRenderPipelineStateLookup { _ in pipelineState }
        )
        var batch = DrawBatch(
            renderStateKey: renderStateKey,
            resources: resources
        )

        try batch.append(
            vertices: makeTriangleVertices(),
            triangles: [SIMD3<UInt32>(0, 1, 2)]
        )

        let texture = try makeRenderTargetTexture(device: device)
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(
            commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        )

        XCTAssertTrue(try batch.flush(encoder: encoder))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertTrue(batch.isEmpty)
        XCTAssertEqual(batch.pendingTriangleCount, 0)
        XCTAssertEqual(batch.totalTriangleCount, 1)
        XCTAssertEqual(batch.drawCallCount, 1)

        let centerPixel = pixel(in: texture, x: 32, y: 32)
        XCTAssertTrue(centerPixel[0] > 0 || centerPixel[1] > 0 || centerPixel[2] > 0)
        XCTAssertEqual(pixel(in: texture, x: 4, y: 4), [0, 0, 0, 255])
    }

    private func makeRenderStateKey() -> RenderStateKey {
        RenderStateKey(
            combinerHash: 0xCAFE_BABE,
            geometryMode: [.zBuffer],
            renderMode: RenderMode(flags: 0)
        )
    }

    private func makeTriangleVertices(xOffset: Float = 0) -> [TransformedVertex] {
        [
            TransformedVertex(
                clipPosition: SIMD4<Float>(-0.5 + xOffset, -0.5, 0, 1),
                textureCoordinates: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(1, 0, 0, 1)
            ),
            TransformedVertex(
                clipPosition: SIMD4<Float>(0.5 + xOffset, -0.5, 0, 1),
                textureCoordinates: SIMD2<Float>(1, 0),
                color: SIMD4<Float>(1, 0, 0, 1)
            ),
            TransformedVertex(
                clipPosition: SIMD4<Float>(0 + xOffset, 0.5, 0, 1),
                textureCoordinates: SIMD2<Float>(0.5, 1),
                color: SIMD4<Float>(1, 0, 0, 1)
            ),
        ]
    }

    private func makeRenderTargetTexture(
        device: MTLDevice,
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

        guard let texture = device.makeTexture(descriptor: descriptor) else {
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
}
