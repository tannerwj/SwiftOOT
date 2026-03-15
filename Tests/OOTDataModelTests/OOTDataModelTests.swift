import XCTest
@testable import OOTDataModel

final class OOTDataModelTests: XCTestCase {
    func testN64VertexMatchesExpectedBinarySize() {
        XCTAssertEqual(MemoryLayout<N64Vertex>.size, 16)
    }

    func testFoundationalModelsSatisfyCodableAndSendableConstraints() {
        assertCodableAndSendable(F3DEX2Command.self)
        assertCodableAndSendable(N64Vertex.self)
        assertCodableAndSendable(RGB8.self)
        assertCodableAndSendable(SceneManifest.self)
        assertCodableAndSendable(SceneActorSpawn.self)
        assertCodableAndSendable(SceneActorsFile.self)
        assertCodableAndSendable(SceneSpawnPoint.self)
        assertCodableAndSendable(SceneSpawnsFile.self)
        assertCodableAndSendable(SceneEnvironmentFile.self)
        assertCodableAndSendable(SceneExitsFile.self)
        assertCodableAndSendable(SceneExitDefinition.self)
        assertCodableAndSendable(SceneLightSetting.self)
        assertCodableAndSendable(ScenePathDefinition.self)
        assertCodableAndSendable(ScenePathsFile.self)
        assertCodableAndSendable(SceneSkyboxSettings.self)
        assertCodableAndSendable(SceneTimeSettings.self)
        assertCodableAndSendable(RoomManifest.self)
        assertCodableAndSendable(RoomActorSpawns.self)
        assertCodableAndSendable(ActorProfile.self)
        assertCodableAndSendable(TextureDescriptor.self)
        assertCodableAndSendable(TextureAssetMetadata.self)
        assertCodableAndSendable(SceneTableEntry.self)
        assertCodableAndSendable(ActorTableEntry.self)
        assertCodableAndSendable(ObjectTableEntry.self)
        assertCodableAndSendable(Vector3b.self)
        assertCodableAndSendable(CollisionMesh.self)
        assertCodableAndSendable(CollisionPoly.self)
        assertCodableAndSendable(CollisionSurfaceType.self)
        assertCodableAndSendable(CollisionBgCameraData.self)
        assertCodableAndSendable(CollisionBgCamera.self)
        assertCodableAndSendable(CollisionWaterBox.self)
        assertCodableAndSendable(SkeletonData.self)
        assertCodableAndSendable(AnimationData.self)
        assertCodableAndSendable(LimbData.self)
        assertCodableAndSendable(MeshData.self)
        assertCodableAndSendable(ObjectManifest.self)
        assertCodableAndSendable(ObjectAnimationReference.self)
        assertCodableAndSendable(ObjectMeshAsset.self)
        assertCodableAndSendable(ObjectSkeletonFile.self)
        assertCodableAndSendable(NamedSkeletonData.self)
        assertCodableAndSendable(ObjectAnimationData.self)
        assertCodableAndSendable(AnimationJointIndex.self)
    }

    func testF3DEX2CommandRoundTripsThroughJSON() throws {
        let command = F3DEX2Command.dpSetTile(
            TileDescriptor(
                format: .rgba16,
                texelSize: .bits16,
                line: 8,
                tmem: 0,
                tile: 0,
                palette: 0,
                clampS: false,
                mirrorS: false,
                maskS: 5,
                shiftS: 0,
                clampT: true,
                mirrorT: false,
                maskT: 5,
                shiftT: 0
            )
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(F3DEX2Command.self, from: data)

        XCTAssertEqual(decoded, command)
    }

    func testSceneManifestEncodesNestedFoundationalTypes() throws {
        let room = RoomManifest(
            id: 0,
            name: "spot04_room_0",
            directory: "Scenes/spot04/rooms/room_0",
            textureDirectories: ["Textures/spot04_room_0"]
        )
        let manifest = SceneManifest(
            id: 0x55,
            name: "spot04",
            title: "g_pn_31",
            drawConfig: 0,
            rooms: [room],
            collisionPath: "Scenes/spot04/collision.bin",
            actorsPath: "Manifests/scenes/overworld/spot04/actors.json",
            spawnsPath: "Manifests/scenes/overworld/spot04/spawns.json",
            environmentPath: "Manifests/scenes/overworld/spot04/environment.json",
            pathsPath: "Manifests/scenes/overworld/spot04/paths.json",
            exitsPath: "Manifests/scenes/overworld/spot04/exits.json",
            textureDirectories: ["Textures/spot04_scene"]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SceneManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    private func assertCodableAndSendable<T: Codable & Sendable>(_: T.Type) {
        XCTAssertTrue(true)
    }
}
