import XCTest
import Foundation
import Metal
import OOTDataModel
@testable import OOTContent

final class OOTContentTests: XCTestCase {
    func testContentLoaderConformsToProtocol() {
        let loader: any ContentLoading = ContentLoader(sceneLoader: StubSceneLoader())

        XCTAssertNotNil(loader)
    }

    func testConfiguredContentRootAcceptsDirectContentSelection() throws {
        let fixture = try ContentRootFixture()
        defer { fixture.cleanup() }

        XCTAssertEqual(
            ContentRootConfiguration.resolveConfiguredContentRoot(from: fixture.contentRoot),
            fixture.contentRoot
        )
    }

    func testConfiguredContentRootAcceptsRepoRootSelection() throws {
        let fixture = try ContentRootFixture()
        defer { fixture.cleanup() }

        XCTAssertEqual(
            ContentRootConfiguration.resolveConfiguredContentRoot(from: fixture.repoRoot),
            fixture.contentRoot
        )
    }

    func testConfiguredContentRootRejectsDirectoriesWithoutSceneTable() throws {
        let fixture = try ContentRootFixture()
        defer { fixture.cleanup() }

        let invalidRoot = fixture.repoRoot.appendingPathComponent("Missing", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)

        XCTAssertNil(ContentRootConfiguration.resolveConfiguredContentRoot(from: invalidRoot))
    }

    func testBinaryDecoderMapsRGBAFormatsToRGBA8Textures() throws {
        let decoder = TextureBinaryDecoder()
        let formats: [TextureFormat] = [.rgba16, .rgba32]

        for format in formats {
            let decodedTexture = try decoder.decodeTextureData(
                binaryData: Data([0x10, 0x20, 0x30, 0x40, 0xAA, 0xBB, 0xCC, 0xDD]),
                metadata: TextureAssetMetadata(format: format, width: 2, height: 1, hasTLUT: false)
            )

            XCTAssertEqual(decodedTexture.pixelFormat, .rgba8Unorm)
            XCTAssertEqual(decodedTexture.bytesPerRow, 8)
            XCTAssertEqual(
                [UInt8](decodedTexture.pixelData),
                [0x10, 0x20, 0x30, 0x40, 0xAA, 0xBB, 0xCC, 0xDD]
            )
        }
    }

    func testBinaryDecoderMapsIAFormatsToRG8Textures() throws {
        let decoder = TextureBinaryDecoder()
        let formats: [TextureFormat] = [.ia4, .ia8, .ia16]

        for format in formats {
            let decodedTexture = try decoder.decodeTextureData(
                binaryData: Data([0x10, 0xF0, 0xAA, 0x55]),
                metadata: TextureAssetMetadata(format: format, width: 2, height: 1, hasTLUT: false)
            )

            XCTAssertEqual(decodedTexture.pixelFormat, .rg8Unorm)
            XCTAssertEqual(decodedTexture.bytesPerRow, 4)
            XCTAssertEqual([UInt8](decodedTexture.pixelData), [0x10, 0xF0, 0xAA, 0x55])
        }
    }

    func testBinaryDecoderMapsIFormatsToR8Textures() throws {
        let decoder = TextureBinaryDecoder()
        let formats: [TextureFormat] = [.i4, .i8]

        for format in formats {
            let decodedTexture = try decoder.decodeTextureData(
                binaryData: Data([0x10, 0xAA, 0x55]),
                metadata: TextureAssetMetadata(format: format, width: 3, height: 1, hasTLUT: false)
            )

            XCTAssertEqual(decodedTexture.pixelFormat, .r8Unorm)
            XCTAssertEqual(decodedTexture.bytesPerRow, 3)
            XCTAssertEqual([UInt8](decodedTexture.pixelData), [0x10, 0xAA, 0x55])
        }
    }

    func testBinaryDecoderResolvesCI4PaletteToRGBA8888() throws {
        let decoder = TextureBinaryDecoder()
        var binary = Data([0x01, 0x02, 0x03])
        binary.append(
            contentsOf: [
                0x00, 0x00, 0x00, 0x00,
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
            ]
        )
        binary.append(contentsOf: [UInt8](repeating: 0x00, count: (16 * 4) - 16))

        let decodedTexture = try decoder.decodeTextureData(
            binaryData: binary,
            metadata: TextureAssetMetadata(format: .ci4, width: 3, height: 1, hasTLUT: true)
        )

        XCTAssertEqual(decodedTexture.pixelFormat, .rgba8Unorm)
        XCTAssertEqual(decodedTexture.bytesPerRow, 12)
        XCTAssertEqual(
            [UInt8](decodedTexture.pixelData),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
            ]
        )
    }

    func testBinaryDecoderResolvesCI8PaletteToRGBA8888() throws {
        let decoder = TextureBinaryDecoder()
        var binary = Data([0x00, 0x02])
        var palette = [UInt8](repeating: 0x00, count: 256 * 4)
        palette.replaceSubrange(0 ..< 4, with: [0x10, 0x20, 0x30, 0x40])
        palette.replaceSubrange(8 ..< 12, with: [0xAA, 0xBB, 0xCC, 0xDD])
        binary.append(contentsOf: palette)

        let decodedTexture = try decoder.decodeTextureData(
            binaryData: binary,
            metadata: TextureAssetMetadata(format: .ci8, width: 2, height: 1, hasTLUT: true)
        )

        XCTAssertEqual(decodedTexture.pixelFormat, .rgba8Unorm)
        XCTAssertEqual(decodedTexture.bytesPerRow, 8)
        XCTAssertEqual(
            [UInt8](decodedTexture.pixelData),
            [0x10, 0x20, 0x30, 0x40, 0xAA, 0xBB, 0xCC, 0xDD]
        )
    }

    @MainActor
    func testMetalTextureLoaderCreatesRGBA16TextureWithMetadataDimensions() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let fixture = try TextureFixture()
        defer { fixture.cleanup() }

        let textureURL = try fixture.writeTexture(
            name: "gObjectTestTex",
            binary: [0xFF, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00],
            metadata: TextureAssetMetadata(format: .rgba16, width: 2, height: 1, hasTLUT: false)
        )

        let texture = try MetalTextureLoader(device: device).loadTexture(at: textureURL)

        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.pixelFormat, .rgba8Unorm)
    }

    @MainActor
    func testMetalTextureLoaderResolvesCI4TextureIntoRGBA8888Pixels() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let fixture = try TextureFixture()
        defer { fixture.cleanup() }

        var binary = Data([0x01, 0x02, 0x03])
        binary.append(
            contentsOf: [
                0x00, 0x00, 0x00, 0x00,
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
            ]
        )
        binary.append(contentsOf: [UInt8](repeating: 0x00, count: (16 * 4) - 16))

        let textureURL = try fixture.writeTexture(
            name: "gSpot04MainTex",
            binary: binary,
            metadata: TextureAssetMetadata(format: .ci4, width: 3, height: 1, hasTLUT: true)
        )

        let texture = try MetalTextureLoader(device: device).loadTexture(at: textureURL)

        XCTAssertEqual(texture.pixelFormat, .rgba8Unorm)
        XCTAssertEqual(texture.width, 3)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(
            rgbaPixels(in: texture),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
            ]
        )
    }

    @MainActor
    func testMetalTextureLoaderCachesByTexturePath() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let fixture = try TextureFixture()
        defer { fixture.cleanup() }

        let firstTextureURL = try fixture.writeTexture(
            name: "gFirstTex",
            binary: [0xFF, 0x00, 0x00, 0xFF],
            metadata: TextureAssetMetadata(format: .rgba16, width: 1, height: 1, hasTLUT: false)
        )
        let secondTextureURL = try fixture.writeTexture(
            name: "gSecondTex",
            binary: [0x00, 0xFF, 0x00, 0xFF],
            metadata: TextureAssetMetadata(format: .rgba16, width: 1, height: 1, hasTLUT: false)
        )

        let loader = MetalTextureLoader(device: device, cacheCapacity: 2)
        let firstLoad = try loader.loadTexture(at: firstTextureURL)
        let secondLoad = try loader.loadTexture(at: firstTextureURL)
        let distinctTexture = try loader.loadTexture(at: secondTextureURL)

        XCTAssertTrue((firstLoad as AnyObject) === (secondLoad as AnyObject))
        XCTAssertFalse((firstLoad as AnyObject) === (distinctTexture as AnyObject))
    }

    private func rgbaPixels(in texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return pixels
    }
}

private struct StubSceneLoader: SceneLoading {
    func loadSceneTableEntries() throws -> [SceneTableEntry] { [] }
    func resolveSceneDirectory(for _: Int) throws -> URL { URL(fileURLWithPath: "/tmp") }
    func loadScene(id: Int) throws -> LoadedScene { throw SceneLoaderError.unknownSceneID(id) }
    func loadScene(named name: String) throws -> LoadedScene { throw SceneLoaderError.missingFile(name) }
    func loadTextureAssetURLs(for scene: LoadedScene) throws -> [UInt32: URL] { [:] }
    func loadSceneManifest(id: Int) throws -> SceneManifest { throw SceneLoaderError.unknownSceneID(id) }
    func loadSceneManifest(named name: String) throws -> SceneManifest { throw SceneLoaderError.missingFile(name) }
    func loadActorTable() throws -> [ActorTableEntry] { [] }
    func loadObjectTable() throws -> [ObjectTableEntry] { [] }
    func loadObject(named name: String) throws -> LoadedObject { throw SceneLoaderError.missingFile(name) }
    func loadEntranceTable() throws -> [EntranceTableEntry] { [] }
    func loadCollisionMesh(for manifest: SceneManifest) throws -> CollisionMesh? { nil }
    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] { [] }
    func loadRoomVertexData(for room: RoomManifest) throws -> Data { Data() }
}

private struct ContentRootFixture {
    let repoRoot: URL
    let contentRoot: URL

    init() throws {
        let fileManager = FileManager.default
        repoRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "OOTContentRootFixture-\(UUID().uuidString)",
            isDirectory: true
        )
        contentRoot = repoRoot
            .appendingPathComponent("Content", isDirectory: true)
            .appendingPathComponent("OOT", isDirectory: true)

        try fileManager.createDirectory(
            at: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true),
            withIntermediateDirectories: true
        )

        try Data("[]".utf8).write(
            to: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("scene-table.json"),
            options: .atomic
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repoRoot)
    }
}

private struct TextureFixture {
    let root: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "OOTContentTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
    }

    func writeTexture(
        name: String,
        binary: some DataProtocol,
        metadata: TextureAssetMetadata
    ) throws -> URL {
        let binaryURL = root.appendingPathComponent("\(name).tex.bin")
        let metadataURL = root.appendingPathComponent("\(name).tex.json")

        try Data(binary).write(to: binaryURL, options: .atomic)
        try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)

        return binaryURL
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
