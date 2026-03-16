import Foundation
import OOTCore
import OOTDataModel

struct ChestRuntimeContentFixture {
    let root: URL
    let contentRoot: URL
    let sceneID = 0x66
    let sceneName = "chest_test"

    var sceneIdentity: SceneIdentity {
        SceneIdentity(id: sceneID, name: sceneName)
    }

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(
            "swiftoot-chest-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        contentRoot = root
            .appendingPathComponent("Content", isDirectory: true)
            .appendingPathComponent("OOT", isDirectory: true)

        try fileManager.createDirectory(at: contentRoot, withIntermediateDirectories: true)
        try seedSceneTable()
        try seedActorTable()
        try seedObjectTable()
        try seedScene()
        try seedPlayerObject()
        try seedChestObject()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private func seedSceneTable() throws {
        try writeJSON(
            [
                SceneTableEntry(
                    index: sceneID,
                    segmentName: "\(sceneName)_scene",
                    enumName: "SCENE_CHEST_TEST"
                )
            ],
            to: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("scene-table.json")
        )
    }

    private func seedActorTable() throws {
        try writeJSON(
            [
                ActorTableEntry(
                    id: 10,
                    enumName: "ACTOR_EN_BOX",
                    profile: ActorProfile(
                        id: 10,
                        category: ActorCategory.chest.rawValue,
                        flags: 0,
                        objectID: 2
                    )
                )
            ],
            to: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("actor-table.json")
        )
    }

    private func seedObjectTable() throws {
        try writeJSON(
            [
                ObjectTableEntry(id: 1, enumName: "OBJECT_LINK_BOY", assetPath: "Objects/object_link_boy"),
                ObjectTableEntry(id: 2, enumName: "OBJECT_BOX", assetPath: "Objects/object_box"),
            ],
            to: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("object-table.json")
        )
    }

    private func seedScene() throws {
        let sceneDirectory = contentRoot
            .appendingPathComponent("Scenes", isDirectory: true)
            .appendingPathComponent(sceneName, isDirectory: true)
        let metadataRoot = contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
            .appendingPathComponent("tests", isDirectory: true)
            .appendingPathComponent(sceneName, isDirectory: true)

        let room = RoomManifest(
            id: 0,
            name: "\(sceneName)_room_0",
            directory: "Scenes/\(sceneName)/rooms/room_0"
        )
        try writeJSON(
            SceneManifest(
                id: sceneID,
                name: sceneName,
                rooms: [room],
                actorsPath: "Manifests/scenes/tests/\(sceneName)/actors.json",
                spawnsPath: "Manifests/scenes/tests/\(sceneName)/spawns.json",
                sceneHeaderPath: "Manifests/scenes/tests/\(sceneName)/scene-header.json"
            ),
            to: sceneDirectory.appendingPathComponent("SceneManifest.json")
        )

        try writeJSON(
            SceneActorsFile(
                sceneName: sceneName,
                rooms: [
                    RoomActorSpawns(
                        roomName: room.name,
                        actors: [
                            SceneActorSpawn(
                                actorID: 10,
                                actorName: "ACTOR_EN_BOX",
                                position: Vector3s(x: 0, y: 0, z: -36),
                                rotation: Vector3s(x: 0, y: 0, z: 0),
                                params: Int16(bitPattern: UInt16((0x40 << 5) | 3))
                            )
                        ]
                    )
                ]
            ),
            to: metadataRoot.appendingPathComponent("actors.json")
        )
        try writeJSON(
            SceneSpawnsFile(
                sceneName: sceneName,
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    )
                ]
            ),
            to: metadataRoot.appendingPathComponent("spawns.json")
        )
        try writeJSON(
            SceneHeaderDefinition(
                sceneName: sceneName,
                sceneObjectIDs: [1, 2],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    )
                ],
                rooms: [
                    SceneRoomDefinition(
                        id: 0,
                        shape: .normal,
                        objectIDs: [1, 2]
                    )
                ]
            ),
            to: metadataRoot.appendingPathComponent("scene-header.json")
        )

        try seedRoomGeometry(in: sceneDirectory)
    }

    private func seedRoomGeometry(in sceneDirectory: URL) throws {
        let roomDirectory = sceneDirectory
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("room_0", isDirectory: true)
        try FileManager.default.createDirectory(at: roomDirectory, withIntermediateDirectories: true)

        let vertices = [
            N64Vertex(
                position: Vector3s(x: -24, y: -10, z: -80),
                flag: 0,
                textureCoordinate: .init(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 0, y: 24, z: -80),
                flag: 0,
                textureCoordinate: .init(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 24, y: -10, z: -80),
                flag: 0,
                textureCoordinate: .init(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
            ),
        ]

        try vertexBinary(for: vertices).write(
            to: roomDirectory.appendingPathComponent("vtx.bin"),
            options: .atomic
        )
        try writeJSON(
            [
                F3DEX2Command.spVertex(
                    VertexCommand(address: 0x03000000, count: 3, destinationIndex: 0)
                ),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ],
            to: roomDirectory.appendingPathComponent("dl.json")
        )
    }

    private func seedPlayerObject() throws {
        try seedObject(
            name: "object_link_boy",
            skeletonName: "gLinkAdultSkel",
            meshName: "gLinkFixtureMesh",
            animations: [
                (
                    name: "gLinkIdleAnim",
                    kind: .player,
                    data: ObjectAnimationData(
                        name: "gLinkIdleAnim",
                        kind: .player,
                        frameCount: 1,
                        values: [0, 0, 0, 0],
                        limbCount: 1
                    )
                ),
                (
                    name: "gLinkWalkAnim",
                    kind: .player,
                    data: ObjectAnimationData(
                        name: "gLinkWalkAnim",
                        kind: .player,
                        frameCount: 1,
                        values: [0, 0, 0, 0],
                        limbCount: 1
                    )
                ),
                (
                    name: "gLinkRunAnim",
                    kind: .player,
                    data: ObjectAnimationData(
                        name: "gLinkRunAnim",
                        kind: .player,
                        frameCount: 1,
                        values: [0, 0, 0, 0],
                        limbCount: 1
                    )
                ),
                (
                    name: "gLinkDemoGetItemAAnim",
                    kind: .player,
                    data: ObjectAnimationData(
                        name: "gLinkDemoGetItemAAnim",
                        kind: .player,
                        frameCount: 1,
                        values: [0, 0, 0, 0],
                        limbCount: 1
                    )
                ),
                (
                    name: "gLinkDemoGetItemBAnim",
                    kind: .player,
                    data: ObjectAnimationData(
                        name: "gLinkDemoGetItemBAnim",
                        kind: .player,
                        frameCount: 1,
                        values: [0, 0, 0, 0],
                        limbCount: 1
                    )
                ),
            ]
        )
    }

    private func seedChestObject() throws {
        try seedObject(
            name: "object_box",
            skeletonName: "gTreasureChestSkel",
            meshName: "gTreasureChestFixtureMesh",
            animations: [
                (
                    name: "TreasureChestAnimOpen",
                    kind: .standard,
                    data: ObjectAnimationData(
                        name: "TreasureChestAnimOpen",
                        kind: .standard,
                        frameCount: 1,
                        values: [0, 0, 0],
                        jointIndices: [AnimationJointIndex(x: 0, y: 1, z: 2)],
                        staticIndexMax: 3,
                        limbCount: 1
                    )
                )
            ]
        )
    }

    private func seedObject(
        name: String,
        skeletonName: String,
        meshName: String,
        animations: [(name: String, kind: ObjectAnimationKind, data: ObjectAnimationData)]
    ) throws {
        let objectDirectory = contentRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let displayListPath = "meshes/\(meshName).dl.json"
        let vertexPath = "meshes/\(meshName).vtx.bin"

        try writeJSON(
            ObjectManifest(
                name: name,
                skeletonPath: "skeleton.json",
                animations: animations.map { animation in
                    ObjectAnimationReference(
                        name: animation.name,
                        kind: animation.kind,
                        path: "animations/\(animation.name).json"
                    )
                },
                meshes: [
                    ObjectMeshAsset(
                        name: meshName,
                        displayListPath: displayListPath,
                        vertexPaths: [vertexPath]
                    )
                ]
            ),
            to: objectDirectory.appendingPathComponent("object_manifest.json")
        )
        try writeJSON(
            ObjectSkeletonFile(
                skeletons: [
                    NamedSkeletonData(
                        name: skeletonName,
                        skeleton: SkeletonData(
                            type: .normal,
                            limbs: [
                                LimbData(
                                    translation: Vector3s(x: 0, y: 0, z: 0),
                                    displayListPath: displayListPath
                                )
                            ]
                        )
                    )
                ]
            ),
            to: objectDirectory.appendingPathComponent("skeleton.json")
        )

        for animation in animations {
            try writeJSON(
                animation.data,
                to: objectDirectory
                    .appendingPathComponent("animations", isDirectory: true)
                    .appendingPathComponent("\(animation.name).json")
            )
        }

        let vertexSymbol = URL(fileURLWithPath: vertexPath)
            .deletingPathExtension()
            .deletingPathExtension()
            .lastPathComponent
        try writeJSON(
            [
                F3DEX2Command.spVertex(
                    VertexCommand(
                        address: OOTAssetID.stableID(for: vertexSymbol),
                        count: 3,
                        destinationIndex: 0
                    )
                ),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ],
            to: objectDirectory.appendingPathComponent(displayListPath)
        )
        try vertexBinary(
            for: [
                N64Vertex(
                    position: Vector3s(x: -8, y: 0, z: 0),
                    flag: 0,
                    textureCoordinate: .init(x: 0, y: 0),
                    colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
                ),
                N64Vertex(
                    position: Vector3s(x: 0, y: 16, z: 0),
                    flag: 0,
                    textureCoordinate: .init(x: 0, y: 0),
                    colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
                ),
                N64Vertex(
                    position: Vector3s(x: 8, y: 0, z: 0),
                    flag: 0,
                    textureCoordinate: .init(x: 0, y: 0),
                    colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
                ),
            ]
        ).write(
            to: objectDirectory.appendingPathComponent(vertexPath),
            options: .atomic
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func vertexBinary(for vertices: [N64Vertex]) -> Data {
        var data = Data()
        data.reserveCapacity(vertices.count * 16)

        for vertex in vertices {
            append(vertex.position.x, to: &data)
            append(vertex.position.y, to: &data)
            append(vertex.position.z, to: &data)
            append(vertex.flag, to: &data)
            append(vertex.textureCoordinate.x, to: &data)
            append(vertex.textureCoordinate.y, to: &data)
            data.append(contentsOf: [
                vertex.colorOrNormal.red,
                vertex.colorOrNormal.green,
                vertex.colorOrNormal.blue,
                vertex.colorOrNormal.alpha,
            ])
        }

        return data
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
