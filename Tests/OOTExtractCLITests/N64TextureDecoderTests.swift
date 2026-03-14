import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class N64TextureDecoderTests: XCTestCase {
    private let decoder = N64TextureDecoder()

    func testDecodeRGBA16ExpandsToRGBA8888AndSetsMetadata() throws {
        let decoded = try decoder.decode(
            format: .rgba16,
            width: 2,
            height: 1,
            texelData: .words([0xF801, 0x07C0])
        )

        XCTAssertEqual(
            [UInt8](decoded.texelData),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0x00,
            ]
        )
        XCTAssertNil(decoded.tlutData)
        XCTAssertEqual(
            decoded.metadata,
            TextureAssetMetadata(format: .rgba16, width: 2, height: 1, hasTLUT: false)
        )
    }

    func testDecodeCI4ExpandsIndicesAndRGBA16TLUT() throws {
        let decoded = try decoder.decode(
            format: .ci4,
            width: 3,
            height: 1,
            texelData: .bytes([0x12, 0x30]),
            tlutData: .words([0xF801, 0x07C1, 0x003F, 0xFFFF])
        )

        XCTAssertEqual([UInt8](decoded.texelData), [0x01, 0x02, 0x03])
        XCTAssertEqual(
            [UInt8](try XCTUnwrap(decoded.tlutData)),
            [
                0xFF, 0x00, 0x00, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF,
            ]
        )
        XCTAssertEqual(
            decoded.metadata,
            TextureAssetMetadata(format: .ci4, width: 3, height: 1, hasTLUT: true)
        )
    }

    func testDecodeCI8PreservesIndicesAndSupportsIA16TLUT() throws {
        let decoded = try decoder.decode(
            format: .ci8,
            width: 2,
            height: 1,
            texelData: .bytes([0x00, 0x01]),
            tlutData: .words([0x20FF, 0x8000]),
            tlutFormat: .ia16
        )

        XCTAssertEqual([UInt8](decoded.texelData), [0x00, 0x01])
        XCTAssertEqual(
            [UInt8](try XCTUnwrap(decoded.tlutData)),
            [
                0x20, 0x20, 0x20, 0xFF,
                0x80, 0x80, 0x80, 0x00,
            ]
        )
    }

    func testDecodeI4ExpandsToOneBytePerPixel() throws {
        let decoded = try decoder.decode(
            format: .i4,
            width: 3,
            height: 1,
            texelData: .bytes([0xF1, 0x20])
        )

        XCTAssertEqual([UInt8](decoded.texelData), [0xFF, 0x11, 0x22])
    }

    func testDecodeI8PreservesSourceBytes() throws {
        let decoded = try decoder.decode(
            format: .i8,
            width: 3,
            height: 1,
            texelData: .bytes([0x00, 0x7F, 0xFF])
        )

        XCTAssertEqual([UInt8](decoded.texelData), [0x00, 0x7F, 0xFF])
    }

    func testDecodeIA4ExpandsToIntensityAlphaPairs() throws {
        let decoded = try decoder.decode(
            format: .ia4,
            width: 3,
            height: 1,
            texelData: .bytes([0xF2, 0x40])
        )

        XCTAssertEqual(
            [UInt8](decoded.texelData),
            [
                0xFF, 0xFF,
                0x24, 0x00,
                0x49, 0x00,
            ]
        )
    }

    func testDecodeIA8ExpandsToIntensityAlphaPairs() throws {
        let decoded = try decoder.decode(
            format: .ia8,
            width: 2,
            height: 1,
            texelData: .bytes([0xF1, 0x27])
        )

        XCTAssertEqual(
            [UInt8](decoded.texelData),
            [
                0xFF, 0x11,
                0x22, 0x77,
            ]
        )
    }

    func testDecodeIA16PreservesBigEndianIntensityAlphaBytes() throws {
        let decoded = try decoder.decode(
            format: .ia16,
            width: 2,
            height: 1,
            texelData: .words([0x12AB, 0x34CD])
        )

        XCTAssertEqual([UInt8](decoded.texelData), [0x12, 0xAB, 0x34, 0xCD])
    }

    func testDecodeRGBA32PreservesSourceBytes() throws {
        let decoded = try decoder.decode(
            format: .rgba32,
            width: 2,
            height: 1,
            texelData: .bytes([0x01, 0x02, 0x03, 0x04, 0xAA, 0xBB, 0xCC, 0xDD])
        )

        XCTAssertEqual(
            [UInt8](decoded.texelData),
            [0x01, 0x02, 0x03, 0x04, 0xAA, 0xBB, 0xCC, 0xDD]
        )
    }

    func testDecodeThrowsWhenTextureByteCountIsWrong() {
        XCTAssertThrowsError(
            try decoder.decode(
                format: .rgba16,
                width: 2,
                height: 1,
                texelData: .bytes([0x00, 0x01])
            )
        ) { error in
            XCTAssertEqual(
                error as? N64TextureDecoderError,
                .invalidTexelCount(format: .rgba16, expectedByteCount: 4, actualByteCount: 2)
            )
        }
    }

    func testDecodeThrowsWhenCITLUTIsMissing() {
        XCTAssertThrowsError(
            try decoder.decode(
                format: .ci8,
                width: 1,
                height: 1,
                texelData: .bytes([0x00])
            )
        ) { error in
            XCTAssertEqual(error as? N64TextureDecoderError, .missingTLUT(format: .ci8))
        }
    }

    func testTextureAssetMetadataRoundTripsThroughJSON() throws {
        let metadata = TextureAssetMetadata(format: .ci4, width: 16, height: 16, hasTLUT: true)

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(TextureAssetMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
    }
}
