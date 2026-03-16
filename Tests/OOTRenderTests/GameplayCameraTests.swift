import CoreGraphics
import XCTest
@testable import OOTDataModel
@testable import OOTRender
import simd

final class GameplayCameraTests: XCTestCase {
    func testNormalModeTargetsHeadHeightAndSmoothsTowardUpdatedPlayerPosition() {
        let controller = GameplayCameraController(
            sceneBounds: sceneBounds,
            configuration: GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(0, 0, 0),
                playerYaw: 0
            ),
            viewportSize: CGSize(width: 800, height: 600)
        )

        let initial = controller.advance()
        XCTAssertEqual(initial.mode, .normal)
        assertVectorEqual(
            initial.focusTarget,
            SIMD3<Float>(0, GameplayCameraConfiguration.defaultHeadHeight, 0)
        )

        controller.updateConfiguration(
            GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(120, 0, 0),
                playerYaw: 0
            )
        )

        let updated = controller.advance()
        XCTAssertEqual(updated.mode, .normal)
        XCTAssertGreaterThan(updated.focusTarget.x, 0)
        XCTAssertLessThan(updated.focusTarget.x, 120)
        XCTAssertGreaterThan(updated.eyePosition.x, initial.eyePosition.x)
    }

    func testFixedModeUsesResolvedBgCameraPoseFromCollision() {
        let controller = GameplayCameraController(
            sceneBounds: sceneBounds,
            configuration: GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(0, 12, 0),
                playerYaw: 0,
                collision: fixedCameraCollision
            )
        )

        let snapshot = controller.advance()

        XCTAssertEqual(snapshot.mode, .fixed)
        assertVectorEqual(snapshot.eyePosition, SIMD3<Float>(40, 60, 120))
        XCTAssertEqual(snapshot.fieldOfView, Float.pi / 3.0, accuracy: 0.000_1)
    }

    func testParallelSnapResetsOrbitBackBehindPlayer() {
        let controller = GameplayCameraController(
            sceneBounds: sceneBounds,
            configuration: GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(0, 0, 0),
                playerYaw: 0
            )
        )

        controller.orbit(deltaX: 180, deltaY: 0)
        let orbited = controller.advance()
        XCTAssertNotEqual(orbited.mode, .parallel)
        XCTAssertGreaterThan(abs(orbited.eyePosition.x), 10)

        controller.snapBehindPlayer()
        let snapped = controller.advance()
        XCTAssertEqual(snapped.mode, .parallel)
        XCTAssertLessThan(abs(snapped.eyePosition.x), abs(orbited.eyePosition.x))
    }

    func testCollisionAvoidancePullsCameraForwardWhenWallBlocksView() {
        let controller = GameplayCameraController(
            sceneBounds: SceneBounds(
                minimum: SIMD3<Float>(-200, -40, -220),
                maximum: SIMD3<Float>(200, 120, 40)
            ),
            configuration: GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(0, 0, 0),
                playerYaw: 0,
                collision: occludingWallCollision
            )
        )

        let snapshot = controller.advance()

        XCTAssertEqual(snapshot.mode, .normal)
        XCTAssertGreaterThan(snapshot.eyePosition.z, -64)
        XCTAssertLessThan(snapshot.eyePosition.z, 0)
    }

    func testItemGetPresentationOverrideZoomsCameraTowardHeldItem() {
        let controller = GameplayCameraController(
            sceneBounds: sceneBounds,
            configuration: GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(0, 0, 0),
                playerYaw: 0,
                presentationOverride: .itemGet(
                    itemPosition: SIMD3<Float>(0, 58, 0),
                    playerYaw: 0
                )
            )
        )

        let snapshot = controller.advance()

        XCTAssertLessThan(snapshot.fieldOfView, Float.pi / 3.0)
        XCTAssertLessThan(simd_distance(snapshot.eyePosition, snapshot.focusTarget), 120)
        XCTAssertEqual(snapshot.focusTarget.y, 58, accuracy: 0.000_1)
    }
}

private extension GameplayCameraTests {
    var sceneBounds: SceneBounds {
        SceneBounds(
            minimum: SIMD3<Float>(-200, -40, -200),
            maximum: SIMD3<Float>(200, 160, 200)
        )
    }

    var fixedCameraCollision: CollisionMesh {
        CollisionMesh(
            vertices: [
                Vector3s(x: -200, y: 0, z: -200),
                Vector3s(x: 200, y: 0, z: -200),
                Vector3s(x: -200, y: 0, z: 200),
                Vector3s(x: 200, y: 0, z: 200),
            ],
            polygons: [
                CollisionPoly(
                    surfaceType: 0,
                    vertexA: 0,
                    vertexB: 2,
                    vertexC: 1,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
                CollisionPoly(
                    surfaceType: 0,
                    vertexA: 2,
                    vertexB: 3,
                    vertexC: 1,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
            ],
            surfaceTypes: [
                CollisionSurfaceType(low: 0, high: 0),
            ],
            bgCameras: [
                CollisionBgCamera(
                    setting: 0x0012,
                    count: 0,
                    cameraData: CollisionBgCameraData(
                        position: Vector3s(x: 40, y: 60, z: 120),
                        rotation: Vector3s(x: 0, y: Int16(bitPattern: 0x8000), z: 0),
                        fov: 60,
                        parameter: 0,
                        unknown: 0
                    )
                ),
            ]
        )
    }

    var occludingWallCollision: CollisionMesh {
        CollisionMesh(
            vertices: [
                Vector3s(x: -200, y: 0, z: -200),
                Vector3s(x: 200, y: 0, z: -200),
                Vector3s(x: -200, y: 0, z: 200),
                Vector3s(x: 200, y: 0, z: 200),
                Vector3s(x: -120, y: -20, z: -48),
                Vector3s(x: 120, y: -20, z: -48),
                Vector3s(x: -120, y: 140, z: -48),
                Vector3s(x: 120, y: 140, z: -48),
            ],
            polygons: [
                CollisionPoly(
                    surfaceType: 0,
                    vertexA: 0,
                    vertexB: 1,
                    vertexC: 2,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
                CollisionPoly(
                    surfaceType: 0,
                    vertexA: 2,
                    vertexB: 1,
                    vertexC: 3,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
                CollisionPoly(
                    surfaceType: 1,
                    vertexA: 4,
                    vertexB: 5,
                    vertexC: 6,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
                CollisionPoly(
                    surfaceType: 1,
                    vertexA: 6,
                    vertexB: 5,
                    vertexC: 7,
                    normal: Vector3s(x: 0, y: 0, z: 0),
                    distance: 0
                ),
            ],
            surfaceTypes: [
                CollisionSurfaceType(low: 0xFF, high: 0),
                CollisionSurfaceType(low: 0xFF, high: 0),
            ]
        )
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
