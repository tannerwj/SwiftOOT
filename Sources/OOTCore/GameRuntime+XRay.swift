import OOTContent
import OOTDataModel
import OOTTelemetry
import simd

extension GameRuntime {
    public var xrayTelemetrySnapshot: XRayTelemetrySnapshot? {
        (telemetryPublisher as? TelemetryPublisher)?.xraySnapshot
    }

    func syncXRayTelemetry() {
        telemetryPublisher.publish(xraySnapshot: makeXRayTelemetrySnapshot())
    }

    func clearXRayTelemetry() {
        telemetryPublisher.publish(xraySnapshot: nil)
    }

    func xrayPlayerAttackCollider() -> CombatCollider? {
        currentXRayPlayerAttackCollider()
    }
}

private extension GameRuntime {
    func makeXRayTelemetrySnapshot() -> XRayTelemetrySnapshot? {
        guard let loadedScene else {
            return nil
        }

        return XRayTelemetrySnapshot(
            scene: makeXRaySceneSnapshot(from: loadedScene),
            activeActors: makeXRayActiveActorSnapshots()
        )
    }

    func makeXRaySceneSnapshot(from scene: LoadedScene) -> XRaySceneSnapshot {
        XRaySceneSnapshot(
            collisionPolygons: makeXRayCollisionPolygons(from: scene.collision),
            bgCameras: makeXRayBgCameras(from: scene.collision),
            waterBoxes: makeXRayWaterBoxes(from: scene.collision),
            paths: (scene.paths?.paths ?? []).map { path in
                XRayScenePathSnapshot(
                    index: path.index,
                    pointsName: path.pointsName,
                    points: path.points.map(XRayVector3.init)
                )
            },
            triggerVolumes: makeXRayTriggerVolumes(from: scene),
            spawnPoints: (scene.spawns?.spawns ?? scene.sceneHeader?.spawns ?? []).map { spawn in
                XRaySceneSpawnSnapshot(
                    index: spawn.index,
                    roomID: spawn.roomID,
                    position: XRayVector3(spawn.position),
                    rotation: XRayVector3(spawn.rotation)
                )
            },
            actorSpawns: (scene.actors?.rooms ?? []).flatMap { room in
                room.actors.map { actor in
                    XRaySceneActorSpawnSnapshot(
                        actorID: actor.actorID,
                        actorName: actor.actorName,
                        roomName: room.roomName,
                        position: XRayVector3(actor.position),
                        rotation: XRayVector3(actor.rotation)
                    )
                }
            }
        )
    }

    func makeXRayTriggerVolumes(from scene: LoadedScene) -> [XRaySceneTriggerSnapshot] {
        let transitionTriggers = (scene.sceneHeader?.transitionTriggers ?? []).map { trigger in
            XRaySceneTriggerSnapshot(
                id: trigger.id,
                source: .transition,
                kind: trigger.kind.rawValue,
                minimum: XRayVector3(trigger.volume.minimum),
                maximum: XRayVector3(trigger.volume.maximum)
            )
        }
        let cutsceneTriggers = (scene.sceneHeader?.cutsceneTriggers ?? []).map { trigger in
            XRaySceneTriggerSnapshot(
                id: trigger.id,
                source: .cutscene,
                kind: trigger.kind,
                cylinder: makeTriggerCylinder(trigger.volume, collision: scene.collision)
            )
        }
        let eventRegionTriggers = (scene.sceneHeader?.eventRegionTriggers ?? []).map { trigger in
            XRaySceneTriggerSnapshot(
                id: trigger.id,
                source: .eventRegion,
                kind: trigger.kind,
                cylinder: makeTriggerCylinder(trigger.volume, collision: scene.collision)
            )
        }
        return transitionTriggers + cutsceneTriggers + eventRegionTriggers
    }

    func makeTriggerCylinder(
        _ volume: SceneCylinderTriggerVolume,
        collision: CollisionMesh?
    ) -> XRayCylinder {
        let fallbackMinimumY = Int16(clamping: Int(volume.center.y) - 200)
        let fallbackMaximumY = Int16(clamping: Int(volume.center.y) + 200)
        var minimumY = volume.minimumY ?? collision?.minimumBounds.y ?? fallbackMinimumY
        var maximumY = volume.maximumY ?? collision?.maximumBounds.y ?? fallbackMaximumY

        if volume.minimumY == nil, volume.maximumY == nil, minimumY == maximumY {
            minimumY = fallbackMinimumY
            maximumY = fallbackMaximumY
        }

        let baseY = min(minimumY, maximumY)
        let height = max(0, Int(maximumY) - Int(baseY))

        return XRayCylinder(
            center: XRayVector3(x: Float(volume.center.x), y: Float(baseY), z: Float(volume.center.z)),
            radius: Float(volume.radius),
            height: Float(height)
        )
    }

    func makeXRayActiveActorSnapshots() -> [XRayActorSnapshot] {
        var snapshots: [XRayActorSnapshot] = []

        if let playerState {
            let bodyCollider = XRayColliderSnapshot(
                role: .body,
                kind: .cylinder,
                cylinder: XRayCylinder(
                    center: XRayVector3(playerState.position.simd),
                    radius: PlayerMovementConfiguration().collisionRadius,
                    height: 44
                )
            )
            var attackColliders: [XRayColliderSnapshot] = []
            if let attackCollider = xrayPlayerAttackCollider() {
                attackColliders.append(makeColliderSnapshot(from: attackCollider, role: .attack))
            }
            snapshots.append(
                XRayActorSnapshot(
                    profileID: -1,
                    actorType: "Player",
                    category: "player",
                    roomID: playState?.currentRoomID,
                    position: XRayVector3(playerState.position.simd),
                    rotation: XRayVector3(x: 0, y: playerState.facingRadians, z: 0),
                    boundsCollider: XRayColliderSnapshot(
                        role: .actorBounds,
                        kind: .cylinder,
                        cylinder: bodyCollider.cylinder
                    ),
                    bodyCollider: bodyCollider,
                    attackColliders: attackColliders
                )
            )
        }

        snapshots.append(
            contentsOf: actors.map { actor in
                let bodyCollider = (actor as? any CombatActor).map {
                    makeColliderSnapshot(
                        from: CombatCollider(
                            initialization: ColliderInit(collisionMask: [.ac]),
                            shape: .cylinder($0.hurtbox)
                        ),
                        role: .body
                    )
                }
                let boundsCollider = bodyCollider.map {
                    XRayColliderSnapshot(
                        role: .actorBounds,
                        kind: $0.kind,
                        cylinder: $0.cylinder,
                        triangles: $0.triangles
                    )
                }
                let attackColliders = (actor as? any CombatActor)?.activeAttacks.map {
                    makeColliderSnapshot(from: $0.collider, role: .attack)
                } ?? []
                let baseActor = actor as? BaseActor

                return XRayActorSnapshot(
                    profileID: actor.profile.id,
                    actorType: String(describing: type(of: actor)),
                    category: actorCategoryName(for: actor),
                    roomID: baseActor?.roomID,
                    position: XRayVector3(actor.position.simd),
                    rotation: XRayVector3(baseActor?.rotation ?? .init(x: 0, y: 0, z: 0)),
                    spawnPosition: baseActor.map { XRayVector3($0.spawnPosition) },
                    boundsCollider: boundsCollider,
                    bodyCollider: bodyCollider,
                    attackColliders: attackColliders
                )
            }
        )

        return snapshots
    }

    func makeXRayCollisionPolygons(from collision: CollisionMesh?) -> [XRayCollisionPolygon] {
        guard let collision else {
            return []
        }

        return collision.polygons.compactMap { polygon in
            guard
                collision.vertices.indices.contains(Int(polygon.vertexA)),
                collision.vertices.indices.contains(Int(polygon.vertexB)),
                collision.vertices.indices.contains(Int(polygon.vertexC))
            else {
                return nil
            }

            return XRayCollisionPolygon(
                kind: classifyCollisionPolygon(polygon, in: collision),
                surfaceTypeIndex: Int(polygon.surfaceType),
                vertices: [
                    XRayVector3(collision.vertices[Int(polygon.vertexA)]),
                    XRayVector3(collision.vertices[Int(polygon.vertexB)]),
                    XRayVector3(collision.vertices[Int(polygon.vertexC)]),
                ]
            )
        }
    }

    func makeXRayBgCameras(from collision: CollisionMesh?) -> [XRaySceneBgCameraSnapshot] {
        guard let collision else {
            return []
        }

        return collision.bgCameras.enumerated().map { index, bgCamera in
            let crawlspacePoints = bgCamera.crawlspacePoints.map(XRayVector3.init)

            guard let cameraData = bgCamera.cameraData else {
                return XRaySceneBgCameraSnapshot(
                    index: index,
                    position: XRayVector3(x: 0, y: 0, z: 0),
                    forward: XRayVector3(x: 0, y: 0, z: -1),
                    fieldOfViewRadians: .pi / 3,
                    crawlspacePoints: crawlspacePoints
                )
            }

            let pitch = binaryAngleToRadians(cameraData.rotation.x)
            let yaw = binaryAngleToRadians(cameraData.rotation.y)
            let forward = normalize(
                SIMD3<Float>(
                    sin(yaw) * cos(pitch),
                    -sin(pitch),
                    cos(yaw) * cos(pitch)
                ),
                fallback: SIMD3<Float>(0, 0, -1)
            )
            let fovDegrees = Float(cameraData.fov) > 360
                ? Float(cameraData.fov) * 0.01
                : Float(cameraData.fov)

            return XRaySceneBgCameraSnapshot(
                index: index,
                position: XRayVector3(cameraData.position),
                forward: XRayVector3(forward),
                fieldOfViewRadians: clamp(fovDegrees * .pi / 180.0, .pi / 8.0, .pi * 0.75),
                crawlspacePoints: crawlspacePoints
            )
        }
    }

    func makeXRayWaterBoxes(from collision: CollisionMesh?) -> [XRaySceneWaterBoxSnapshot] {
        guard let collision else {
            return []
        }

        return collision.waterBoxes.map { waterBox in
            XRaySceneWaterBoxSnapshot(
                minimum: XRayVector3(
                    x: Float(waterBox.xMin),
                    y: Float(waterBox.ySurface),
                    z: Float(waterBox.zMin)
                ),
                maximum: XRayVector3(
                    x: Float(waterBox.xMin) + Float(waterBox.xLength),
                    y: Float(waterBox.ySurface),
                    z: Float(waterBox.zMin) + Float(waterBox.zLength)
                ),
                ySurface: Float(waterBox.ySurface)
            )
        }
    }

    func makeColliderSnapshot(
        from collider: CombatCollider,
        role: XRayColliderRole
    ) -> XRayColliderSnapshot {
        switch collider.shape {
        case .cylinder(let cylinder):
            return XRayColliderSnapshot(
                role: role,
                kind: .cylinder,
                cylinder: XRayCylinder(
                    center: XRayVector3(cylinder.center.simd),
                    radius: cylinder.radius,
                    height: cylinder.height
                )
            )
        case .tris(let tris):
            return XRayColliderSnapshot(
                role: role,
                kind: .triangles,
                triangles: tris.triangles.map { triangle in
                    XRayTriangle(
                        a: XRayVector3(triangle.a.simd),
                        b: XRayVector3(triangle.b.simd),
                        c: XRayVector3(triangle.c.simd)
                    )
                }
            )
        }
    }

    func classifyCollisionPolygon(
        _ polygon: CollisionPoly,
        in collision: CollisionMesh
    ) -> XRayCollisionKind {
        let surfaceType = collision.surfaceType(for: polygon)
        let normal = normalize(
            SIMD3<Float>(
                Float(polygon.normal.x),
                Float(polygon.normal.y),
                Float(polygon.normal.z)
            ),
            fallback: SIMD3<Float>(0, 1, 0)
        )

        if surfaceType?.canHookshot == true {
            return .climbable
        }
        if normal.y > 0.55 {
            return .walkable
        }
        if normal.y < -0.55 {
            return .void
        }
        if abs(normal.y) <= 0.55 {
            return .wall
        }
        return .other
    }

    func actorCategoryName(for actor: any Actor) -> String {
        if let baseActor = actor as? BaseActor {
            return String(describing: baseActor.category)
        }

        if let category = ActorCategory(rawValue: actor.profile.category) {
            return String(describing: category)
        }

        return "misc"
    }

    func binaryAngleToRadians(_ value: Int16) -> Float {
        Float(value) * (.pi / 32_768.0)
    }

    func normalize(
        _ vector: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let length = simd_length(vector)
        guard length > 0.000_1 else {
            return fallback
        }

        return vector / length
    }

    func clamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
