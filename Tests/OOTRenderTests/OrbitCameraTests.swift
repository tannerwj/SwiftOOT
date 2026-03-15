import CoreGraphics
import XCTest
import simd
@testable import OOTDataModel
@testable import OOTRender

final class OrbitCameraTests: XCTestCase {
    func testInitialCameraFramesSceneBoundsAtCenterWithSixtyDegreeFieldOfView() {
        let bounds = SceneBounds(
            minimum: SIMD3<Float>(-2.0, -1.0, -4.0),
            maximum: SIMD3<Float>(6.0, 3.0, 8.0)
        )
        let camera = OrbitCamera(sceneBounds: bounds)

        assertVectorEqual(camera.target, SIMD3<Float>(2.0, 1.0, 2.0))
        XCTAssertEqual(camera.fieldOfView, .pi / 3.0, accuracy: 0.000_1)
        XCTAssertGreaterThan(camera.distance, bounds.radius)
    }

    func testViewAndProjectionMatricesMatchOrbitCameraState() {
        let bounds = SceneBounds(
            minimum: SIMD3<Float>(-1.0, -1.0, -1.0),
            maximum: SIMD3<Float>(1.0, 1.0, 1.0)
        )
        let camera = OrbitCamera(
            sceneBounds: bounds,
            azimuth: 0.0,
            elevation: 0.0
        )
        let eyeInViewSpace = camera.viewMatrix * SIMD4<Float>(camera.position, 1.0)
        let targetInViewSpace = camera.viewMatrix * SIMD4<Float>(camera.target, 1.0)
        let projection = camera.projectionMatrix(aspectRatio: 16.0 / 9.0)
        let expectedYScale = 1.0 / tan((Float.pi / 3.0) * 0.5)

        assertVectorEqual(eyeInViewSpace.xyz, .zero)
        XCTAssertLessThan(targetInViewSpace.z, 0.0)
        XCTAssertEqual(projection[1, 1], expectedYScale, accuracy: 0.000_1)
        XCTAssertEqual(projection[0, 0], expectedYScale / (16.0 / 9.0), accuracy: 0.000_1)
    }

    func testOrbitZoomAndPanAdjustCameraStateWithinBounds() {
        var camera = OrbitCamera(
            sceneBounds: SceneBounds(
                minimum: SIMD3<Float>(-1.0, -1.0, -1.0),
                maximum: SIMD3<Float>(1.0, 1.0, 1.0)
            )
        )
        let originalTarget = camera.target

        camera.orbit(deltaAzimuth: 0.25, deltaElevation: 10.0)
        XCTAssertEqual(camera.elevation, .pi * 0.49, accuracy: 0.000_1)

        camera.zoom(delta: 10_000.0)
        XCTAssertEqual(camera.distance, camera.minDistance, accuracy: 0.000_1)

        camera.zoom(delta: -10_000.0)
        XCTAssertEqual(camera.distance, camera.maxDistance, accuracy: 0.000_1)

        camera.pan(
            screenDelta: SIMD2<Float>(120.0, 60.0),
            viewportSize: CGSize(width: 800.0, height: 600.0)
        )

        XCTAssertNotEqual(camera.target, originalTarget)
    }

    func testControllerMapsMouseScrollAndKeyboardInputIntoCameraUpdates() {
        let controller = OrbitCameraController(
            sceneBounds: SceneBounds(
                minimum: SIMD3<Float>(-1.0, -1.0, -1.0),
                maximum: SIMD3<Float>(1.0, 1.0, 1.0)
            ),
            viewportSize: CGSize(width: 800.0, height: 600.0)
        )
        let initialPosition = controller.camera.position
        let initialTarget = controller.camera.target
        let initialDistance = controller.camera.distance

        controller.orbit(deltaX: 32.0, deltaY: -16.0)
        controller.zoom(scrollDeltaY: 12.0)
        controller.pan(deltaX: 24.0, deltaY: 12.0)
        controller.pan(direction: .right)

        XCTAssertNotEqual(controller.camera.position, initialPosition)
        XCTAssertNotEqual(controller.camera.target, initialTarget)
        XCTAssertLessThan(controller.camera.distance, initialDistance)
    }

    func testPerspectiveFrameUniformKeepsTriangleVisibleInRenderer() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let vertices = [
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
        let renderer = try OOTRenderer(sceneVertices: vertices)
        let texture = try makeRenderTargetTexture(renderer: renderer)
        let camera = OrbitCamera(
            sceneBounds: SceneBounds(vertices: vertices),
            azimuth: 0.0,
            elevation: 0.0
        )

        renderer.renderToTexture(
            texture,
            vertices: vertices,
            frameUniforms: camera.frameUniforms(aspectRatio: 1.0)
        )

        XCTAssertEqual(pixel(in: texture, x: 32, y: 24), [0, 0, 255, 255])
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
}

private func assertVectorEqual(
    _ lhs: SIMD3<Float>,
    _ rhs: SIMD3<Float>,
    accuracy: Float = 0.000_1,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
