import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class TextureExtractorTests: XCTestCase {
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

    func writeXML(at relativePath: String, contents: String) throws {
        try writeFile(at: relativePath, contents: contents)
    }

    func writeSource(at relativePath: String, contents: String) throws {
        try writeFile(at: relativePath, contents: contents)
    }

    func writePNG(at relativePath: String) throws {
        let data = try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxkAAAAAASUVORK5CYII=")
        )
        try writeData(at: relativePath, data: data)
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
