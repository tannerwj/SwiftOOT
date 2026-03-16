import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class ObjectExtractorTests: XCTestCase {
    func testSceneScopedExtractionIncludesRequiredObjectsForSelectedSceneSet() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        func writeMinimalObject(named name: String, symbolPrefix: String) throws {
            try harness.writeFile(
                at: "assets/xml/objects/\(name).xml",
                contents: """
                <Root>
                    <File Name="\(name)" Segment="6">
                        <Array Name="\(symbolPrefix)MeshVtx" Count="3" Offset="0x20">
                            <Vtx/>
                        </Array>
                        <DList Name="\(symbolPrefix)MeshDL" Offset="0x80"/>
                        <Limb Name="\(symbolPrefix)RootLimb" LimbType="Standard" Offset="0xA0"/>
                        <Skeleton Name="\(symbolPrefix)Skel" Type="Normal" LimbType="Standard" Offset="0xC0"/>
                    </File>
                </Root>
                """
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(name).c",
                contents: """
                Vtx \(symbolPrefix)MeshVtx[] = {
                #include "assets/objects/\(name)/\(symbolPrefix)MeshVtx.inc.c"
                };

                Gfx \(symbolPrefix)MeshDL[] = {
                #include "assets/objects/\(name)/\(symbolPrefix)MeshDL.inc.c"
                };

                StandardLimb \(symbolPrefix)RootLimb = {
                #include "assets/objects/\(name)/\(symbolPrefix)RootLimb.inc.c"
                };

                void* \(symbolPrefix)Limbs[] = {
                #include "assets/objects/\(name)/\(symbolPrefix)Limbs.inc.c"
                };

                SkeletonHeader \(symbolPrefix)Skel = {
                #include "assets/objects/\(name)/\(symbolPrefix)Skel.inc.c"
                };
                """
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(symbolPrefix)MeshVtx.inc.c",
                contents: """
                VTX(0, 0, 0, 0, 0, 0, 255, 0, 0),
                VTX(10, 0, 0, 0, 32, 0, 0, 255, 0),
                VTX(0, 10, 0, 0, 0, 32, 0, 0, 255),
                """
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(symbolPrefix)MeshDL.inc.c",
                contents: """
                gsSPVertex(\(symbolPrefix)MeshVtx, 3, 0),
                gsSP1Triangle(0, 1, 2, 0),
                gsSPEndDisplayList(),
                """
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(symbolPrefix)RootLimb.inc.c",
                contents: "{ 0, 0, 0 }, 255, 255, \(symbolPrefix)MeshDL\n"
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(symbolPrefix)Limbs.inc.c",
                contents: "&\(symbolPrefix)RootLimb,\n"
            )
            try harness.writeFile(
                at: "assets/objects/\(name)/\(symbolPrefix)Skel.inc.c",
                contents: "\(symbolPrefix)Limbs, 1\n"
            )
        }

        try writeMinimalObject(named: "object_link_boy", symbolPrefix: "gLinkBoy")
        try writeMinimalObject(named: "object_required_a", symbolPrefix: "gRequiredA")
        try writeMinimalObject(named: "object_required_b", symbolPrefix: "gRequiredB")
        try writeMinimalObject(named: "object_unused", symbolPrefix: "gUnused")

        let encoder = JSONEncoder()
        let tablesDirectory = harness.outputRoot
            .appendingPathComponent("Manifests/tables", isDirectory: true)
        try FileManager.default.createDirectory(at: tablesDirectory, withIntermediateDirectories: true)

        try encoder.encode([
            ObjectTableEntry(id: 101, enumName: "OBJECT_REQUIRED_A", assetPath: "Objects/object_required_a"),
            ObjectTableEntry(id: 102, enumName: "OBJECT_REQUIRED_B", assetPath: "Objects/object_required_b"),
            ObjectTableEntry(id: 103, enumName: "OBJECT_UNUSED", assetPath: "Objects/object_unused"),
        ]).write(to: tablesDirectory.appendingPathComponent("object-table.json"))

        try encoder.encode([
            ActorTableEntry(
                id: 11,
                enumName: "ACTOR_REQUIRED_A",
                profile: ActorProfile(id: 11, category: 4, flags: 0, objectID: 101)
            ),
            ActorTableEntry(
                id: 12,
                enumName: "ACTOR_UNUSED",
                profile: ActorProfile(id: 12, category: 4, flags: 0, objectID: 103)
            ),
        ]).write(to: tablesDirectory.appendingPathComponent("actor-table.json"))

        let spot00Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot00", isDirectory: true)
        let spot01Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot01", isDirectory: true)
        let spot02Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot02", isDirectory: true)
        try FileManager.default.createDirectory(at: spot00Directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: spot01Directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: spot02Directory, withIntermediateDirectories: true)

        try encoder.encode(
            SceneHeaderDefinition(
                sceneName: "spot00",
                rooms: [SceneRoomDefinition(id: 0, shape: .normal)]
            )
        ).write(to: spot00Directory.appendingPathComponent("scene-header.json"))
        try encoder.encode(
            SceneActorsFile(
                sceneName: "spot00",
                rooms: [
                    RoomActorSpawns(
                        roomName: "spot00_room_0",
                        actors: [
                            SceneActorSpawn(
                                actorID: 11,
                                actorName: "ACTOR_REQUIRED_A",
                                position: .init(x: 0, y: 0, z: 0),
                                rotation: .init(x: 0, y: 0, z: 0),
                                params: 0
                            ),
                        ]
                    ),
                ]
            )
        ).write(to: spot00Directory.appendingPathComponent("actors.json"))

        try encoder.encode(
            SceneHeaderDefinition(
                sceneName: "spot01",
                rooms: [SceneRoomDefinition(id: 0, shape: .normal, objectIDs: [102])]
            )
        ).write(to: spot01Directory.appendingPathComponent("scene-header.json"))
        try encoder.encode(
            SceneActorsFile(sceneName: "spot01", rooms: [])
        ).write(to: spot01Directory.appendingPathComponent("actors.json"))

        try encoder.encode(
            SceneHeaderDefinition(
                sceneName: "spot02",
                rooms: [SceneRoomDefinition(id: 0, shape: .normal)]
            )
        ).write(to: spot02Directory.appendingPathComponent("scene-header.json"))
        try encoder.encode(
            SceneActorsFile(
                sceneName: "spot02",
                rooms: [
                    RoomActorSpawns(
                        roomName: "spot02_room_0",
                        actors: [
                            SceneActorSpawn(
                                actorID: 12,
                                actorName: "ACTOR_UNUSED",
                                position: .init(x: 0, y: 0, z: 0),
                                rotation: .init(x: 0, y: 0, z: 0),
                                params: 0
                            ),
                        ]
                    ),
                ]
            )
        ).write(to: spot02Directory.appendingPathComponent("actors.json"))

        try ObjectExtractor().extract(using: harness.extractionContext(sceneNames: ["spot00", "spot01"]))

        let objectsRoot = harness.outputRoot.appendingPathComponent("Objects", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectsRoot.appendingPathComponent("object_link_boy/object_manifest.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectsRoot.appendingPathComponent("object_required_a/object_manifest.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectsRoot.appendingPathComponent("object_required_b/object_manifest.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: objectsRoot.appendingPathComponent("object_unused/object_manifest.json").path
            )
        )
    }

    func testExtractWritesManifestSkeletonAnimationMeshAndCopiedTextures() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        try harness.writeFile(
            at: "assets/xml/objects/object_test.xml",
            contents: """
            <Root>
                <File Name="object_test" Segment="6">
                    <Texture Name="gObjectTestTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Array Name="gObjectTestMeshVtx" Count="3" Offset="0x20">
                        <Vtx/>
                    </Array>
                    <DList Name="gObjectTestMeshDL" Offset="0x80"/>
                    <Limb Name="gObjectTestRootLimb" LimbType="Standard" Offset="0xA0"/>
                    <Limb Name="gObjectTestChildLimb" LimbType="Standard" Offset="0xAC"/>
                    <Skeleton Name="gObjectTestSkel" Type="Normal" LimbType="Standard" Offset="0xC0"/>
                    <Animation Name="gObjectTestAnim" Offset="0xE0"/>
                </File>
            </Root>
            """
        )

        try harness.writeFile(
            at: "assets/objects/object_test/object_test.h",
            contents: ""
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestAnim.h",
            contents: ""
        )
        try harness.writeFile(
            at: "assets/objects/object_test/object_test.c",
            contents: """
            #include "object_test.h"

            u16 gObjectTestTex[] = {
            #include "assets/objects/object_test/gObjectTestTex.inc.c"
            };

            Vtx gObjectTestMeshVtx[] = {
            #include "assets/objects/object_test/gObjectTestMeshVtx.inc.c"
            };

            Gfx gObjectTestMeshDL[] = {
            #include "assets/objects/object_test/gObjectTestMeshDL.inc.c"
            };

            StandardLimb gObjectTestRootLimb = {
            #include "assets/objects/object_test/gObjectTestRootLimb.inc.c"
            };

            StandardLimb gObjectTestChildLimb = {
            #include "assets/objects/object_test/gObjectTestChildLimb.inc.c"
            };

            void* gObjectTestLimbs[] = {
            #include "assets/objects/object_test/gObjectTestLimbs.inc.c"
            };

            SkeletonHeader gObjectTestSkel = {
            #include "assets/objects/object_test/gObjectTestSkel.inc.c"
            };
            """
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestAnim.c",
            contents: """
            #include "gObjectTestAnim.h"

            s16 gObjectTestFrameData[] = {
            #include "assets/objects/object_test/gObjectTestFrameData.inc.c"
            };

            JointIndex gObjectTestJointIndices[] = {
            #include "assets/objects/object_test/gObjectTestJointIndices.inc.c"
            };

            AnimationHeader gObjectTestAnim = {
            #include "assets/objects/object_test/gObjectTestAnim.inc.c"
            };
            """
        )
        try harness.writeFile(at: "assets/objects/object_test/gObjectTestTex.inc.c", contents: "0xFFFF,\n")
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestMeshVtx.inc.c",
            contents: """
            VTX(0, 0, 0, 0, 0, 0, 255, 0, 0),
            VTX(10, 0, 0, 0, 32, 0, 0, 255, 0),
            VTX(0, 10, 0, 0, 0, 32, 0, 0, 255),
            """
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestMeshDL.inc.c",
            contents: """
            gsSPVertex(gObjectTestMeshVtx, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestRootLimb.inc.c",
            contents: "{ 0, 0, 0 }, 1, 255, gObjectTestMeshDL\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestChildLimb.inc.c",
            contents: "{ 10, 0, 0 }, 255, 255, NULL\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestLimbs.inc.c",
            contents: "&gObjectTestRootLimb,\n&gObjectTestChildLimb,\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestSkel.inc.c",
            contents: "gObjectTestLimbs, 2\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestFrameData.inc.c",
            contents: "0, 1, 2, 3, 4, 5\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestJointIndices.inc.c",
            contents: "{ 0, 1, 2 },\n{ 3, 4, 5 }\n"
        )
        try harness.writeFile(
            at: "assets/objects/object_test/gObjectTestAnim.inc.c",
            contents: "{ 2 }, gObjectTestFrameData, gObjectTestJointIndices, 6\n"
        )

        try TextureExtractor().extract(using: harness.extractionContext)
        try ObjectExtractor().extract(using: harness.extractionContext)

        let objectDirectory = harness.outputRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent("object_test", isDirectory: true)

        let manifest = try JSONDecoder().decode(
            ObjectManifest.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("object_manifest.json"))
        )
        XCTAssertEqual(manifest.name, "object_test")
        XCTAssertEqual(manifest.skeletonPath, "skeleton.json")
        XCTAssertEqual(manifest.animations, [
            ObjectAnimationReference(name: "gObjectTestAnim", kind: .standard, path: "animations/gObjectTestAnim.anim.json"),
        ])
        XCTAssertEqual(manifest.meshes, [
            ObjectMeshAsset(
                name: "gObjectTestMeshDL",
                displayListPath: "meshes/gObjectTestMeshDL.dl.json",
                vertexPaths: ["meshes/gObjectTestMeshVtx.vtx.bin"]
            ),
        ])
        XCTAssertEqual(manifest.textures, [
            TextureDescriptor(
                format: .rgba16,
                width: 1,
                height: 1,
                path: "textures/gObjectTestTex.tex.bin"
            ),
        ])

        let skeletonFile = try JSONDecoder().decode(
            ObjectSkeletonFile.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("skeleton.json"))
        )
        XCTAssertEqual(skeletonFile.skeletons.count, 1)
        XCTAssertEqual(skeletonFile.skeletons[0].name, "gObjectTestSkel")
        XCTAssertEqual(
            skeletonFile.skeletons[0].skeleton,
            SkeletonData(
                type: .normal,
                limbs: [
                    LimbData(
                        translation: Vector3s(x: 0, y: 0, z: 0),
                        childIndex: 1,
                        siblingIndex: nil,
                        displayListPath: "meshes/gObjectTestMeshDL.dl.json"
                    ),
                    LimbData(
                        translation: Vector3s(x: 10, y: 0, z: 0),
                        childIndex: nil,
                        siblingIndex: nil,
                        displayListPath: nil
                    ),
                ]
            )
        )

        let animation = try JSONDecoder().decode(
            ObjectAnimationData.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("animations/gObjectTestAnim.anim.json"))
        )
        XCTAssertEqual(
            animation,
            ObjectAnimationData(
                name: "gObjectTestAnim",
                kind: .standard,
                frameCount: 2,
                values: [0, 1, 2, 3, 4, 5],
                jointIndices: [
                    AnimationJointIndex(x: 0, y: 1, z: 2),
                    AnimationJointIndex(x: 3, y: 4, z: 5),
                ],
                staticIndexMax: 6
            )
        )

        let commands = try JSONDecoder().decode(
            [F3DEX2Command].self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("meshes/gObjectTestMeshDL.dl.json"))
        )
        XCTAssertEqual(commands.count, 3)
        let vertices = try VertexParser.decode(
            Data(contentsOf: objectDirectory.appendingPathComponent("meshes/gObjectTestMeshVtx.vtx.bin"))
        )
        XCTAssertEqual(vertices.count, 3)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectDirectory.appendingPathComponent("textures/gObjectTestTex.tex.bin").path
            )
        )

        try ObjectExtractor().verify(using: harness.verificationContext)
    }

    func testExtractResolvesPlayerAnimationDataFromExternalAssetDirectory() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        try harness.writeFile(
            at: "assets/xml/objects/object_player.xml",
            contents: """
            <Root>
                <ExternalFile OutPath="assets/misc/object_player_anim/"/>
                <File Name="object_player" Segment="6">
                    <PlayerAnimation Name="gObjectPlayerAnim" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeFile(
            at: "assets/objects/object_player/player_anim_headers.h",
            contents: ""
        )
        try harness.writeFile(
            at: "assets/objects/object_player/player_anim_headers.c",
            contents: """
            #include "player_anim_headers.h"

            LinkAnimationHeader gObjectPlayerAnim = {
            #include "assets/objects/object_player/gObjectPlayerAnim.inc.c"
            };
            """
        )
        try harness.writeFile(
            at: "assets/objects/object_player/gObjectPlayerAnim.inc.c",
            contents: "{ 2 }, 0, gObjectPlayerAnimData\n"
        )
        try harness.writeFile(
            at: "assets/misc/object_player_anim/object_player_anim.c",
            contents: """
            s16 gObjectPlayerAnimData[] = {
                0, 1, 2, 3, 4, 5, 6,
                7, 8, 9, 10, 11, 12, 13,
            };
            """
        )

        try ObjectExtractor().extract(using: harness.extractionContext)

        let objectDirectory = harness.outputRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent("object_player", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            ObjectManifest.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("object_manifest.json"))
        )
        XCTAssertEqual(manifest.animations, [
            ObjectAnimationReference(
                name: "gObjectPlayerAnim",
                kind: .player,
                path: "animations/gObjectPlayerAnim.anim.json"
            ),
        ])

        let animation = try JSONDecoder().decode(
            ObjectAnimationData.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("animations/gObjectPlayerAnim.anim.json"))
        )
        XCTAssertEqual(
            animation,
            ObjectAnimationData(
                name: "gObjectPlayerAnim",
                kind: .player,
                frameCount: 2,
                values: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
                limbCount: 2
            )
        )
    }

    func testExtractFindsObjectSourcesInBuildVariantAssetDirectory() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        try harness.writeFile(
            at: "assets/xml/objects/object_build.xml",
            contents: """
            <Root>
                <File Name="object_build" Segment="6">
                    <Array Name="gObjectBuildMeshVtx" Count="3" Offset="0x20">
                        <Vtx/>
                    </Array>
                    <DList Name="gObjectBuildMeshDL" Offset="0x80"/>
                    <Limb Name="gObjectBuildRootLimb" LimbType="Standard" Offset="0xA0"/>
                    <Limb Name="gObjectBuildChildLimb" LimbType="Standard" Offset="0xAC"/>
                    <Skeleton Name="gObjectBuildSkel" Type="Normal" LimbType="Standard" Offset="0xC0"/>
                    <Animation Name="gObjectBuildAnim" Offset="0xE0"/>
                </File>
            </Root>
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/object_build.c",
            contents: """
            Vtx gObjectBuildMeshVtx[] = {
            #include "assets/objects/object_build/gObjectBuildMeshVtx.inc.c"
            };

            Gfx gObjectBuildMeshDL[] = {
            #include "assets/objects/object_build/gObjectBuildMeshDL.inc.c"
            };

            StandardLimb gObjectBuildRootLimb = {
            #include "assets/objects/object_build/gObjectBuildRootLimb.inc.c"
            };

            StandardLimb gObjectBuildChildLimb = {
            #include "assets/objects/object_build/gObjectBuildChildLimb.inc.c"
            };

            void* gObjectBuildLimbs[] = {
            #include "assets/objects/object_build/gObjectBuildLimbs.inc.c"
            };

            SkeletonHeader gObjectBuildSkel = {
            #include "assets/objects/object_build/gObjectBuildSkel.inc.c"
            };
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildAnim.c",
            contents: """
            s16 gObjectBuildFrameData[] = {
            #include "assets/objects/object_build/gObjectBuildFrameData.inc.c"
            };

            JointIndex gObjectBuildJointIndices[] = {
            #include "assets/objects/object_build/gObjectBuildJointIndices.inc.c"
            };

            AnimationHeader gObjectBuildAnim = {
            #include "assets/objects/object_build/gObjectBuildAnim.inc.c"
            };
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildMeshVtx.inc.c",
            contents: """
            VTX(0, 0, 0, 0, 0, 0, 255, 0, 0),
            VTX(10, 0, 0, 0, 32, 0, 0, 255, 0),
            VTX(0, 10, 0, 0, 0, 32, 0, 0, 255),
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildMeshDL.inc.c",
            contents: """
            gsSPVertex(gObjectBuildMeshVtx, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildRootLimb.inc.c",
            contents: "{ 0, 0, 0 }, 1, 255, gObjectBuildMeshDL\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildChildLimb.inc.c",
            contents: "{ 10, 0, 0 }, 255, 255, NULL\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildLimbs.inc.c",
            contents: "&gObjectBuildRootLimb,\n&gObjectBuildChildLimb,\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildSkel.inc.c",
            contents: "gObjectBuildLimbs, 2\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildFrameData.inc.c",
            contents: "0, 1, 2, 3, 4, 5\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildJointIndices.inc.c",
            contents: "{ 0, 1, 2 },\n{ 3, 4, 5 }\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_build/gObjectBuildAnim.inc.c",
            contents: "{ 2 }, gObjectBuildFrameData, gObjectBuildJointIndices, 6\n"
        )

        try ObjectExtractor().extract(using: harness.extractionContext)

        let objectDirectory = harness.outputRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent("object_build", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            ObjectManifest.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("object_manifest.json"))
        )

        XCTAssertEqual(manifest.skeletonPath, "skeleton.json")
        XCTAssertEqual(manifest.animations.map(\.name), ["gObjectBuildAnim"])
        XCTAssertEqual(manifest.meshes.map(\.name), ["gObjectBuildMeshDL"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectDirectory.appendingPathComponent("meshes/gObjectBuildMeshVtx.vtx.bin").path
            )
        )
    }

    func testExtractSupportsRealGameplayKeepAnimationSourceShape() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        let fixtureRoot = try repoRoot()
            .appendingPathComponent("Vendor/oot", isDirectory: true)
        let gameplayKeepXML = fixtureRoot.appendingPathComponent("assets/xml/objects/gameplay_keep.xml")
        let gameplayKeepAnimation = fixtureRoot.appendingPathComponent("assets/objects/gameplay_keep/gArrow1_Anim.c")

        guard FileManager.default.fileExists(atPath: gameplayKeepXML.path) else {
            throw XCTSkip("Vendor/oot gameplay_keep.xml is not available")
        }
        guard FileManager.default.fileExists(atPath: gameplayKeepAnimation.path) else {
            throw XCTSkip("Vendor/oot gArrow1_Anim.c is not available")
        }

        try harness.copyFile(
            from: gameplayKeepXML,
            to: "assets/xml/objects/gameplay_keep.xml"
        )
        try harness.copyFile(
            from: gameplayKeepAnimation,
            to: "build/gc-eu-mq-dbg/assets/objects/gameplay_keep/gArrow1_Anim.c"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/gameplay_keep/gArrow1_FrameData.inc.c",
            contents: "0, 1, 2, 3, 4, 5\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/gameplay_keep/gArrow1_JointIndices.inc.c",
            contents: "{ 0, 1, 2 },\n{ 3, 4, 5 }\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/gameplay_keep/gArrow1_Anim.inc.c",
            contents: "{ 2 }, gArrow1_FrameData, gArrow1_JointIndices, 6\n"
        )

        try ObjectExtractor().extract(using: harness.extractionContext)

        let objectDirectory = harness.outputRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent("gameplay_keep", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            ObjectManifest.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("object_manifest.json"))
        )
        XCTAssertEqual(manifest.animations, [
            ObjectAnimationReference(
                name: "gArrow1_Anim",
                kind: .standard,
                path: "animations/gArrow1_Anim.anim.json"
            ),
        ])

        let animation = try JSONDecoder().decode(
            ObjectAnimationData.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("animations/gArrow1_Anim.anim.json"))
        )
        XCTAssertEqual(animation.frameCount, 2)
        XCTAssertEqual(animation.values, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(
            animation.jointIndices,
            [
                AnimationJointIndex(x: 0, y: 1, z: 2),
                AnimationJointIndex(x: 3, y: 4, z: 5),
            ]
        )
    }

    func testExtractSupportsRealObjectLinkBoySkeletonAndMeshSourceShape() throws {
        let harness = try ObjectHarness()
        defer { harness.cleanup() }

        let fixtureRoot = try repoRoot()
            .appendingPathComponent("Vendor/oot", isDirectory: true)
        let objectXML = fixtureRoot.appendingPathComponent("assets/xml/objects/object_link_boy.xml")
        let objectSource = fixtureRoot.appendingPathComponent("assets/objects/object_link_boy/object_link_boy.c")

        guard FileManager.default.fileExists(atPath: objectXML.path) else {
            throw XCTSkip("Vendor/oot object_link_boy.xml is not available")
        }
        guard FileManager.default.fileExists(atPath: objectSource.path) else {
            throw XCTSkip("Vendor/oot object_link_boy.c is not available")
        }

        try harness.copyFile(
            from: objectXML,
            to: "assets/xml/objects/object_link_boy.xml"
        )
        try harness.copyFile(
            from: objectSource,
            to: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/object_link_boy.c"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultWaistNearVtx.inc.c",
            contents: """
            VTX(0, 0, 0, 0, 0, 0, 255, 0, 0),
            VTX(10, 0, 0, 0, 32, 0, 0, 255, 0),
            VTX(0, 10, 0, 0, 0, 32, 0, 0, 255),
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultWaistNearDL.inc.c",
            contents: """
            gsSPVertex(gLinkAdultWaistNearVtx, 3, 0),
            gsSP1Triangle(0, 1, 2, 0),
            gsSPEndDisplayList(),
            """
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultRootLimb.inc.c",
            contents: "{ 0, 0, 0 }, 1, 255, { NULL, NULL }\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultWaistLimb.inc.c",
            contents: "{ 0, 12, 0 }, 255, 255, { gLinkAdultWaistNearDL, NULL }\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultLimbs.inc.c",
            contents: "&gLinkAdultRootLimb,\n&gLinkAdultWaistLimb,\n"
        )
        try harness.writeFile(
            at: "build/gc-eu-mq-dbg/assets/objects/object_link_boy/gLinkAdultSkel.inc.c",
            contents: "{ gLinkAdultLimbs, 2 }, 2\n"
        )

        try ObjectExtractor().extract(using: harness.extractionContext)

        let objectDirectory = harness.outputRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent("object_link_boy", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            ObjectManifest.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("object_manifest.json"))
        )
        XCTAssertEqual(manifest.skeletonPath, "skeleton.json")
        XCTAssertTrue(
            manifest.meshes.contains {
                $0.name == "gLinkAdultWaistNearDL" &&
                    $0.displayListPath == "meshes/gLinkAdultWaistNearDL.dl.json"
            }
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: objectDirectory.appendingPathComponent("meshes/gLinkAdultWaistNearDL.dl.json").path
            )
        )

        let skeletonFile = try JSONDecoder().decode(
            ObjectSkeletonFile.self,
            from: Data(contentsOf: objectDirectory.appendingPathComponent("skeleton.json"))
        )
        XCTAssertEqual(skeletonFile.skeletons.count, 1)
        XCTAssertEqual(skeletonFile.skeletons[0].name, "gLinkAdultSkel")
        XCTAssertEqual(
            skeletonFile.skeletons[0].skeleton,
            SkeletonData(
                type: .flex,
                limbs: [
                    LimbData(
                        translation: Vector3s(x: 0, y: 0, z: 0),
                        childIndex: 1,
                        siblingIndex: nil,
                        displayListPath: nil,
                        lowDetailDisplayListPath: nil
                    ),
                    LimbData(
                        translation: Vector3s(x: 0, y: 12, z: 0),
                        childIndex: nil,
                        siblingIndex: nil,
                        displayListPath: "meshes/gLinkAdultWaistNearDL.dl.json",
                        lowDetailDisplayListPath: nil
                    ),
                ]
            )
        )
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ObjectHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "ObjectExtractorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        self.root = root
        self.sourceRoot = sourceRoot
        self.outputRoot = outputRoot
    }

    var extractionContext: OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot)
    }

    func extractionContext(sceneNames: [String]) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneNames: sceneNames)
    }

    var verificationContext: OOTVerificationContext {
        OOTVerificationContext(content: outputRoot)
    }

    func writeFile(at relativePath: String, contents: String) throws {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func copyFile(from sourceURL: URL, to relativePath: String) throws {
        try writeFile(at: relativePath, contents: String(contentsOf: sourceURL, encoding: .utf8))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
