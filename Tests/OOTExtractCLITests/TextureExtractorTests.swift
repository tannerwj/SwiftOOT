import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class TextureExtractorTests: XCTestCase {
    func testSceneScopedExtractionIncludesRequiredObjectTexturesForSelectedSceneSet() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        func writeObjectTexture(named name: String, textureName: String, texel: String) throws {
            try harness.writeXML(
                at: "assets/xml/objects/\(name).xml",
                contents: """
                <Root>
                    <File Name="\(name)" Segment="6">
                        <Texture Name="\(textureName)" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    </File>
                </Root>
                """
            )
            try harness.writeSource(
                at: "assets/objects/\(name)/\(name).c",
                contents: """
                u16 \(textureName)[] = { \(texel) };
                """
            )
        }

        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot00.xml",
            contents: """
            <Root>
                <File Name="spot00_scene" Segment="2">
                    <Texture Name="gSpot00Tex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Scene Name="spot00_scene" Offset="0x0"/>
                </File>
                <File Name="spot00_room_0" Segment="3">
                    <Room Name="spot00_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot01.xml",
            contents: """
            <Root>
                <File Name="spot01_scene" Segment="2">
                    <Texture Name="gSpot01Tex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Scene Name="spot01_scene" Offset="0x0"/>
                </File>
                <File Name="spot01_room_0" Segment="3">
                    <Room Name="spot01_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/scenes/overworld/spot00/spot00_scene.inc.c",
            contents: "u16 gSpot00Tex[] = { 0xFFFF };"
        )
        try harness.writeSource(
            at: "assets/scenes/overworld/spot01/spot01_scene.inc.c",
            contents: "u16 gSpot01Tex[] = { 0x1111 };"
        )

        try writeObjectTexture(named: "object_link_boy", textureName: "gLinkBoyTex", texel: "0xAAAA")
        try writeObjectTexture(named: "object_required", textureName: "gRequiredTex", texel: "0xBBBB")
        try writeObjectTexture(named: "object_unused", textureName: "gUnusedTex", texel: "0xCCCC")

        let encoder = JSONEncoder()
        let fileManager = FileManager.default
        let tablesDirectory = harness.outputRoot
            .appendingPathComponent("Manifests/tables", isDirectory: true)
        try fileManager.createDirectory(at: tablesDirectory, withIntermediateDirectories: true)
        try encoder.encode([
            ObjectTableEntry(id: 201, enumName: "OBJECT_REQUIRED", assetPath: "Objects/object_required"),
            ObjectTableEntry(id: 202, enumName: "OBJECT_UNUSED", assetPath: "Objects/object_unused"),
        ]).write(to: tablesDirectory.appendingPathComponent("object-table.json"))
        try encoder.encode([
            ActorTableEntry(
                id: 21,
                enumName: "ACTOR_REQUIRED",
                profile: ActorProfile(id: 21, category: 4, flags: 0, objectID: 201)
            ),
            ActorTableEntry(
                id: 22,
                enumName: "ACTOR_UNUSED",
                profile: ActorProfile(id: 22, category: 4, flags: 0, objectID: 202)
            ),
        ]).write(to: tablesDirectory.appendingPathComponent("actor-table.json"))

        let spot00Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot00", isDirectory: true)
        let spot01Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot01", isDirectory: true)
        let spot02Directory = harness.outputRoot
            .appendingPathComponent("Manifests/scenes/overworld/spot02", isDirectory: true)
        try fileManager.createDirectory(at: spot00Directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: spot01Directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: spot02Directory, withIntermediateDirectories: true)

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
                                actorID: 21,
                                actorName: "ACTOR_REQUIRED",
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
                rooms: [SceneRoomDefinition(id: 0, shape: .normal)]
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
                                actorID: 22,
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

        try TextureExtractor().extract(using: harness.extractionContext(sceneNames: ["spot00", "spot01"]))

        XCTAssertTrue(
            fileManager.fileExists(
                atPath: harness.outputRoot.appendingPathComponent("Textures/spot00_scene/gSpot00Tex.tex.bin").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: harness.outputRoot.appendingPathComponent("Textures/spot01_scene/gSpot01Tex.tex.bin").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: harness.outputRoot.appendingPathComponent("Textures/object_link_boy/gLinkBoyTex.tex.bin").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: harness.outputRoot.appendingPathComponent("Textures/object_required/gRequiredTex.tex.bin").path
            )
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: harness.outputRoot.appendingPathComponent("Textures/object_unused/gUnusedTex.tex.bin").path
            )
        )
    }

    func testExtractWritesDecodedRGBA16TextureAndMetadataFromObjectXML() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_test.xml",
            contents: """
            <Root>
                <File Name="object_test" Segment="6">
                    <Texture Name="gObjectTestTex" Format="rgba16" Width="2" Height="1" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_test/object_test.inc.c",
            contents: """
            u16 gObjectTestTex[] = {
                0xF801, 0x07C0,
            };
            """
        )

        let extractor = TextureExtractor()
        try extractor.extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("object_test", isDirectory: true)
        let binary = try Data(contentsOf: textureDirectory.appendingPathComponent("gObjectTestTex.tex.bin"))
        let metadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: textureDirectory.appendingPathComponent("gObjectTestTex.tex.json"))
        )

        XCTAssertEqual(
            [UInt8](binary),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0x00,
            ]
        )
        XCTAssertEqual(
            metadata,
            TextureAssetMetadata(format: .rgba16, width: 2, height: 1, hasTLUT: false)
        )

        try extractor.verify(using: harness.verificationContext)
    }

    func testExtractWritesCITexelsAndDecodedTLUTFromSceneXML() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_scene" Segment="2">
                    <TLUT Name="gSpot04TLUT" Format="rgba16" Offset="0x20"/>
                    <Texture Name="gSpot04MainTex" Format="ci4" Width="3" Height="1" Offset="0x0" TlutOffset="0x20"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/scenes/overworld/spot04/spot04_scene.inc.c",
            contents: """
            u8 gSpot04MainTex[] = {
                0x12, 0x30,
            };

            u16 gSpot04TLUT[] = {
                0xF801, 0x07C1, 0x003F, 0xFFFF,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
            };
            """
        )

        let extractor = TextureExtractor()
        try extractor.extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("spot04_scene", isDirectory: true)
        let binary = try Data(contentsOf: textureDirectory.appendingPathComponent("gSpot04MainTex.tex.bin"))
        let metadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: textureDirectory.appendingPathComponent("gSpot04MainTex.tex.json"))
        )

        XCTAssertEqual(Array(binary.prefix(3)), [0x01, 0x02, 0x03])
        XCTAssertEqual(
            Array(binary.dropFirst(3).prefix(16)),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF,
            ]
        )
        XCTAssertEqual(
            metadata,
            TextureAssetMetadata(format: .ci4, width: 3, height: 1, hasTLUT: true)
        )
        XCTAssertEqual(binary.count, 3 + (16 * 4))

        try extractor.verify(using: harness.verificationContext)
    }

    func testExtractHonorsSceneFilterForSceneXMLs() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_scene" Segment="2">
                    <Texture Name="gSpot04MainTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot05.xml",
            contents: """
            <Root>
                <File Name="spot05_scene" Segment="2">
                    <Texture Name="gSpot05MainTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/scenes/overworld/spot04/spot04_scene.inc.c",
            contents: """
            u16 gSpot04MainTex[] = { 0xFFFF };
            """
        )
        try harness.writeSource(
            at: "assets/scenes/overworld/spot05/spot05_scene.inc.c",
            contents: """
            u16 gSpot05MainTex[] = { 0x0001 };
            """
        )

        try TextureExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Textures/spot04_scene/gSpot04MainTex.tex.bin")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Textures/spot05_scene/gSpot05MainTex.tex.bin")
                    .path
            )
        )
    }

    func testExtractIncludesSkyboxTextureCatalogsDuringSceneScopedRuns() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/textures/skyboxes.xml",
            contents: """
            <Root>
                <File Name="vr_cloud1_static">
                    <Texture Name="gDayOvercastSkybox1Tex" Format="ci8" Width="1" Height="1" Offset="0x0"/>
                </File>
                <File Name="vr_cloud1_pal_static">
                    <Texture Name="gDayOvercastSkyboxTLUT" Format="rgba16" Width="16" Height="8" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/textures/skyboxes/vr_cloud1_static.c",
            contents: """
            #include "vr_cloud1_static.h"

            u64 gDayOvercastSkybox1Tex[TEX_LEN(u64, gDayOvercastSkybox1Tex_WIDTH, gDayOvercastSkybox1Tex_HEIGHT, 8)] = {
            #include "assets/textures/skyboxes/gDayOvercastSkybox1Tex.ci8.split_hi.tlut_gDayOvercastSkyboxTLUT.inc.c"
            };
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/textures/skyboxes/vr_cloud1_static.h",
            contents: """
            #include "tex_len.h"
            #define gDayOvercastSkybox1Tex_WIDTH 1
            #define gDayOvercastSkybox1Tex_HEIGHT 1
            extern u64 gDayOvercastSkybox1Tex[TEX_LEN(u64, gDayOvercastSkybox1Tex_WIDTH, gDayOvercastSkybox1Tex_HEIGHT, 8)];
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/textures/skyboxes/gDayOvercastSkybox1Tex.ci8.split_hi.tlut_gDayOvercastSkyboxTLUT.png"
        )

        try TextureExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Textures/vr_cloud1_static/gDayOvercastSkybox1Tex.tex.bin")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Textures/vr_cloud1_pal_static/gDayOvercastSkyboxTLUT.tex.bin")
                    .path
            )
        )
    }

    func testExtractSkipsStandaloneTLUTWhenPNGBackedCITextureProvidesFallback() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_bombwall.xml",
            contents: """
            <Root>
                <File Name="object_bombwall" Segment="6">
                    <Texture Name="gBombwallTLUT" Format="rgba16" Width="4" Height="4" Offset="0x0"/>
                    <Texture Name="gBombwallTex" Format="ci4" Width="1" Height="1" Offset="0x20" TlutOffset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/objects/object_bombwall/object_bombwall.h",
            contents: """
            #define gBombwallTex_WIDTH 1
            #define gBombwallTex_HEIGHT 1
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/objects/object_bombwall/object_bombwall.c",
            contents: """
            #include "object_bombwall.h"

            u64 gBombwallTLUT[] = {
            #include "assets/objects/object_bombwall/gBombwallTLUT.tlut.rgba16.inc.c"
            };

            u64 gBombwallTex[] = {
            #include "assets/objects/object_bombwall/gBombwallTex.ci4.tlut_gBombwallTLUT.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_bombwall/gBombwallTex.ci4.tlut_gBombwallTLUT.png"
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_bombwall", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gBombwallTex.tex.bin").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gBombwallTLUT.tex.bin").path
            )
        )
    }

    func testExtractSkipsOrphanedTLUTMarkedWithHackMode() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_owl.xml",
            contents: """
            <Root>
                <File Name="object_owl" Segment="6">
                    <TLUT Name="object_owl_TLUT_006DA8" Format="rgba16" Offset="0x0"/>
                    <Texture Name="object_owl_TLUT_006FA8" Format="rgba16" Width="4" Height="4" Offset="0x20" HackMode="ignore_orphaned_tlut"/>
                    <Texture Name="gObjOwlEyeOpenTex" Format="ci4" Width="1" Height="1" Offset="0x40" TlutOffset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_owl/object_owl.inc.c",
            contents: """
            u16 object_owl_TLUT_006DA8[] = {
                0xFFFF, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
            };

            u8 gObjOwlEyeOpenTex[] = { 0x00 };
            """
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_owl", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gObjOwlEyeOpenTex.tex.bin").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("object_owl_TLUT_006FA8.tex.bin").path
            )
        )
    }

    func testExtractSupportsWordSizedSourceBackedPNGTextureFallbacks() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_ahg.xml",
            contents: """
            <Root>
                <File Name="object_ahg" Segment="6">
                    <Texture Name="gHylianMan1TLUT" Format="rgba16" Width="16" Height="16" Offset="0x0"/>
                    <Texture Name="gHylianMan1BeardedSkinHairTex" Format="ci8" Width="16" Height="16" Offset="0x200" TlutOffset="0x0"/>
                    <Texture Name="gHylianMan1ShirtTex" Format="i8" Width="8" Height="8" Offset="0x300"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/objects/object_ahg/object_ahg.h",
            contents: """
            #define gHylianMan1BeardedSkinHairTex_WIDTH 16
            #define gHylianMan1BeardedSkinHairTex_HEIGHT 16
            #define gHylianMan1ShirtTex_WIDTH 8
            #define gHylianMan1ShirtTex_HEIGHT 8
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/objects/object_ahg/object_ahg.c",
            contents: """
            #include "object_ahg.h"

            u32 gHylianMan1TLUT[] = {
            #include "assets/objects/object_ahg/gHylianMan1TLUT.tlut.rgba16.u32.inc.c"
            };

            u32 gHylianMan1BeardedSkinHairTex[] = {
            #include "assets/objects/object_ahg/gHylianMan1BeardedSkinHairTex.ci8.tlut_gHylianMan1TLUT_u32.u32.inc.c"
            };

            u32 gHylianMan1ShirtTex[] = {
            #include "assets/objects/object_ahg/gHylianMan1ShirtTex.i8.u32.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_ahg/gHylianMan1BeardedSkinHairTex.ci8.tlut_gHylianMan1TLUT_u32.u32.png",
            width: 16,
            height: 16
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_ahg/gHylianMan1ShirtTex.i8.u32.png",
            width: 8,
            height: 8
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_ahg", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gHylianMan1BeardedSkinHairTex.tex.bin").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gHylianMan1ShirtTex.tex.bin").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gHylianMan1TLUT.tex.bin").path
            )
        )
    }

    func testExtractFallsBackToRealSceneSourceShapeWhenXMLOmitsTextureDeclarations() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/scenes/overworld/spot04.xml",
            contents: """
            <Root>
                <File Name="spot04_scene" Segment="2">
                    <Scene Name="spot04_scene" Offset="0x0"/>
                </File>
                <File Name="spot04_room_0" Segment="3">
                    <Room Name="spot04_room_0" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_scene.h",
            contents: """
            extern u64 spot04_scene_0000E010_TLUT[];
            #define spot04_scene_0000FA18_CITex_WIDTH 16
            #define spot04_scene_0000FA18_CITex_HEIGHT 1
            extern u64 spot04_scene_0000FA18_CITex[];
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_scene.c",
            contents: """
            #include "spot04_scene.h"

            u64 spot04_scene_0000E010_TLUT[] = {
            #include "assets/scenes/overworld/spot04/spot04_scene_0000E010_TLUT.tlut.rgba16.inc.c"
            };

            u64 spot04_scene_0000FA18_CITex[] = {
            #include "assets/scenes/overworld/spot04/spot04_scene_0000FA18_CITex.ci4.tlut_spot04_scene_0000E010_TLUT.inc.c"
            };
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_scene_0000E010_TLUT.tlut.rgba16.inc.c",
            contents: """
            0x7C1F07C1003FFFFF,
            0x0001000100010001,
            0x0001000100010001,
            0x0001000100010001,
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_scene_0000FA18_CITex.ci4.tlut_spot04_scene_0000E010_TLUT.inc.c",
            contents: """
            0x0102000000000000,
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_room_0.h",
            contents: """
            #define spot04_room_0_0000BF08_Tex_WIDTH 2
            #define spot04_room_0_0000BF08_Tex_HEIGHT 2
            extern u64 spot04_room_0_0000BF08_Tex[];
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_room_0.c",
            contents: """
            #include "spot04_room_0.h"

            u64 spot04_room_0_0000BF08_Tex[] = {
            #include "assets/scenes/overworld/spot04/spot04_room_0_0000BF08_Tex.rgba16.inc.c"
            };
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/overworld/spot04/spot04_room_0_0000BF08_Tex.rgba16.inc.c",
            contents: """
            0x07C1000000000000,
            """
        )

        try TextureExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let sceneDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("spot04_scene", isDirectory: true)
        let roomDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("spot04_room_0", isDirectory: true)

        let sceneMetadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: sceneDirectory.appendingPathComponent("spot04_scene_0000FA18_CITex.tex.json"))
        )
        let roomMetadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: roomDirectory.appendingPathComponent("spot04_room_0_0000BF08_Tex.tex.json"))
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sceneDirectory.appendingPathComponent("spot04_scene_0000FA18_CITex.tex.bin").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: roomDirectory.appendingPathComponent("spot04_room_0_0000BF08_Tex.tex.bin").path
            )
        )
        XCTAssertEqual(
            sceneMetadata,
            TextureAssetMetadata(format: .ci4, width: 16, height: 1, hasTLUT: true)
        )
        XCTAssertEqual(
            roomMetadata,
            TextureAssetMetadata(format: .rgba16, width: 2, height: 2, hasTLUT: false)
        )

        try TextureExtractor().verify(using: harness.verificationContext)
    }

    func testExtractFallsBackToOwningSceneSourceWhenWrapperIsMissing() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/scenes/dungeons/Bmori1.xml",
            contents: """
            <Root>
                <File Name="Bmori1_scene" Segment="2">
                    <Texture Name="gForestTempleDayEntranceTex" Format="ia16" Width="1" Height="1" Offset="0x0"/>
                    <Texture Name="gForestTempleNightEntranceTex" Format="ia16" Width="1" Height="1" Offset="0x2"/>
                    <Scene Name="Bmori1_scene" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "build/assets/scenes/dungeons/Bmori1/Bmori1_scene.h",
            contents: """
            u16 gForestTempleDayEntranceTex[] = {
                0x00FF,
            };

            u16 gForestTempleNightEntranceTex[] = {
                0xFF00,
            };
            """
        )
        try harness.writeSource(
            at: "src/code/z_scene_table.c",
            contents: """
            #include "assets/scenes/dungeons/Bmori1/Bmori1_scene.h"

            void* sForestTempleEntranceTextures[] = {
                gForestTempleDayEntranceTex,
                gForestTempleNightEntranceTex,
            };
            """
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("Bmori1_scene", isDirectory: true)
        let metadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: textureDirectory.appendingPathComponent("gForestTempleDayEntranceTex.tex.json"))
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory
                    .appendingPathComponent("gForestTempleNightEntranceTex.tex.bin")
                    .path
            )
        )
        XCTAssertEqual(
            metadata,
            TextureAssetMetadata(format: .ia16, width: 1, height: 1, hasTLUT: false)
        )
    }

    func testExtractUsesPNGWhenSceneTextureIncludeIsMissingFromCanonicalShape() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/scenes/dungeons/ydan.xml",
            contents: """
            <Root>
                <File Name="ydan_scene" Segment="2">
                    <Texture Name="gDekuTreeDayEntranceTex" Format="rgba16" Width="1" Height="1" Offset="0xBA08"/>
                    <Scene Name="ydan_scene" Offset="0x0"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/dungeons/ydan/ydan_scene.h",
            contents: """
            #include "tex_len.h"

            #define gDekuTreeDayEntranceTex_WIDTH 1
            #define gDekuTreeDayEntranceTex_HEIGHT 1
            extern u64 gDekuTreeDayEntranceTex[TEX_LEN(u64, gDekuTreeDayEntranceTex_WIDTH, gDekuTreeDayEntranceTex_HEIGHT, 16)];
            """
        )
        try harness.writeSource(
            at: "extracted/ntsc-1.2/assets/scenes/dungeons/ydan/ydan_scene.c",
            contents: """
            #include "ydan_scene.h"

            u64 gDekuTreeDayEntranceTex[TEX_LEN(u64, gDekuTreeDayEntranceTex_WIDTH, gDekuTreeDayEntranceTex_HEIGHT, 16)] = {
            #include "assets/scenes/dungeons/ydan/gDekuTreeDayEntranceTex.rgba16.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/scenes/dungeons/ydan/gDekuTreeDayEntranceTex.rgba16.png"
        )

        let extractor = TextureExtractor()
        try extractor.extract(using: harness.extractionContext(sceneName: "ydan"))

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("ydan_scene", isDirectory: true)
        let binary = try Data(contentsOf: textureDirectory.appendingPathComponent("gDekuTreeDayEntranceTex.tex.bin"))
        let metadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: textureDirectory.appendingPathComponent("gDekuTreeDayEntranceTex.tex.json"))
        )

        XCTAssertEqual(binary.count, 4)
        XCTAssertEqual(
            metadata,
            TextureAssetMetadata(format: .rgba32, width: 1, height: 1, hasTLUT: false)
        )

        try extractor.verify(using: harness.verificationContext)
    }

    func testExtractUsesExtractedPNGWhenObjectSourceLivesInAssetsDirectory() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_link_boy.xml",
            contents: """
            <Root>
                <File Name="object_link_boy" Segment="6">
                    <Texture Name="gLinkAdultEyesOpenTex" Format="ci8" Width="1" Height="1" Offset="0x0" TlutOffset="0x20"/>
                    <Texture Name="gLinkAdultHeadTLUT" Format="rgba16" Width="16" Height="1" Offset="0x20"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_link_boy/object_link_boy.h",
            contents: """
            #include "tex_len.h"

            #define LINK_ADULT_EYES_TEX_WIDTH 1
            #define LINK_ADULT_EYES_TEX_HEIGHT 1
            extern u64 gLinkAdultEyesOpenTex[TEX_LEN(u64, LINK_ADULT_EYES_TEX_WIDTH, LINK_ADULT_EYES_TEX_HEIGHT, 8)];
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_link_boy/object_link_boy.c",
            contents: """
            #include "object_link_boy.h"

            u64 gLinkAdultEyesOpenTex[TEX_LEN(u64, LINK_ADULT_EYES_TEX_WIDTH, LINK_ADULT_EYES_TEX_HEIGHT, 8)] = {
            #include "assets/objects/object_link_boy/gLinkAdultEyesOpenTex.ci8.tlut_gLinkAdultHeadTLUT.inc.c"
            };

            u64 gLinkAdultHeadTLUT[] = {
            #include "assets/objects/object_link_boy/gLinkAdultHeadTLUT.tlut.rgba16.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_link_boy/gLinkAdultEyesOpenTex.ci8.tlut_gLinkAdultHeadTLUT.png"
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_link_boy", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gLinkAdultEyesOpenTex.tex.bin").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gLinkAdultHeadTLUT.tex.bin").path
            )
        )
    }

    func testExtractUsesPNGFallbackFromAlternateObjectSourceFile() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_umajump.xml",
            contents: """
            <Root>
                <File Name="object_umajump" Segment="6">
                    <Texture Name="gJumpableHorseFenceBrickTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Texture Name="gJumpableHorseFenceMetalBarTex" Format="rgba16" Width="1" Height="1" Offset="0x2"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_umajump/object_umajump.h",
            contents: """
            #include "tex_len.h"

            #define gJumpableHorseFenceBrickTex_WIDTH 1
            #define gJumpableHorseFenceBrickTex_HEIGHT 1
            extern u64 gJumpableHorseFenceBrickTex[TEX_LEN(u64, gJumpableHorseFenceBrickTex_WIDTH, gJumpableHorseFenceBrickTex_HEIGHT, 16)];

            #define gJumpableHorseFenceMetalBarTex_WIDTH 1
            #define gJumpableHorseFenceMetalBarTex_HEIGHT 1
            extern u64 gJumpableHorseFenceMetalBarTex[TEX_LEN(u64, gJumpableHorseFenceMetalBarTex_WIDTH, gJumpableHorseFenceMetalBarTex_HEIGHT, 16)];
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_umajump/gJumpableHorseFenceDL.c",
            contents: """
            #include "object_umajump.h"

            #define gJumpableHorseFenceBrickTex_WIDTH 1
            #define gJumpableHorseFenceBrickTex_HEIGHT 1

            u64 gJumpableHorseFenceBrickTex[TEX_LEN(u64, gJumpableHorseFenceBrickTex_WIDTH, gJumpableHorseFenceBrickTex_HEIGHT, 16)] = {
            #include "assets/objects/object_umajump/gJumpableHorseFenceBrickTex.rgba16.inc.c"
            };

            #define gJumpableHorseFenceMetalBarTex_WIDTH 1
            #define gJumpableHorseFenceMetalBarTex_HEIGHT 1

            u64 gJumpableHorseFenceMetalBarTex[TEX_LEN(u64, gJumpableHorseFenceMetalBarTex_WIDTH, gJumpableHorseFenceMetalBarTex_HEIGHT, 16)] = {
            #include "assets/objects/object_umajump/gJumpableHorseFenceMetalBarTex.rgba16.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_umajump/gJumpableHorseFenceBrickTex.rgba16.png"
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_umajump/gJumpableHorseFenceMetalBarTex.rgba16.png"
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Textures/object_umajump/gJumpableHorseFenceBrickTex.tex.bin")
                    .path
            )
        )
    }

    func testExtractAggregatesPNGFallbacksAcrossSplitObjectSourceFiles() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_zo.xml",
            contents: """
            <Root>
                <File Name="object_zo" Segment="6">
                    <Texture Name="gZoraEyeOpenTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Texture Name="gZoraBubblesTex" Format="ia8" Width="1" Height="1" Offset="0x2"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_zo/gZoraSkel.c",
            contents: """
            u64 gZoraEyeOpenTex[] = {
            #include "assets/objects/object_zo/gZoraEyeOpenTex.rgba16.inc.c"
            };
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_zo/effect_bubbles.c",
            contents: """
            u64 gZoraBubblesTex[] = {
            #include "assets/objects/object_zo/gZoraBubblesTex.ia8.inc.c"
            };
            """
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_zo/gZoraEyeOpenTex.rgba16.png"
        )
        try harness.writePNG(
            at: "extracted/ntsc-1.2/assets/objects/object_zo/gZoraBubblesTex.ia8.png"
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_zo", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gZoraEyeOpenTex.tex.bin").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gZoraBubblesTex.tex.bin").path
            )
        )
    }

    func testExtractParsesArrayBackedTexturesAcrossSplitObjectSourceFiles() throws {
        let harness = try TextureHarness()
        defer { harness.cleanup() }

        try harness.writeXML(
            at: "assets/xml/objects/object_zo.xml",
            contents: """
                <Root>
                    <File Name="object_zo" Segment="6">
                    <Texture Name="gZoraTLUT" Format="rgba16" Width="8" Height="8" Offset="0x20"/>
                    <Texture Name="gZoraEyeOpenTex" Format="rgba16" Width="1" Height="1" Offset="0x0"/>
                    <Texture Name="gZoraBubblesTex" Format="ia8" Width="1" Height="1" Offset="0x2"/>
                    <Texture Name="gZoraHeadTex" Format="ci8" Width="1" Height="1" Offset="0x4" TlutOffset="0x20"/>
                </File>
            </Root>
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_zo/gZoraSkel.c",
            contents: """
            u16 gZoraEyeOpenTex[] = { 0xF801 };
            u16 gZoraTLUT[] = {
                0xF801, 0x07C1, 0x003F, 0xFFFF,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001,
                0x0001, 0x0001, 0x0001, 0x0001
            };
            u8 gZoraHeadTex[] = { 0x01 };
            """
        )
        try harness.writeSource(
            at: "assets/objects/object_zo/effect_bubbles.c",
            contents: """
            u8 gZoraBubblesTex[] = { 0xFF };
            """
        )

        try TextureExtractor().extract(using: harness.extractionContext)

        let textureDirectory = harness.outputRoot
            .appendingPathComponent("Textures/object_zo", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gZoraEyeOpenTex.tex.bin").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gZoraBubblesTex.tex.bin").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: textureDirectory.appendingPathComponent("gZoraHeadTex.tex.bin").path
            )
        )
    }
}

private struct TextureHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "TextureExtractorTests-\(UUID().uuidString)",
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

    var verificationContext: OOTVerificationContext {
        OOTVerificationContext(content: outputRoot)
    }

    func extractionContext(sceneName: String) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneName: sceneName)
    }

    func extractionContext(sceneNames: [String]) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneNames: sceneNames)
    }

    func writeXML(at relativePath: String, contents: String) throws {
        try writeFile(at: relativePath, contents: contents)
    }

    func writeSource(at relativePath: String, contents: String) throws {
        try writeFile(at: relativePath, contents: contents)
    }

    func writePNG(at relativePath: String, width: Int = 1, height: Int = 1) throws {
        var buffer = Data(repeating: 0xFF, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pngData = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil)
        )

        let image = try buffer.withUnsafeMutableBytes { rawBuffer -> CGImage in
            let context = try XCTUnwrap(
                CGContext(
                    data: rawBuffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            return try XCTUnwrap(context.makeImage())
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try writeData(at: relativePath, data: pngData as Data)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeFile(at relativePath: String, contents: String) throws {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeData(at relativePath: String, data: Data) throws {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }
}
