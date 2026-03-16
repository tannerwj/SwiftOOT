import CoreGraphics
import OOTDataModel
import simd

public struct SceneBounds: Sendable, Equatable {
    public var minimum: SIMD3<Float>
    public var maximum: SIMD3<Float>

    public init(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(vertices: [N64Vertex]) {
        guard let firstVertex = vertices.first else {
            self.init(minimum: .zero, maximum: .zero)
            return
        }

        var minimum = SIMD3<Float>(
            Float(firstVertex.position.x),
            Float(firstVertex.position.y),
            Float(firstVertex.position.z)
        )
        var maximum = minimum

        for vertex in vertices.dropFirst() {
            let point = SIMD3<Float>(
                Float(vertex.position.x),
                Float(vertex.position.y),
                Float(vertex.position.z)
            )
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }

        self.init(minimum: minimum, maximum: maximum)
    }

    public var center: SIMD3<Float> {
        (minimum + maximum) * 0.5
    }

    public var size: SIMD3<Float> {
        maximum - minimum
    }

    public var radius: Float {
        max(simd_length(maximum - center), 1.0)
    }
}

public enum OrbitPanDirection: Sendable {
    case up
    case down
    case left
    case right
}

public struct OrbitCamera: Sendable, Equatable {
    public static let defaultFieldOfView: Float = .pi / 3.0

    public private(set) var sceneBounds: SceneBounds
    public var target: SIMD3<Float>
    public var distance: Float
    public var azimuth: Float
    public var elevation: Float
    public var fieldOfView: Float
    public var minDistance: Float
    public var maxDistance: Float

    public init(
        sceneBounds: SceneBounds,
        azimuth: Float = -.pi / 4.0,
        elevation: Float = .pi / 9.0,
        fieldOfView: Float = OrbitCamera.defaultFieldOfView
    ) {
        let radius = sceneBounds.radius
        let distance = max(radius / sin(fieldOfView * 0.5), radius + 1.0)

        self.sceneBounds = sceneBounds
        self.target = sceneBounds.center
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.fieldOfView = fieldOfView
        self.minDistance = max(radius * 0.25, 0.5)
        self.maxDistance = max(radius * 32.0, distance + radius * 4.0)
        clampState()
    }

    public var position: SIMD3<Float> {
        target + orbitOffset
    }

    public var viewMatrix: simd_float4x4 {
        makeLookAtMatrix(eye: position, center: target, up: cameraUpVector)
    }

    public var nearPlane: Float {
        max(0.1, min(distance * 0.1, distance - minDistance * 0.5))
    }

    public var farPlane: Float {
        max(distance + sceneBounds.radius * 8.0, nearPlane + 128.0)
    }

    public func projectionMatrix(aspectRatio: Float) -> simd_float4x4 {
        makePerspectiveMatrix(
            verticalFieldOfView: fieldOfView,
            aspectRatio: max(aspectRatio, 0.000_1),
            nearPlane: nearPlane,
            farPlane: farPlane
        )
    }

    public func frameUniforms(aspectRatio: Float) -> FrameUniforms {
        FrameUniforms(mvp: projectionMatrix(aspectRatio: aspectRatio) * viewMatrix)
    }

    public mutating func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth += deltaAzimuth
        elevation += deltaElevation
        clampState()
    }

    public mutating func zoom(delta: Float) {
        let zoomScale = exp(-delta * 0.015)
        distance = clamp(distance * zoomScale, minDistance, maxDistance)
    }

    public mutating func pan(screenDelta: SIMD2<Float>, viewportSize: CGSize) {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let aspectRatio = Float(viewportSize.width / viewportSize.height)
        let visibleHeight = 2.0 * distance * tan(fieldOfView * 0.5)
        let visibleWidth = visibleHeight * aspectRatio
        let right = cameraRightVector
        let up = cameraUpVector
        let offset =
            right * (screenDelta.x / Float(viewportSize.width) * visibleWidth) +
            up * (screenDelta.y / Float(viewportSize.height) * visibleHeight)

        target += offset
    }

    public mutating func pan(
        direction: OrbitPanDirection,
        viewportSize: CGSize,
        stepInPoints: Float = 48.0
    ) {
        let delta: SIMD2<Float>

        switch direction {
        case .up:
            delta = SIMD2<Float>(0.0, stepInPoints)
        case .down:
            delta = SIMD2<Float>(0.0, -stepInPoints)
        case .left:
            delta = SIMD2<Float>(-stepInPoints, 0.0)
        case .right:
            delta = SIMD2<Float>(stepInPoints, 0.0)
        }

        pan(screenDelta: delta, viewportSize: viewportSize)
    }

    private var orbitOffset: SIMD3<Float> {
        SIMD3<Float>(
            cos(elevation) * sin(azimuth),
            sin(elevation),
            cos(elevation) * cos(azimuth)
        ) * distance
    }

    private var forwardVector: SIMD3<Float> {
        normalize(target - position, fallback: SIMD3<Float>(0.0, 0.0, -1.0))
    }

    private var cameraRightVector: SIMD3<Float> {
        normalize(
            simd_cross(forwardVector, SIMD3<Float>(0.0, 1.0, 0.0)),
            fallback: SIMD3<Float>(1.0, 0.0, 0.0)
        )
    }

    private var cameraUpVector: SIMD3<Float> {
        normalize(
            simd_cross(cameraRightVector, forwardVector),
            fallback: SIMD3<Float>(0.0, 1.0, 0.0)
        )
    }

    private mutating func clampState() {
        elevation = clamp(elevation, -.pi * 0.49, .pi * 0.49)
        distance = clamp(distance, minDistance, maxDistance)
    }
}

public final class OrbitCameraController {
    public private(set) var camera: OrbitCamera
    public private(set) var viewportSize: CGSize

    public init(
        sceneBounds: SceneBounds,
        viewportSize: CGSize = .zero
    ) {
        self.camera = OrbitCamera(sceneBounds: sceneBounds)
        self.viewportSize = viewportSize
    }

    public func updateViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    public func orbit(deltaX: CGFloat, deltaY: CGFloat) {
        camera.orbit(
            deltaAzimuth: Float(deltaX) * 0.01,
            deltaElevation: Float(deltaY) * 0.01
        )
    }

    public func pan(deltaX: CGFloat, deltaY: CGFloat) {
        camera.pan(
            screenDelta: SIMD2<Float>(Float(deltaX), Float(deltaY)),
            viewportSize: viewportSize
        )
    }

    public func zoom(scrollDeltaY: CGFloat) {
        camera.zoom(delta: Float(scrollDeltaY))
    }

    public func pan(direction: OrbitPanDirection) {
        camera.pan(direction: direction, viewportSize: viewportSize)
    }

    func cameraMatrices() -> CameraMatrices {
        let aspectRatio: Float
        if viewportSize.width > 0, viewportSize.height > 0 {
            aspectRatio = Float(viewportSize.width / viewportSize.height)
        } else {
            aspectRatio = 1.0
        }

        return CameraMatrices(
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix(aspectRatio: aspectRatio)
        )
    }

    public func frameUniforms() -> FrameUniforms {
        FrameUniforms(mvp: cameraMatrices().viewProjectionMatrix)
    }
}

private func makeLookAtMatrix(
    eye: SIMD3<Float>,
    center: SIMD3<Float>,
    up: SIMD3<Float>
) -> simd_float4x4 {
    let forward = normalize(center - eye, fallback: SIMD3<Float>(0.0, 0.0, -1.0))
    let side = normalize(simd_cross(forward, up), fallback: SIMD3<Float>(1.0, 0.0, 0.0))
    let cameraUp = normalize(simd_cross(side, forward), fallback: SIMD3<Float>(0.0, 1.0, 0.0))
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

private func makePerspectiveMatrix(
    verticalFieldOfView: Float,
    aspectRatio: Float,
    nearPlane: Float,
    farPlane: Float
) -> simd_float4x4 {
    let yScale = 1.0 / tan(verticalFieldOfView * 0.5)
    let xScale = yScale / aspectRatio
    let zRange = farPlane - nearPlane

    return simd_float4x4(
        SIMD4<Float>(xScale, 0.0, 0.0, 0.0),
        SIMD4<Float>(0.0, yScale, 0.0, 0.0),
        SIMD4<Float>(0.0, 0.0, -(farPlane + nearPlane) / zRange, -1.0),
        SIMD4<Float>(0.0, 0.0, -(2.0 * farPlane * nearPlane) / zRange, 0.0)
    )
}

private func normalize(
    _ vector: SIMD3<Float>,
    fallback: SIMD3<Float>
) -> SIMD3<Float> {
    let length = simd_length(vector)
    guard length > 0.000_1 else {
        return fallback
    }

    return vector / length
}

private func clamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
    Swift.max(minimum, Swift.min(value, maximum))
}
