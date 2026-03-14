import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class VertexParserTests: XCTestCase {
    func testExtractWritesPackedBinaryForDecimalAndHexVertexMacros() throws {
        let harness = try TestHarness()
        defer { harness.cleanup() }

        try harness.writeSource(
            at: "assets/scenes/test_scene/sample.inc.c",
            contents: """
            Vtx sceneName_Vtx_0000[] = {
                VTX(-1, 0x0002, 3, 0, -4, 0x10, 32, 48, 0xFF),
                VTX(0xFFFE, -8, 9, 0x8000, 0xFFF0, 16, 1, 2, 3),
            };
            """
        )

        try VertexParser().extract(using: harness.extractionContext)

        let outputURL = harness.outputRoot
            .appendingPathComponent("assets/scenes/test_scene", isDirectory: true)
            .appendingPathComponent("sceneName_Vtx_0000.vtx.bin")

        let data = try Data(contentsOf: outputURL)
        XCTAssertEqual(
            [UInt8](data),
            [
                0xFF, 0xFF, 0x00, 0x02, 0x00, 0x03, 0x00, 0x00,
                0x00, 0x00, 0xFF, 0xFC, 0x10, 0x20, 0x30, 0xFF,
                0xFF, 0xFE, 0xFF, 0xF8, 0x00, 0x09, 0x00, 0x00,
                0x80, 0x00, 0xFF, 0xF0, 0x10, 0x01, 0x02, 0x03,
            ]
        )
    }

    func testParseVertexArraysSupportsExpandedInitializerForm() throws {
        let harness = try TestHarness()
        defer { harness.cleanup() }

        try harness.writeSource(
            at: "assets/scenes/test_scene/fused.inc.c",
            contents: """
            Vtx spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_[] = {
                { { { -1, 2, 3 }, 0, { 4, 5 }, { 6, 7, 8, 9 } } },
                { { { 10, 11, 12 }, 0, { 13, 14 }, { 15, 16, 17, 18 } } },
            };
            """
        )

        let sourceURL = harness.sourceRoot.appendingPathComponent("assets/scenes/test_scene/fused.inc.c")
        let arrays = try VertexParser().parseVertexArrays(in: sourceURL, sourceRoot: harness.sourceRoot)

        XCTAssertEqual(arrays.count, 1)
        XCTAssertEqual(
            arrays[0].name,
            "spot04_room_0_03000580_RoomShapeCullable_0300058C_CullableEntries_03002A10_DL_03001270_Vtx_fused_"
        )
        XCTAssertEqual(
            arrays[0].vertices,
            [
                N64Vertex(
                    position: Vector3s(x: -1, y: 2, z: 3),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 4, y: 5),
                    colorOrNormal: RGBA8(red: 6, green: 7, blue: 8, alpha: 9)
                ),
                N64Vertex(
                    position: Vector3s(x: 10, y: 11, z: 12),
                    flag: 0,
                    textureCoordinate: Vector2s(x: 13, y: 14),
                    colorOrNormal: RGBA8(red: 15, green: 16, blue: 17, alpha: 18)
                ),
            ]
        )
    }

    func testExtractPreservesSourceRelativeDirectoriesToAvoidCollisions() throws {
        let harness = try TestHarness()
        defer { harness.cleanup() }

        let contents = """
        Vtx shared_Vtx_0000[] = {
            VTX(0, 0, 0, 0, 0, 255, 255, 255, 255),
        };
        """

        try harness.writeSource(at: "assets/alpha/common.inc.c", contents: contents)
        try harness.writeSource(at: "assets/beta/common.inc.c", contents: contents)

        try VertexParser().extract(using: harness.extractionContext)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("assets/alpha/shared_Vtx_0000.vtx.bin")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("assets/beta/shared_Vtx_0000.vtx.bin")
                    .path
            )
        )
    }

    func testVerifyRejectsMalformedVertexBinarySize() throws {
        let harness = try TestHarness()
        defer { harness.cleanup() }

        let malformedURL = harness.outputRoot.appendingPathComponent("broken.vtx.bin")
        try Data([0x00, 0x01, 0x02]).write(to: malformedURL)

        XCTAssertThrowsError(try VertexParser().verify(using: harness.verificationContext)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a multiple of 16 bytes"))
        }
    }
}

private struct TestHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

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

    func writeSource(at relativePath: String, contents: String) throws {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
