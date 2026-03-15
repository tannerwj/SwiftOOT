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
        let vertex = N64Vertex(
            position: Vector3s(x: 1, y: 2, z: 3),
            flag: 0,
            textureCoordinate: Vector2s(x: 4, y: 5),
            colorOrNormal: RGBA8(red: 255, green: 128, blue: 64, alpha: 255)
        )
        let room = RoomManifest(
            id: 0,
            name: "Inside Deku Tree",
            objectIDs: [1, 2],
            actors: [ActorProfile(id: 1, category: 5, flags: 0x20, objectID: 3)],
            mesh: MeshData(vertices: [vertex], indices: [0])
        )
        let manifest = SceneManifest(
            id: 1,
            name: "ydan",
            title: "Inside the Deku Tree",
            rooms: [room],
            objectIDs: [1, 2, 3],
            collision: CollisionMesh(
                vertices: [Vector3s(x: 0, y: 0, z: 0)],
                polygons: [
                    CollisionPoly(
                        surfaceType: 1,
                        vertexA: 0,
                        vertexB: 0,
                        vertexC: 0,
                        normal: Vector3s(x: 0, y: 1, z: 0),
                        distance: 0
                    )
                ]
            )
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SceneManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    private func assertCodableAndSendable<T: Codable & Sendable>(_: T.Type) {
        XCTAssertTrue(true)
    }
}
