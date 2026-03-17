import simd

public struct XRayDebugLineSegment: Sendable, Equatable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var color: SIMD4<Float>

    public init(
        start: SIMD3<Float>,
        end: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        self.start = start
        self.end = end
        self.color = color
    }
}

public struct XRayDebugTriangle: Sendable, Equatable {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var c: SIMD3<Float>
    public var color: SIMD4<Float>

    public init(
        a: SIMD3<Float>,
        b: SIMD3<Float>,
        c: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.color = color
    }
}

public struct XRayDebugScene: Sendable, Equatable {
    public var lineSegments: [XRayDebugLineSegment]
    public var filledTriangles: [XRayDebugTriangle]
    public var cameraFrustumColor: SIMD4<Float>?

    public init(
        lineSegments: [XRayDebugLineSegment] = [],
        filledTriangles: [XRayDebugTriangle] = [],
        cameraFrustumColor: SIMD4<Float>? = nil
    ) {
        self.lineSegments = lineSegments
        self.filledTriangles = filledTriangles
        self.cameraFrustumColor = cameraFrustumColor
    }

    public var isEmpty: Bool {
        lineSegments.isEmpty &&
            filledTriangles.isEmpty &&
            cameraFrustumColor == nil
    }
}
