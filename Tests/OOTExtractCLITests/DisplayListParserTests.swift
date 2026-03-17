import XCTest
@testable import OOTExtractSupport
@testable import OOTDataModel

final class DisplayListParserTests: XCTestCase {
    func testParserBuildsCommandsForRequiredMacroSet() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("scene.c")
        try fixtureSource().write(to: sourceFile, atomically: true, encoding: .utf8)

        let parser = DisplayListParser()
        let displayLists = try parser.parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(displayLists.count, 1)
        XCTAssertEqual(displayLists[0].name, "sceneMainDL")
        XCTAssertEqual(displayLists[0].commands, expectedCommands())
    }

    func testExtractorWritesJsonForIncludeBackedDisplayListArray() throws {
        let fixtureRoot = try makeFixtureRoot()
        let assetsDirectory = fixtureRoot.appendingPathComponent("assets", isDirectory: true)
        let objectDirectory = assetsDirectory.appendingPathComponent("objects", isDirectory: true)
        try FileManager.default.createDirectory(at: objectDirectory, withIntermediateDirectories: true)

        let includeSource = """
        gsSPVertex(sceneName_Vtx_0000, 4, 0),
        gsSP1Triangle(0, 1, 2, 0),
        gsSPEndDisplayList(),
        """
        try includeSource.write(
            to: objectDirectory.appendingPathComponent("gSimpleDL.inc.c"),
            atomically: true,
            encoding: .utf8
        )

        let source = """
        #include "gfx.h"

        Gfx gSimpleDL[] = {
        #include "assets/objects/gSimpleDL.inc.c"
        };
        """
        let sourceFile = fixtureRoot.appendingPathComponent("object.c")
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)

        let outputRoot = fixtureRoot.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        try DisplayListParser().extract(using: OOTExtractionContext(source: fixtureRoot, output: outputRoot))

        let outputFile = try XCTUnwrap(
            FileManager.default.enumerator(
                at: outputRoot.appendingPathComponent("DisplayLists", isDirectory: true),
                includingPropertiesForKeys: nil
            )?
            .compactMap { $0 as? URL }
            .first(where: { $0.lastPathComponent == "gSimpleDL.json" })
        )
        let data = try Data(contentsOf: outputFile)
        let decoded = try JSONDecoder().decode([F3DEX2Command].self, from: data)

        XCTAssertEqual(
            decoded,
            [
                .spVertex(
                    VertexCommand(
                        address: DisplayListParser.stableID(for: "sceneName_Vtx_0000"),
                        count: 4,
                        destinationIndex: 0
                    )
                ),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
                .spEndDisplayList,
            ]
        )
    }

    func testParserSupportsIndexedVertexAddresses() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("indexed-scene.c")
        try """
        #include "gfx.h"

        static Gfx indexedDL[] = {
            gsSPVertex(&sceneName_Vtx_0000[2], 4, 0),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "indexedDL",
                    commands: [
                        .spVertex(
                            VertexCommand(
                                address: DisplayListParser.stableID(for: "sceneName_Vtx_0000[2]"),
                                count: 4,
                                destinationIndex: 0
                            )
                        ),
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testParserExpandsLoadTextureBlockMacro() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("texture-block.c")
        try """
        #include "gfx.h"

        static Gfx textureBlockDL[] = {
            gsDPLoadTextureBlock(sceneMainTex, G_IM_FMT_RGBA, G_IM_SIZ_16b, 32, 32, 0, G_TX_NOMIRROR | G_TX_WRAP, G_TX_NOMIRROR | G_TX_WRAP, 5, 5, G_TX_NOLOD, G_TX_NOLOD),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "textureBlockDL",
                    commands: [
                        .dpSetTextureImage(
                            ImageDescriptor(
                                format: .rgba16,
                                texelSize: .bits16,
                                width: 1,
                                address: DisplayListParser.stableID(for: "sceneMainTex")
                            )
                        ),
                        .dpSetTile(
                            TileDescriptor(
                                format: .rgba16,
                                texelSize: .bits16,
                                line: 0,
                                tmem: 0,
                                tile: 7,
                                palette: 0,
                                clampS: false,
                                mirrorS: false,
                                maskS: 5,
                                shiftS: 0,
                                clampT: false,
                                mirrorT: false,
                                maskT: 5,
                                shiftT: 0
                            )
                        ),
                        .dpLoadSync,
                        .dpLoadBlock(
                            LoadBlockCommand(
                                tile: 7,
                                upperLeftS: 0,
                                upperLeftT: 0,
                                texelCount: 1023,
                                dxt: 256
                            )
                        ),
                        .dpPipeSync,
                        .dpSetTile(
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
                                clampT: false,
                                mirrorT: false,
                                maskT: 5,
                                shiftT: 0
                            )
                        ),
                        .dpSetTileSize(
                            TileSizeCommand(
                                tile: 0,
                                upperLeftS: 0,
                                upperLeftT: 0,
                                lowerRightS: 124,
                                lowerRightT: 124
                            )
                        ),
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testParserMasksCombineFieldsToHardwareBitWidths() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("combine-scene.c")
        try """
        #include "gfx.h"

        static Gfx combineDL[] = {
            gsDPSetCombineLERP(TEXEL0, 0, SHADE, 0, 0, 0, 0, 1, COMBINED, 0, PRIMITIVE, 0, 0, 0, 0, COMBINED),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "combineDL",
                    commands: [
                        .dpSetCombineMode(
                            CombineMode(
                                colorMux: 1_211_907,
                                alphaMux: 4_294_966_776
                            )
                        ),
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testParserExpandsLoadTLUTPal16Macro() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("pal16.c")
        try """
        #include "gfx.h"

        static Gfx pal16DL[] = {
            gsDPLoadTLUT_pal16(3, sceneTLUT),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "pal16DL",
                    commands: [
                        .dpSetTextureImage(
                            ImageDescriptor(
                                format: .rgba16,
                                texelSize: .bits16,
                                width: 1,
                                address: DisplayListParser.stableID(for: "sceneTLUT")
                            )
                        ),
                        .dpTileSync,
                        .dpSetTile(
                            TileDescriptor(
                                format: .rgba16,
                                texelSize: .bits16,
                                line: 0,
                                tmem: 304,
                                tile: 7,
                                palette: 0,
                                clampS: false,
                                mirrorS: false,
                                maskS: 0,
                                shiftS: 0,
                                clampT: false,
                                mirrorT: false,
                                maskT: 0,
                                shiftT: 0
                            )
                        ),
                        .dpLoadSync,
                        .dpLoadTLUT(LoadTLUTCommand(tile: 7, colorCount: 15)),
                        .dpPipeSync,
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testParserExpandsLoadMultiBlock4bMacro() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("multi-block-4b.c")
        try """
        #include "gfx.h"

        static Gfx multiBlock4bDL[] = {
            gsDPLoadMultiBlock_4b(sceneMaskTex, 0x0100, 1, G_IM_FMT_I, 16, 16, 0, G_TX_NOMIRROR | G_TX_WRAP, G_TX_NOMIRROR | G_TX_WRAP, 4, 4, G_TX_NOLOD, G_TX_NOLOD),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "multiBlock4bDL",
                    commands: [
                        .dpSetTextureImage(
                            ImageDescriptor(
                                format: .i4,
                                texelSize: .bits16,
                                width: 1,
                                address: DisplayListParser.stableID(for: "sceneMaskTex")
                            )
                        ),
                        .dpSetTile(
                            TileDescriptor(
                                format: .i4,
                                texelSize: .bits16,
                                line: 0,
                                tmem: 256,
                                tile: 7,
                                palette: 0,
                                clampS: false,
                                mirrorS: false,
                                maskS: 4,
                                shiftS: 0,
                                clampT: false,
                                mirrorT: false,
                                maskT: 4,
                                shiftT: 0
                            )
                        ),
                        .dpLoadSync,
                        .dpLoadBlock(
                            LoadBlockCommand(
                                tile: 7,
                                upperLeftS: 0,
                                upperLeftT: 0,
                                texelCount: 63,
                                dxt: 2048
                            )
                        ),
                        .dpPipeSync,
                        .dpSetTile(
                            TileDescriptor(
                                format: .i4,
                                texelSize: .bits4,
                                line: 1,
                                tmem: 256,
                                tile: 1,
                                palette: 0,
                                clampS: false,
                                mirrorS: false,
                                maskS: 4,
                                shiftS: 0,
                                clampT: false,
                                mirrorT: false,
                                maskT: 4,
                                shiftT: 0
                            )
                        ),
                        .dpSetTileSize(
                            TileSizeCommand(
                                tile: 1,
                                upperLeftS: 0,
                                upperLeftT: 0,
                                lowerRightS: 60,
                                lowerRightT: 60
                            )
                        ),
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testParserBuildsBranchLessZRawCommand() throws {
        let fixtureRoot = try makeFixtureRoot()
        let sourceFile = fixtureRoot.appendingPathComponent("branch-less-z.c")
        try """
        #include "gfx.h"

        static Gfx branchLessZDL[] = {
            gsSPBranchLessZraw(sceneBranchDL, 7, 0x1770),
            gsSPEndDisplayList(),
        };
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let displayLists = try DisplayListParser().parseDisplayLists(in: sourceFile, sourceRoot: fixtureRoot)

        XCTAssertEqual(
            displayLists,
            [
                ParsedDisplayList(
                    name: "branchLessZDL",
                    commands: [
                        .spBranchLessZ(
                            BranchLessZCommand(
                                branchAddress: DisplayListParser.stableID(for: "sceneBranchDL"),
                                vertexIndex: 7,
                                zValue: 0x1770
                            )
                        ),
                        .spEndDisplayList,
                    ]
                ),
            ]
        )
    }

    func testExtractorSkipsSourceFileWhenDisplayListContainsUnsupportedMacro() throws {
        let fixtureRoot = try makeFixtureRoot()
        let assetsDirectory = fixtureRoot.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        try """
        #include "gfx.h"

        Gfx gValidDL[] = {
            gsSPEndDisplayList(),
        };
        """.write(
            to: fixtureRoot.appendingPathComponent("assets/valid.c"),
            atomically: true,
            encoding: .utf8
        )

        try """
        #include "gfx.h"

        Gfx gUnsupportedDL[] = {
            gsSPUnsupportedCommand(0),
            gsSPEndDisplayList(),
        };
        """.write(
            to: fixtureRoot.appendingPathComponent("assets/unsupported.c"),
            atomically: true,
            encoding: .utf8
        )

        let outputRoot = fixtureRoot.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        XCTAssertNoThrow(try DisplayListParser().extract(using: OOTExtractionContext(source: fixtureRoot, output: outputRoot)))

        let outputFiles = FileManager.default.enumerator(
            at: outputRoot.appendingPathComponent("DisplayLists", isDirectory: true),
            includingPropertiesForKeys: nil
        )?
        .compactMap { ($0 as? URL)?.lastPathComponent } ?? []

        XCTAssertTrue(outputFiles.contains("gValidDL.json"))
        XCTAssertFalse(outputFiles.contains("gUnsupportedDL.json"))
    }

    func testExtractorSkipsSourceFileWhenIncludeBackedAssetSourceIsMissing() throws {
        let fixtureRoot = try makeFixtureRoot()
        let assetsDirectory = fixtureRoot.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        try """
        #include "gfx.h"

        u64 gMissingTex[] = {
        #include "assets/missing.inc.c"
        };

        Gfx gResilientDL[] = {
            gsSPEndDisplayList(),
        };
        """.write(
            to: fixtureRoot.appendingPathComponent("assets/missing-include.c"),
            atomically: true,
            encoding: .utf8
        )

        let outputRoot = fixtureRoot.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        XCTAssertNoThrow(try DisplayListParser().extract(using: OOTExtractionContext(source: fixtureRoot, output: outputRoot)))

        let outputFiles = FileManager.default.enumerator(
            at: outputRoot.appendingPathComponent("DisplayLists", isDirectory: true),
            includingPropertiesForKeys: nil
        )?
        .compactMap { ($0 as? URL)?.lastPathComponent } ?? []

        XCTAssertTrue(outputFiles.contains("gResilientDL.json"))
    }

    private func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftoot-displaylists-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let includeDirectory = root.appendingPathComponent("include/ultra64", isDirectory: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        try fixtureHeader().write(
            to: includeDirectory.appendingPathComponent("gbi.h"),
            atomically: true,
            encoding: .utf8
        )
        try """
        #include "ultra64/gbi.h"
        """.write(
            to: root.appendingPathComponent("gfx.h"),
            atomically: true,
            encoding: .utf8
        )

        return root
    }

    private func fixtureHeader() -> String {
        """
        #define G_ON 1
        #define G_OFF 0

        #define G_MTX_MODELVIEW 0x00
        #define G_MTX_PROJECTION 0x04
        #define G_MTX_LOAD 0x02
        #define G_MTX_NOPUSH 0x00
        #define G_MTX_PUSH 0x01

        #define G_TX_LOADTILE 7
        #define G_TX_RENDERTILE 0
        #define G_TX_NOMIRROR (0 << 0)
        #define G_TX_WRAP (0 << 1)
        #define G_TX_MIRROR (1 << 0)
        #define G_TX_CLAMP (1 << 1)
        #define G_TX_NOLOD 0

        #define G_IM_FMT_RGBA 0
        #define G_IM_FMT_I 4
        #define G_IM_FMT_IA 3
        #define G_IM_SIZ_4b 0
        #define G_IM_SIZ_8b 1
        #define G_IM_SIZ_16b 2
        #define G_IM_SIZ_32b 3
        #define G_TT_RGBA16 (2 << 14)

        #define G_ZBUFFER 0x00000001
        #define G_SHADE 0x00000004
        #define G_CULL_BACK 0x00002000
        #define G_LIGHTING 0x00020000
        #define G_TEXTURE_GEN 0x00040000
        #define G_TEXTURE_GEN_LINEAR 0x00080000
        #define G_FOG 0x00010000

        #define AA_EN 0x0008
        #define Z_CMP 0x0010
        #define Z_UPD 0x0020
        #define IM_RD 0x0040
        #define CLR_ON_CVG 0x0080
        #define CVG_DST_WRAP 0x0100
        #define FORCE_BL 0x4000
        #define ZMODE_OPA 0x0000
        #define ZMODE_XLU 0x0800
        #define ALPHA_CVG_SEL 0x2000

        #define G_BL_CLR_IN 0
        #define G_BL_A_IN 0
        #define G_BL_CLR_MEM 1
        #define G_BL_A_MEM 1
        #define G_BL_1MA 1
        #define G_BL_CLR_FOG 1
        #define G_BL_A_SHADE 2

        #define GBL_c1(m1a, m1b, m2a, m2b) ((m1a) << 30 | (m1b) << 26 | (m2a) << 22 | (m2b) << 18)
        #define GBL_c2(m1a, m1b, m2a, m2b) ((m1a) << 28 | (m1b) << 24 | (m2a) << 20 | (m2b) << 16)

        #define G_RM_FOG_SHADE_A GBL_c1(G_BL_CLR_FOG, G_BL_A_SHADE, G_BL_CLR_IN, G_BL_1MA)
        #define G_RM_AA_ZB_OPA_SURF2 (AA_EN | Z_CMP | Z_UPD | IM_RD | ALPHA_CVG_SEL | GBL_c2(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM))

        #define COMBINED COMBINED
        #define TEXEL0 TEXEL0
        #define TEXEL1 TEXEL1
        #define PRIMITIVE PRIMITIVE
        #define SHADE SHADE
        #define ENVIRONMENT ENVIRONMENT
        #define CENTER CENTER
        #define SCALE SCALE
        #define COMBINED_ALPHA COMBINED_ALPHA
        #define TEXEL0_ALPHA TEXEL0_ALPHA
        #define TEXEL1_ALPHA TEXEL1_ALPHA
        #define PRIMITIVE_ALPHA PRIMITIVE_ALPHA
        #define SHADE_ALPHA SHADE_ALPHA
        #define ENV_ALPHA ENV_ALPHA
        #define LOD_FRACTION LOD_FRACTION
        #define PRIM_LOD_FRAC PRIM_LOD_FRAC
        #define NOISE NOISE
        #define K4 K4
        #define K5 K5

        #define G_CC_PRIMITIVE 0, 0, 0, PRIMITIVE, 0, 0, 0, PRIMITIVE
        #define G_CC_PASS2 0, 0, 0, COMBINED, 0, 0, 0, COMBINED
        """
    }

    private func fixtureSource() -> String {
        """
        #include "gfx.h"

        #define sceneTexWidth 32

        static Gfx sceneMainDL[] = {
            gsSPVertex(sceneName_Vtx_0000, 4, 0),
            gsSPCullDisplayList(0, 3),
            gsSP1Triangle(0, 1, 2, 0),
            gsSP2Triangles(0, 2, 3, 0, 3, 2, 1, 0),
            gsSPDisplayList(sceneSubDL),
            gsSPBranchDL(sceneBranchDL),
            gsSPMatrix(sceneMainMtx, G_MTX_NOPUSH | G_MTX_LOAD | G_MTX_PROJECTION),
            gsSPPopMatrix(G_MTX_MODELVIEW),
            gsSPTexture(0xFFFF, 0x4000, 0, G_TX_RENDERTILE, G_ON),
            gsDPSetTextureLUT(G_TT_RGBA16),
            gsDPSetTextureImage(G_IM_FMT_RGBA, G_IM_SIZ_16b, sceneTexWidth, sceneMainTex),
            gsDPLoadBlock(G_TX_LOADTILE, 0, 0, 255, 16),
            gsDPLoadTile(G_TX_LOADTILE, 0, 0, 31, 31),
            gsDPSetTile(G_IM_FMT_RGBA, G_IM_SIZ_16b, 8, 0, G_TX_RENDERTILE, 0, G_TX_WRAP | G_TX_NOMIRROR, 0, 0, G_TX_CLAMP | G_TX_NOMIRROR, 5, 0),
            gsDPSetTileSize(G_TX_RENDERTILE, 0, 0, 124, 124),
            gsDPSetCombineLERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT, PRIMITIVE, 0, TEXEL0, 0, 0, 0, 0, COMBINED, 0, 0, 0, COMBINED),
            gsDPSetCombineMode(G_CC_PRIMITIVE, G_CC_PASS2),
            gsDPSetRenderMode(G_RM_FOG_SHADE_A, G_RM_AA_ZB_OPA_SURF2),
            gsSPGeometryMode(G_ZBUFFER | G_SHADE, G_CULL_BACK),
            gsSPSetGeometryMode(G_LIGHTING | G_TEXTURE_GEN),
            gsSPClearGeometryMode(G_FOG | G_TEXTURE_GEN_LINEAR),
            gsDPSetPrimColor(0, 128, 255, 64, 32, 200),
            gsDPSetEnvColor(10, 20, 30, 40),
            gsDPSetFogColor(50, 60, 70, 80),
            gsDPPipeSync(),
            gsDPTileSync(),
            gsDPLoadSync(),
            gsSPEndDisplayList(),
        };
        """
    }

    private func expectedCommands() -> [F3DEX2Command] {
        [
            .spVertex(
                VertexCommand(
                    address: DisplayListParser.stableID(for: "sceneName_Vtx_0000"),
                    count: 4,
                    destinationIndex: 0
                )
            ),
            .spCullDisplayList(CullDisplayListCommand(firstVertex: 0, lastVertex: 3)),
            .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2, flag: 0)),
            .sp2Triangles(
                TrianglePairCommand(
                    first: TriangleCommand(vertex0: 0, vertex1: 2, vertex2: 3, flag: 0),
                    second: TriangleCommand(vertex0: 3, vertex1: 2, vertex2: 1, flag: 0)
                )
            ),
            .spDisplayList(DisplayListParser.stableID(for: "sceneSubDL")),
            .spBranchList(DisplayListParser.stableID(for: "sceneBranchDL")),
            .spMatrix(
                MatrixCommand(
                    address: DisplayListParser.stableID(for: "sceneMainMtx"),
                    projection: true,
                    load: true,
                    push: false
                )
            ),
            .spPopMatrix(0),
            .spTexture(TextureState(scaleS: 0xFFFF, scaleT: 0x4000, level: 0, tile: 0, enabled: true)),
            .dpSetTextureLUT(.rgba16),
            .dpSetTextureImage(
                ImageDescriptor(
                    format: .rgba16,
                    texelSize: .bits16,
                    width: 32,
                    address: DisplayListParser.stableID(for: "sceneMainTex")
                )
            ),
            .dpLoadBlock(LoadBlockCommand(tile: 7, upperLeftS: 0, upperLeftT: 0, texelCount: 255, dxt: 16)),
            .dpLoadTile(LoadTileCommand(tile: 7, upperLeftS: 0, upperLeftT: 0, lowerRightS: 31, lowerRightT: 31)),
            .dpSetTile(
                TileDescriptor(
                    format: .rgba16,
                    texelSize: .bits16,
                    line: 8,
                    tmem: 0,
                    tile: 0,
                    palette: 0,
                    clampS: true,
                    mirrorS: false,
                    maskS: 5,
                    shiftS: 0,
                    clampT: false,
                    mirrorT: false,
                    maskT: 0,
                    shiftT: 0
                )
            ),
            .dpSetTileSize(TileSizeCommand(tile: 0, upperLeftS: 0, upperLeftT: 0, lowerRightS: 124, lowerRightT: 124)),
            .dpSetCombineMode(
                CombineMode(
                    colorMux: combineColorMux(
                        a0: "PRIMITIVE",
                        c0: "TEXEL0",
                        Aa0: "PRIMITIVE",
                        Ac0: "TEXEL0",
                        a1: "0",
                        c1: "0"
                    ),
                    alphaMux: combineAlphaMux(
                        b0: "ENVIRONMENT",
                        d0: "ENVIRONMENT",
                        Ab0: "0",
                        Ad0: "0",
                        b1: "0",
                        Aa1: "0",
                        Ac1: "0",
                        d1: "COMBINED",
                        Ab1: "0",
                        Ad1: "COMBINED"
                    )
                )
            ),
            .dpSetCombineMode(
                CombineMode(
                    colorMux: combineColorMux(
                        a0: "0",
                        c0: "0",
                        Aa0: "0",
                        Ac0: "0",
                        a1: "0",
                        c1: "0"
                    ),
                    alphaMux: combineAlphaMux(
                        b0: "0",
                        d0: "PRIMITIVE",
                        Ab0: "0",
                        Ad0: "PRIMITIVE",
                        b1: "0",
                        Aa1: "0",
                        Ac1: "0",
                        d1: "COMBINED",
                        Ab1: "0",
                        Ad1: "COMBINED"
                    )
                )
            ),
            .dpSetRenderMode(RenderMode(flags: 1_209_344_120)),
            .spGeometryMode(GeometryModeCommand(clearBits: 0x00000001 | 0x00000004, setBits: 0x00002000)),
            .spGeometryMode(GeometryModeCommand(clearBits: 0, setBits: 0x00020000 | 0x00040000)),
            .spGeometryMode(GeometryModeCommand(clearBits: 0x00010000 | 0x00080000, setBits: 0)),
            .dpSetPrimColor(
                PrimitiveColor(
                    minimumLOD: 0,
                    level: 128,
                    color: RGBA8(red: 255, green: 64, blue: 32, alpha: 200)
                )
            ),
            .dpSetEnvColor(RGBA8(red: 10, green: 20, blue: 30, alpha: 40)),
            .dpSetFogColor(RGBA8(red: 50, green: 60, blue: 70, alpha: 80)),
            .dpPipeSync,
            .dpTileSync,
            .dpLoadSync,
            .spEndDisplayList,
        ]
    }

    private func combineColorMux(
        a0: String,
        c0: String,
        Aa0: String,
        Ac0: String,
        a1: String,
        c1: String
    ) -> UInt32 {
        ((combineColorSource(a0) & 0x0F) << 20) |
        ((combineColorSource(c0) & 0x1F) << 15) |
        ((combineAlphaSource(Aa0) & 0x07) << 12) |
        ((combineAlphaSource(Ac0) & 0x07) << 9) |
        ((combineColorSource(a1) & 0x0F) << 5) |
        (combineColorSource(c1) & 0x1F)
    }

    private func combineAlphaMux(
        b0: String,
        d0: String,
        Ab0: String,
        Ad0: String,
        b1: String,
        Aa1: String,
        Ac1: String,
        d1: String,
        Ab1: String,
        Ad1: String
    ) -> UInt32 {
        ((combineColorSource(b0) & 0x0F) << 28) |
        ((combineColorSource(d0) & 0x07) << 15) |
        ((combineAlphaSource(Ab0) & 0x07) << 12) |
        ((combineAlphaSource(Ad0) & 0x07) << 9) |
        ((combineColorSource(b1) & 0x0F) << 24) |
        ((combineAlphaSource(Aa1) & 0x07) << 21) |
        ((combineAlphaSource(Ac1) & 0x07) << 18) |
        ((combineColorSource(d1) & 0x07) << 6) |
        ((combineAlphaSource(Ab1) & 0x07) << 3) |
        (combineAlphaSource(Ad1) & 0x07)
    }

    private func combineColorSource(_ value: String) -> UInt32 {
        switch value {
        case "COMBINED":
            return 0
        case "TEXEL0":
            return 1
        case "TEXEL1":
            return 2
        case "PRIMITIVE":
            return 3
        case "SHADE":
            return 4
        case "ENVIRONMENT":
            return 5
        case "CENTER", "SCALE", "1":
            return 6
        case "COMBINED_ALPHA", "NOISE", "K4":
            return 7
        case "TEXEL0_ALPHA":
            return 8
        case "TEXEL1_ALPHA":
            return 9
        case "PRIMITIVE_ALPHA":
            return 10
        case "SHADE_ALPHA":
            return 11
        case "ENV_ALPHA":
            return 12
        case "LOD_FRACTION":
            return 13
        case "PRIM_LOD_FRAC":
            return 14
        case "K5":
            return 15
        case "0":
            return 31
        default:
            fatalError("Unhandled combiner color source \(value)")
        }
    }

    private func combineAlphaSource(_ value: String) -> UInt32 {
        switch value {
        case "COMBINED", "LOD_FRACTION":
            return 0
        case "TEXEL0":
            return 1
        case "TEXEL1":
            return 2
        case "PRIMITIVE":
            return 3
        case "SHADE":
            return 4
        case "ENVIRONMENT":
            return 5
        case "PRIM_LOD_FRAC", "1":
            return 6
        case "0":
            return 7
        default:
            fatalError("Unhandled combiner alpha source \(value)")
        }
    }
}
