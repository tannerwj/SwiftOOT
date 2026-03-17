import SwiftUI
import OOTRender
import OOTTelemetry
import simd

public struct XRayOverlaySettings: Equatable {
    public var collisionMesh: Bool
    public var actorBounds: Bool
    public var attackColliders: Bool
    public var bodyColliders: Bool
    public var cameraFrustum: Bool
    public var cameraRails: Bool
    public var paths: Bool
    public var triggerVolumes: Bool
    public var actorSpawnPoints: Bool
    public var waterPlanes: Bool

    public init(
        collisionMesh: Bool = false,
        actorBounds: Bool = false,
        attackColliders: Bool = false,
        bodyColliders: Bool = false,
        cameraFrustum: Bool = false,
        cameraRails: Bool = false,
        paths: Bool = false,
        triggerVolumes: Bool = false,
        actorSpawnPoints: Bool = false,
        waterPlanes: Bool = false
    ) {
        self.collisionMesh = collisionMesh
        self.actorBounds = actorBounds
        self.attackColliders = attackColliders
        self.bodyColliders = bodyColliders
        self.cameraFrustum = cameraFrustum
        self.cameraRails = cameraRails
        self.paths = paths
        self.triggerVolumes = triggerVolumes
        self.actorSpawnPoints = actorSpawnPoints
        self.waterPlanes = waterPlanes
    }

    var anyEnabled: Bool {
        collisionMesh ||
            actorBounds ||
            attackColliders ||
            bodyColliders ||
            cameraFrustum ||
            cameraRails ||
            paths ||
            triggerVolumes ||
            actorSpawnPoints ||
            waterPlanes
    }

    var allEnabled: Bool {
        collisionMesh &&
            actorBounds &&
            attackColliders &&
            bodyColliders &&
            cameraFrustum &&
            cameraRails &&
            paths &&
            triggerVolumes &&
            actorSpawnPoints &&
            waterPlanes
    }

    mutating func setAll(_ enabled: Bool) {
        collisionMesh = enabled
        actorBounds = enabled
        attackColliders = enabled
        bodyColliders = enabled
        cameraFrustum = enabled
        cameraRails = enabled
        paths = enabled
        triggerVolumes = enabled
        actorSpawnPoints = enabled
        waterPlanes = enabled
    }

    mutating func toggleAll() {
        setAll(!allEnabled)
    }
}

struct XRayOverlay: View {
    @Binding var settings: XRayOverlaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Collision Mesh", isOn: $settings.collisionMesh)
            Toggle("Actor Bounds", isOn: $settings.actorBounds)
            Toggle("Attack Colliders", isOn: $settings.attackColliders)
            Toggle("Body Colliders", isOn: $settings.bodyColliders)
            Toggle("Camera Frustum", isOn: $settings.cameraFrustum)
            Toggle("Camera Rails", isOn: $settings.cameraRails)
            Toggle("Paths", isOn: $settings.paths)
            Toggle("Trigger Volumes", isOn: $settings.triggerVolumes)
            Toggle("Spawn Points", isOn: $settings.actorSpawnPoints)
            Toggle("Water Planes", isOn: $settings.waterPlanes)
        }
        .toggleStyle(.switch)
    }
}

enum XRayDebugSceneBuilder {
    static func build(
        from snapshot: XRayTelemetrySnapshot?,
        settings: XRayOverlaySettings
    ) -> XRayDebugScene? {
        guard settings.anyEnabled else {
            return nil
        }

        var lineSegments: [XRayDebugLineSegment] = []
        var filledTriangles: [XRayDebugTriangle] = []

        if settings.collisionMesh, let collisionPolygons = snapshot?.scene?.collisionPolygons {
            for polygon in collisionPolygons {
                let color = collisionColor(for: polygon.kind)
                appendPolygonEdges(polygon.vertices.map(\.simd), color: color, to: &lineSegments)
            }
        }

        if settings.cameraRails, let bgCameras = snapshot?.scene?.bgCameras {
            for camera in bgCameras {
                appendSphere(
                    center: camera.position.simd,
                    radius: 10,
                    color: cameraRailColor,
                    to: &lineSegments
                )
                lineSegments.append(
                    XRayDebugLineSegment(
                        start: camera.position.simd,
                        end: camera.position.simd + (camera.forward.simd * 48),
                        color: cameraRailColor
                    )
                )
                appendPolyline(camera.crawlspacePoints.map(\.simd), color: cameraRailColor, to: &lineSegments)
            }
        }

        if settings.paths, let paths = snapshot?.scene?.paths {
            for path in paths {
                appendPolyline(path.points.map(\.simd), color: pathColor, to: &lineSegments)
                for point in path.points {
                    appendSphere(center: point.simd, radius: 8, color: pathColor, to: &lineSegments)
                }
            }
        }

        if settings.triggerVolumes, let triggerVolumes = snapshot?.scene?.triggerVolumes {
            for trigger in triggerVolumes {
                appendBox(
                    minimum: trigger.minimum.simd,
                    maximum: trigger.maximum.simd,
                    color: triggerVolumeColor,
                    to: &lineSegments
                )
            }
        }

        if settings.actorSpawnPoints {
            for spawn in snapshot?.scene?.spawnPoints ?? [] {
                appendSphere(center: spawn.position.simd, radius: 9, color: spawnPointColor, to: &lineSegments)
            }
            for spawn in snapshot?.scene?.actorSpawns ?? [] {
                appendSphere(center: spawn.position.simd, radius: 12, color: actorSpawnColor, to: &lineSegments)
            }
        }

        if settings.waterPlanes, let waterBoxes = snapshot?.scene?.waterBoxes {
            for waterBox in waterBoxes {
                appendWaterPlane(waterBox, to: &lineSegments, triangles: &filledTriangles)
            }
        }

        for actor in snapshot?.activeActors ?? [] {
            if settings.actorBounds {
                if let boundsCollider = actor.boundsCollider {
                    appendCollider(boundsCollider, color: categoryColor(for: actor.category), to: &lineSegments)
                } else {
                    appendSphere(
                        center: actor.position.simd,
                        radius: 14,
                        color: categoryColor(for: actor.category),
                        to: &lineSegments
                    )
                }
            }

            if settings.bodyColliders, let bodyCollider = actor.bodyCollider {
                appendCollider(bodyCollider, color: bodyColliderColor, to: &lineSegments)
            }

            if settings.attackColliders {
                for attackCollider in actor.attackColliders {
                    appendCollider(attackCollider, color: attackColliderColor, to: &lineSegments)
                }
            }
        }

        let debugScene = XRayDebugScene(
            lineSegments: lineSegments,
            filledTriangles: filledTriangles,
            cameraFrustumColor: settings.cameraFrustum ? cameraFrustumColor : nil
        )

        return debugScene.isEmpty ? nil : debugScene
    }
}

private extension XRayDebugSceneBuilder {
    static let walkableColor = SIMD4<Float>(0.18, 0.88, 0.32, 0.95)
    static let wallColor = SIMD4<Float>(0.18, 0.50, 1.00, 0.95)
    static let voidColor = SIMD4<Float>(0.98, 0.24, 0.24, 0.95)
    static let climbableColor = SIMD4<Float>(0.98, 0.84, 0.18, 0.95)
    static let actorSpawnColor = SIMD4<Float>(1.00, 0.62, 0.20, 0.95)
    static let spawnPointColor = SIMD4<Float>(0.98, 0.96, 0.96, 0.95)
    static let pathColor = SIMD4<Float>(0.18, 0.90, 0.92, 0.95)
    static let triggerVolumeColor = SIMD4<Float>(0.98, 0.68, 0.18, 0.9)
    static let waterLineColor = SIMD4<Float>(0.26, 0.58, 1.00, 0.8)
    static let waterFillColor = SIMD4<Float>(0.24, 0.52, 1.00, 0.22)
    static let bodyColliderColor = SIMD4<Float>(0.28, 0.62, 1.00, 0.95)
    static let attackColliderColor = SIMD4<Float>(0.98, 0.22, 0.22, 0.95)
    static let cameraFrustumColor = SIMD4<Float>(0.20, 0.96, 0.96, 0.95)
    static let cameraRailColor = SIMD4<Float>(0.98, 0.92, 0.52, 0.95)
    static let ringSegmentCount = 16

    static func collisionColor(for kind: XRayCollisionKind) -> SIMD4<Float> {
        switch kind {
        case .walkable:
            return walkableColor
        case .wall:
            return wallColor
        case .void:
            return voidColor
        case .climbable:
            return climbableColor
        case .other:
            return SIMD4<Float>(0.9, 0.9, 0.9, 0.9)
        }
    }

    static func categoryColor(for category: String) -> SIMD4<Float> {
        switch category.lowercased() {
        case "player":
            return SIMD4<Float>(1.0, 1.0, 1.0, 0.95)
        case "enemy", "boss":
            return SIMD4<Float>(0.96, 0.36, 0.36, 0.95)
        case "npc":
            return SIMD4<Float>(0.42, 0.92, 0.54, 0.95)
        case "door":
            return SIMD4<Float>(0.88, 0.72, 0.28, 0.95)
        case "chest":
            return SIMD4<Float>(1.0, 0.84, 0.32, 0.95)
        case "item", "bomb":
            return SIMD4<Float>(0.34, 0.96, 0.82, 0.95)
        default:
            return SIMD4<Float>(0.8, 0.78, 0.74, 0.95)
        }
    }

    static func appendCollider(
        _ collider: XRayColliderSnapshot,
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        switch collider.kind {
        case .cylinder:
            guard let cylinder = collider.cylinder else {
                return
            }
            appendCylinder(cylinder, color: color, to: &lineSegments)
        case .triangles:
            for triangle in collider.triangles {
                appendPolygonEdges([triangle.a.simd, triangle.b.simd, triangle.c.simd], color: color, to: &lineSegments)
            }
        }
    }

    static func appendCylinder(
        _ cylinder: XRayCylinder,
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        let center = cylinder.center.simd
        let top = center + SIMD3<Float>(0, cylinder.height, 0)
        let bottomRing = ringPoints(center: center, radius: cylinder.radius)
        let topRing = ringPoints(center: top, radius: cylinder.radius)

        appendLoop(bottomRing, color: color, to: &lineSegments)
        appendLoop(topRing, color: color, to: &lineSegments)

        for index in bottomRing.indices where index < topRing.count {
            lineSegments.append(
                XRayDebugLineSegment(
                    start: bottomRing[index],
                    end: topRing[index],
                    color: color
                )
            )
        }
    }

    static func appendSphere(
        center: SIMD3<Float>,
        radius: Float,
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        appendLoop(
            ringPoints(center: center, radius: radius, axis: SIMD3<Float>(0, 1, 0)),
            color: color,
            to: &lineSegments
        )
        appendLoop(
            ringPoints(center: center, radius: radius, axis: SIMD3<Float>(1, 0, 0)),
            color: color,
            to: &lineSegments
        )
        appendLoop(
            ringPoints(center: center, radius: radius, axis: SIMD3<Float>(0, 0, 1)),
            color: color,
            to: &lineSegments
        )
    }

    static func appendWaterPlane(
        _ waterBox: XRaySceneWaterBoxSnapshot,
        to lineSegments: inout [XRayDebugLineSegment],
        triangles: inout [XRayDebugTriangle]
    ) {
        let minPoint = waterBox.minimum.simd
        let maxPoint = waterBox.maximum.simd
        let a = SIMD3<Float>(minPoint.x, waterBox.ySurface, minPoint.z)
        let b = SIMD3<Float>(maxPoint.x, waterBox.ySurface, minPoint.z)
        let c = SIMD3<Float>(maxPoint.x, waterBox.ySurface, maxPoint.z)
        let d = SIMD3<Float>(minPoint.x, waterBox.ySurface, maxPoint.z)

        triangles.append(XRayDebugTriangle(a: a, b: b, c: c, color: waterFillColor))
        triangles.append(XRayDebugTriangle(a: a, b: c, c: d, color: waterFillColor))
        appendPolygonEdges([a, b, c, d], color: waterLineColor, to: &lineSegments)
    }

    static func appendBox(
        minimum: SIMD3<Float>,
        maximum: SIMD3<Float>,
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        let v000 = SIMD3<Float>(minimum.x, minimum.y, minimum.z)
        let v001 = SIMD3<Float>(minimum.x, minimum.y, maximum.z)
        let v010 = SIMD3<Float>(minimum.x, maximum.y, minimum.z)
        let v011 = SIMD3<Float>(minimum.x, maximum.y, maximum.z)
        let v100 = SIMD3<Float>(maximum.x, minimum.y, minimum.z)
        let v101 = SIMD3<Float>(maximum.x, minimum.y, maximum.z)
        let v110 = SIMD3<Float>(maximum.x, maximum.y, minimum.z)
        let v111 = SIMD3<Float>(maximum.x, maximum.y, maximum.z)

        appendPolygonEdges([v000, v100, v110, v010], color: color, to: &lineSegments)
        appendPolygonEdges([v001, v101, v111, v011], color: color, to: &lineSegments)
        lineSegments.append(XRayDebugLineSegment(start: v000, end: v001, color: color))
        lineSegments.append(XRayDebugLineSegment(start: v100, end: v101, color: color))
        lineSegments.append(XRayDebugLineSegment(start: v110, end: v111, color: color))
        lineSegments.append(XRayDebugLineSegment(start: v010, end: v011, color: color))
    }

    static func appendPolyline(
        _ points: [SIMD3<Float>],
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        guard points.count >= 2 else {
            return
        }

        for index in 0..<(points.count - 1) {
            lineSegments.append(
                XRayDebugLineSegment(
                    start: points[index],
                    end: points[index + 1],
                    color: color
                )
            )
        }
    }

    static func appendLoop(
        _ points: [SIMD3<Float>],
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        guard points.count >= 2 else {
            return
        }

        appendPolygonEdges(points, color: color, to: &lineSegments)
    }

    static func appendPolygonEdges(
        _ points: [SIMD3<Float>],
        color: SIMD4<Float>,
        to lineSegments: inout [XRayDebugLineSegment]
    ) {
        guard points.count >= 2 else {
            return
        }

        for index in points.indices {
            let next = (index + 1) % points.count
            lineSegments.append(
                XRayDebugLineSegment(
                    start: points[index],
                    end: points[next],
                    color: color
                )
            )
        }
    }

    static func ringPoints(
        center: SIMD3<Float>,
        radius: Float,
        axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    ) -> [SIMD3<Float>] {
        let normalizedAxis = simd_normalize(axis)
        let reference = abs(normalizedAxis.y) > 0.9
            ? SIMD3<Float>(1, 0, 0)
            : SIMD3<Float>(0, 1, 0)
        let tangent = simd_normalize(simd_cross(normalizedAxis, reference))
        let bitangent = simd_normalize(simd_cross(normalizedAxis, tangent))

        return (0..<ringSegmentCount).map { index in
            let angle = (Float(index) / Float(ringSegmentCount)) * (.pi * 2)
            return center + ((tangent * cos(angle)) + (bitangent * sin(angle))) * radius
        }
    }
}
