import CoreGraphics
import OOTDataModel
import simd

public enum GameplayCameraMode: String, Sendable, Equatable {
    case normal
    case fixed
    case parallel
}

public struct GameplayCameraConfiguration: Sendable, Equatable {
    public static let defaultHeadHeight: Float = 44.0

    public var playerPosition: SIMD3<Float>
    public var playerYaw: Float
    public var headHeight: Float
    public var collision: CollisionMesh?

    public init(
        playerPosition: SIMD3<Float>,
        playerYaw: Float,
        headHeight: Float = Self.defaultHeadHeight,
        collision: CollisionMesh? = nil
    ) {
        self.playerPosition = playerPosition
        self.playerYaw = playerYaw
        self.headHeight = headHeight
        self.collision = collision
    }
}

struct GameplayCameraSnapshot: Sendable, Equatable {
    var mode: GameplayCameraMode
    var eyePosition: SIMD3<Float>
    var focusTarget: SIMD3<Float>
    var fieldOfView: Float
}

public final class GameplayCameraController {
    public private(set) var configuration: GameplayCameraConfiguration
    public private(set) var viewportSize: CGSize
    public private(set) var currentMode: GameplayCameraMode

    private let sceneBounds: SceneBounds
    private let followDistance: Float
    private let collisionPadding: Float
    private let orientationSmoothing: Float
    private let positionSmoothing: Float
    private let targetSmoothing: Float
    private let fieldOfViewSmoothing: Float

    private var currentEyePosition: SIMD3<Float>
    private var currentFocusTarget: SIMD3<Float>
    private var currentOrientation: simd_quatf
    private var currentFieldOfView: Float
    private var orbitAzimuthOffset: Float
    private var orbitElevation: Float
    private var isParallelSnapActive: Bool

    public init(
        sceneBounds: SceneBounds,
        configuration: GameplayCameraConfiguration,
        viewportSize: CGSize = .zero
    ) {
        self.sceneBounds = sceneBounds
        self.configuration = configuration
        self.viewportSize = viewportSize
        self.followDistance = max(140.0, min(sceneBounds.radius * 0.08, 220.0))
        self.collisionPadding = 12.0
        self.orientationSmoothing = 0.2
        self.positionSmoothing = 0.18
        self.targetSmoothing = 0.22
        self.fieldOfViewSmoothing = 0.18
        self.orbitAzimuthOffset = 0
        self.orbitElevation = 0.22
        self.isParallelSnapActive = false

        let initial = Self.desiredPose(
            sceneBounds: sceneBounds,
            configuration: configuration,
            followDistance: followDistance,
            orbitAzimuthOffset: 0,
            orbitElevation: 0.22,
            isParallelSnapActive: false,
            collisionPadding: 12.0
        )
        self.currentMode = initial.mode
        self.currentEyePosition = initial.eyePosition
        self.currentFocusTarget = initial.focusTarget
        self.currentOrientation = initial.orientation
        self.currentFieldOfView = initial.fieldOfView
    }

    public func updateViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    public func updateConfiguration(_ configuration: GameplayCameraConfiguration) {
        self.configuration = configuration
    }

    public func orbit(deltaX: CGFloat, deltaY: CGFloat) {
        guard Self.resolvedFixedCamera(in: configuration) == nil else {
            return
        }

        orbitAzimuthOffset += Float(deltaX) * 0.01
        orbitElevation = gameplayClamp(
            orbitElevation + Float(deltaY) * 0.005,
            -Float.pi * 0.18,
            Float.pi * 0.35
        )
        isParallelSnapActive = false
    }

    public func snapBehindPlayer() {
        orbitAzimuthOffset = 0
        isParallelSnapActive = true
    }

    func cameraMatrices() -> CameraMatrices {
        let snapshot = advance()
        let aspectRatio = if viewportSize.width > 0, viewportSize.height > 0 {
            Float(viewportSize.width / viewportSize.height)
        } else {
            Float(1.0)
        }

        let viewMatrix = gameplayMakeLookAtMatrix(
            eye: snapshot.eyePosition,
            center: snapshot.eyePosition + currentOrientation.act(SIMD3<Float>(0, 0, -1)),
            up: currentOrientation.act(SIMD3<Float>(0, 1, 0))
        )
        let nearPlane = max(10.0, min(simd_distance(snapshot.eyePosition, snapshot.focusTarget) * 0.1, 40.0))
        let farPlane = max(sceneBounds.radius * 8.0, 2_000.0)

        return CameraMatrices(
            viewMatrix: viewMatrix,
            projectionMatrix: gameplayMakePerspectiveMatrix(
                verticalFieldOfView: snapshot.fieldOfView,
                aspectRatio: aspectRatio,
                nearPlane: nearPlane,
                farPlane: farPlane
            )
        )
    }

    public func frameUniforms() -> FrameUniforms {
        FrameUniforms(mvp: cameraMatrices().viewProjectionMatrix)
    }

    @discardableResult
    func advance() -> GameplayCameraSnapshot {
        let desired = Self.desiredPose(
            sceneBounds: sceneBounds,
            configuration: configuration,
            followDistance: followDistance,
            orbitAzimuthOffset: orbitAzimuthOffset,
            orbitElevation: orbitElevation,
            isParallelSnapActive: isParallelSnapActive,
            collisionPadding: collisionPadding
        )

        currentEyePosition = simd_mix(
            currentEyePosition,
            desired.eyePosition,
            SIMD3<Float>(repeating: positionSmoothing)
        )
        currentFocusTarget = simd_mix(
            currentFocusTarget,
            desired.focusTarget,
            SIMD3<Float>(repeating: targetSmoothing)
        )
        currentOrientation = simd_slerp(currentOrientation, desired.orientation, orientationSmoothing)
        currentFieldOfView += (desired.fieldOfView - currentFieldOfView) * fieldOfViewSmoothing
        currentMode = desired.mode

        if isParallelSnapActive, Self.angularDistance(currentOrientation, desired.orientation) < 0.02 {
            isParallelSnapActive = false
            currentMode = .normal
        }

        return GameplayCameraSnapshot(
            mode: currentMode,
            eyePosition: currentEyePosition,
            focusTarget: currentFocusTarget,
            fieldOfView: currentFieldOfView
        )
    }
}

private extension GameplayCameraController {
    struct DesiredPose {
        var mode: GameplayCameraMode
        var eyePosition: SIMD3<Float>
        var focusTarget: SIMD3<Float>
        var orientation: simd_quatf
        var fieldOfView: Float
    }

    static func desiredPose(
        sceneBounds: SceneBounds,
        configuration: GameplayCameraConfiguration,
        followDistance: Float,
        orbitAzimuthOffset: Float,
        orbitElevation: Float,
        isParallelSnapActive: Bool,
        collisionPadding: Float
    ) -> DesiredPose {
        let focusTarget = configuration.playerPosition + SIMD3<Float>(0, configuration.headHeight, 0)

        if let fixedCamera = resolvedFixedCamera(in: configuration) {
            let forward = fixedCamera.forwardVector
            let orientation = gameplayLookRotationQuaternion(
                eye: fixedCamera.position,
                center: fixedCamera.position + forward
            )
            return DesiredPose(
                mode: .fixed,
                eyePosition: fixedCamera.position,
                focusTarget: fixedCamera.position + forward,
                orientation: orientation,
                fieldOfView: fixedCamera.fieldOfView
            )
        }

        let desiredAzimuth = configuration.playerYaw + .pi + orbitAzimuthOffset
        let desiredEye =
            focusTarget +
            gameplayOrbitalOffset(
                azimuth: desiredAzimuth,
                elevation: orbitElevation,
                distance: followDistance
            )
        let collisionCorrectedEye = correctedEyePosition(
            from: focusTarget,
            to: desiredEye,
            collision: configuration.collision,
            padding: collisionPadding
        )
        let orientation = gameplayLookRotationQuaternion(
            eye: collisionCorrectedEye,
            center: focusTarget
        )

        return DesiredPose(
            mode: isParallelSnapActive ? .parallel : .normal,
            eyePosition: collisionCorrectedEye,
            focusTarget: focusTarget,
            orientation: orientation,
            fieldOfView: Float.pi / 3.0
        )
    }

    static func resolvedFixedCamera(
        in configuration: GameplayCameraConfiguration
    ) -> FixedCameraPose? {
        guard let collision = configuration.collision else {
            return nil
        }

        guard
            let bgCameraIndex = bgCameraIndexUnderPlayer(collision: collision, position: configuration.playerPosition),
            collision.bgCameras.indices.contains(bgCameraIndex)
        else {
            return nil
        }

        let bgCamera = collision.bgCameras[bgCameraIndex]
        guard bgCamera.setting != 0, let cameraData = bgCamera.cameraData else {
            return nil
        }

        return FixedCameraPose(cameraData: cameraData)
    }

    static func bgCameraIndexUnderPlayer(
        collision: CollisionMesh,
        position: SIMD3<Float>
    ) -> Int? {
        var highestFloorY = -Float.greatestFiniteMagnitude
        var selectedIndex: Int?

        for polygon in collision.polygons {
            guard Int(polygon.surfaceType) < collision.surfaceTypes.count else {
                continue
            }

            let triangle = GameplayCollisionTriangle(collision: collision, polygon: polygon)
            guard triangle.isFloorCandidate else {
                continue
            }
            guard let floorY = triangle.verticalIntersectionY(x: position.x, z: position.z) else {
                continue
            }
            guard floorY <= position.y + 1.0, floorY > highestFloorY else {
                continue
            }

            highestFloorY = floorY
            let bgCameraIndex = Int(collision.surfaceTypes[Int(polygon.surfaceType)].bgCamIndex)
            selectedIndex = bgCameraIndex
        }

        return selectedIndex
    }

    static func correctedEyePosition(
        from start: SIMD3<Float>,
        to target: SIMD3<Float>,
        collision: CollisionMesh?,
        padding: Float
    ) -> SIMD3<Float> {
        guard let collision else {
            return target
        }

        let segment = target - start
        let segmentLength = simd_length(segment)
        guard segmentLength > 0.001 else {
            return target
        }

        var nearestDistance = segmentLength
        for polygon in collision.polygons {
            let triangle = GameplayCollisionTriangle(collision: collision, polygon: polygon)
            guard let distance = triangle.intersectionDistance(from: start, to: target) else {
                continue
            }
            nearestDistance = min(nearestDistance, distance)
        }

        guard nearestDistance < segmentLength else {
            return target
        }

        let safeDistance = max(nearestDistance - padding, 32.0)
        return start + (segment / segmentLength) * safeDistance
    }

    static func angularDistance(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let dot = max(-1.0, min(1.0, simd_dot(lhs.vector, rhs.vector)))
        return acos(abs(dot)) * 2.0
    }
}

private struct FixedCameraPose {
    let position: SIMD3<Float>
    let forwardVector: SIMD3<Float>
    let fieldOfView: Float

    init(cameraData: CollisionBgCameraData) {
        position = SIMD3<Float>(
            Float(cameraData.position.x),
            Float(cameraData.position.y),
            Float(cameraData.position.z)
        )

        let pitch = gameplayBinaryAngleToRadians(cameraData.rotation.x)
        let yaw = gameplayBinaryAngleToRadians(cameraData.rotation.y)
        forwardVector = gameplayNormalize(
            SIMD3<Float>(
                sin(yaw) * cos(pitch),
                -sin(pitch),
                cos(yaw) * cos(pitch)
            ),
            fallback: SIMD3<Float>(0, 0, -1)
        )

        let fovDegrees = Float(cameraData.fov) > 360 ? Float(cameraData.fov) * 0.01 : Float(cameraData.fov)
        fieldOfView = gameplayClamp(fovDegrees * .pi / 180.0, .pi / 8.0, .pi * 0.75)
    }
}

private struct GameplayCollisionTriangle {
    let a: SIMD3<Float>
    let b: SIMD3<Float>
    let c: SIMD3<Float>
    let normal: SIMD3<Float>

    init(collision: CollisionMesh, polygon: CollisionPoly) {
        a = gameplayVector(collision.vertices[Int(polygon.vertexA)])
        b = gameplayVector(collision.vertices[Int(polygon.vertexB)])
        c = gameplayVector(collision.vertices[Int(polygon.vertexC)])
        normal = gameplayNormalize(simd_cross(b - a, c - a), fallback: SIMD3<Float>(0, 1, 0))
    }

    var isFloorCandidate: Bool {
        normal.y > 0.2
    }

    func verticalIntersectionY(x: Float, z: Float) -> Float? {
        guard abs(normal.y) > 0.0001 else {
            return nil
        }

        let y = a.y - ((normal.x * (x - a.x)) + (normal.z * (z - a.z))) / normal.y
        let point = SIMD3<Float>(x, y, z)
        return contains(point) ? y : nil
    }

    func intersectionDistance(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float? {
        let direction = end - start
        let edge1 = b - a
        let edge2 = c - a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)

        guard abs(determinant) > 0.0001 else {
            return nil
        }

        let inverseDeterminant = 1.0 / determinant
        let tVector = start - a
        let u = simd_dot(tVector, p) * inverseDeterminant
        guard 0...1 ~= u else {
            return nil
        }

        let q = simd_cross(tVector, edge1)
        let v = simd_dot(direction, q) * inverseDeterminant
        guard v >= 0, u + v <= 1 else {
            return nil
        }

        let t = simd_dot(edge2, q) * inverseDeterminant
        guard 0...1 ~= t else {
            return nil
        }

        return simd_length(direction) * t
    }

    private func contains(_ point: SIMD3<Float>) -> Bool {
        let v0 = c - a
        let v1 = b - a
        let v2 = point - a

        let dot00 = simd_dot(v0, v0)
        let dot01 = simd_dot(v0, v1)
        let dot02 = simd_dot(v0, v2)
        let dot11 = simd_dot(v1, v1)
        let dot12 = simd_dot(v1, v2)

        let inverseDenominator = 1.0 / max((dot00 * dot11) - (dot01 * dot01), 0.0001)
        let u = ((dot11 * dot02) - (dot01 * dot12)) * inverseDenominator
        let v = ((dot00 * dot12) - (dot01 * dot02)) * inverseDenominator
        return u >= -0.001 && v >= -0.001 && (u + v) <= 1.001
    }
}

private func gameplayVector(_ vector: Vector3s) -> SIMD3<Float> {
    SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
}

private func gameplayOrbitalOffset(
    azimuth: Float,
    elevation: Float,
    distance: Float
) -> SIMD3<Float> {
    SIMD3<Float>(
        cos(elevation) * sin(azimuth),
        sin(elevation),
        cos(elevation) * cos(azimuth)
    ) * distance
}

private func gameplayLookRotationQuaternion(
    eye: SIMD3<Float>,
    center: SIMD3<Float>
) -> simd_quatf {
    let forward = gameplayNormalize(center - eye, fallback: SIMD3<Float>(0, 0, -1))
    let right = gameplayNormalize(
        simd_cross(forward, SIMD3<Float>(0, 1, 0)),
        fallback: SIMD3<Float>(1, 0, 0)
    )
    let up = gameplayNormalize(simd_cross(right, forward), fallback: SIMD3<Float>(0, 1, 0))
    return simd_quatf(simd_float3x3(columns: (right, up, -forward)))
}

private func gameplayMakeLookAtMatrix(
    eye: SIMD3<Float>,
    center: SIMD3<Float>,
    up: SIMD3<Float>
) -> simd_float4x4 {
    let forward = gameplayNormalize(center - eye, fallback: SIMD3<Float>(0, 0, -1))
    let side = gameplayNormalize(simd_cross(forward, up), fallback: SIMD3<Float>(1, 0, 0))
    let cameraUp = gameplayNormalize(simd_cross(side, forward), fallback: SIMD3<Float>(0, 1, 0))
    let zAxis = -forward

    return simd_float4x4(
        SIMD4<Float>(side.x, cameraUp.x, zAxis.x, 0.0),
        SIMD4<Float>(side.y, cameraUp.y, zAxis.y, 0.0),
        SIMD4<Float>(side.z, cameraUp.z, zAxis.z, 0.0),
        SIMD4<Float>(
            -simd_dot(side, eye),
            -simd_dot(cameraUp, eye),
            -simd_dot(zAxis, eye),
            1.0
        )
    )
}

private func gameplayMakePerspectiveMatrix(
    verticalFieldOfView: Float,
    aspectRatio: Float,
    nearPlane: Float,
    farPlane: Float
) -> simd_float4x4 {
    let yScale = 1.0 / tan(verticalFieldOfView * 0.5)
    let xScale = yScale / max(aspectRatio, 0.0001)
    let zRange = farPlane - nearPlane

    return simd_float4x4(
        SIMD4<Float>(xScale, 0.0, 0.0, 0.0),
        SIMD4<Float>(0.0, yScale, 0.0, 0.0),
        SIMD4<Float>(0.0, 0.0, -(farPlane + nearPlane) / zRange, -1.0),
        SIMD4<Float>(0.0, 0.0, -(2.0 * farPlane * nearPlane) / zRange, 0.0)
    )
}

private func gameplayBinaryAngleToRadians(_ value: Int16) -> Float {
    Float(value) * (.pi / 32_768.0)
}

private func gameplayNormalize(
    _ vector: SIMD3<Float>,
    fallback: SIMD3<Float>
) -> SIMD3<Float> {
    let length = simd_length(vector)
    guard length > 0.0001 else {
        return fallback
    }

    return vector / length
}

private func gameplayClamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
    Swift.max(minimum, Swift.min(value, maximum))
}
