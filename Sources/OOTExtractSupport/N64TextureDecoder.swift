import Foundation
import OOTDataModel

public enum N64TextureDataSource: Sendable, Equatable {
    case bytes([UInt8])
    case words([UInt16])

    fileprivate func bigEndianData() -> Data {
        switch self {
        case .bytes(let bytes):
            return Data(bytes)
        case .words(let words):
            var data = Data()
            data.reserveCapacity(words.count * MemoryLayout<UInt16>.size)

            for word in words {
                data.append(bigEndian: word)
            }

            return data
        }
    }
}

public struct DecodedN64Texture: Sendable, Equatable {
    public var texelData: Data
    public var tlutData: Data?
    public var metadata: TextureAssetMetadata

    public init(texelData: Data, tlutData: Data?, metadata: TextureAssetMetadata) {
        self.texelData = texelData
        self.tlutData = tlutData
        self.metadata = metadata
    }
}

public struct N64TextureDecoder: Sendable {
    public init() {}

    public func decode(
        format: TextureFormat,
        width: Int,
        height: Int,
        texelData: N64TextureDataSource,
        tlutData: N64TextureDataSource? = nil,
        tlutFormat: TextureFormat? = nil
    ) throws -> DecodedN64Texture {
        guard width > 0, height > 0 else {
            throw N64TextureDecoderError.invalidDimensions(width: width, height: height)
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard overflow == false else {
            throw N64TextureDecoderError.invalidDimensions(width: width, height: height)
        }

        let rawTexels = texelData.bigEndianData()
        try validate(textureByteCount: rawTexels.count, format: format, pixelCount: pixelCount)

        let decodedTexels = try decodeTexels(rawTexels, format: format, pixelCount: pixelCount)
        let decodedTLUT = try decodeTLUT(
            for: format,
            tlutData: tlutData,
            tlutFormat: tlutFormat
        )

        return DecodedN64Texture(
            texelData: decodedTexels,
            tlutData: decodedTLUT,
            metadata: TextureAssetMetadata(
                format: format,
                width: width,
                height: height,
                hasTLUT: decodedTLUT != nil
            )
        )
    }
}

private extension N64TextureDecoder {
    func validate(textureByteCount: Int, format: TextureFormat, pixelCount: Int) throws {
        let expectedByteCount: Int
        switch format {
        case .rgba16, .ia16:
            expectedByteCount = pixelCount * 2
        case .ci4, .i4, .ia4:
            expectedByteCount = (pixelCount + 1) / 2
        case .ci8, .i8, .ia8:
            expectedByteCount = pixelCount
        case .rgba32:
            expectedByteCount = pixelCount * 4
        }

        guard textureByteCount == expectedByteCount else {
            throw N64TextureDecoderError.invalidTexelCount(
                format: format,
                expectedByteCount: expectedByteCount,
                actualByteCount: textureByteCount
            )
        }
    }

    func decodeTexels(_ rawTexels: Data, format: TextureFormat, pixelCount: Int) throws -> Data {
        switch format {
        case .rgba16:
            return decodeRGBA16(rawTexels)
        case .ci4:
            return decodeCI4(rawTexels, pixelCount: pixelCount)
        case .ci8:
            return rawTexels
        case .i4:
            return decodeI4(rawTexels, pixelCount: pixelCount)
        case .i8:
            return rawTexels
        case .ia4:
            return decodeIA4(rawTexels, pixelCount: pixelCount)
        case .ia8:
            return decodeIA8(rawTexels)
        case .ia16:
            return rawTexels
        case .rgba32:
            return rawTexels
        }
    }

    func decodeTLUT(
        for format: TextureFormat,
        tlutData: N64TextureDataSource?,
        tlutFormat: TextureFormat?
    ) throws -> Data? {
        guard format == .ci4 || format == .ci8 else {
            guard tlutData == nil else {
                throw N64TextureDecoderError.unexpectedTLUT(format: format)
            }
            return nil
        }

        guard let tlutData else {
            throw N64TextureDecoderError.missingTLUT(format: format)
        }

        let resolvedTLUTFormat = tlutFormat ?? .rgba16
        let rawTLUT = tlutData.bigEndianData()

        guard rawTLUT.count.isMultiple(of: 2) else {
            throw N64TextureDecoderError.invalidTLUTByteCount(actualByteCount: rawTLUT.count)
        }

        switch resolvedTLUTFormat {
        case .rgba16:
            return decodeRGBA16(rawTLUT)
        case .ia16:
            return decodeIA16Palette(rawTLUT)
        default:
            throw N64TextureDecoderError.unsupportedTLUTFormat(resolvedTLUTFormat)
        }
    }

    func decodeRGBA16(_ data: Data) -> Data {
        var decoded = Data()
        decoded.reserveCapacity((data.count / 2) * 4)

        var index = data.startIndex
        while index < data.endIndex {
            let word = UInt16(data[index]) << 8 | UInt16(data[data.index(after: index)])
            let red = expand5BitTo8(UInt8((word >> 11) & 0x1F))
            let green = expand5BitTo8(UInt8((word >> 6) & 0x1F))
            let blue = expand5BitTo8(UInt8((word >> 1) & 0x1F))
            let alpha: UInt8 = (word & 0x01) == 0 ? 0x00 : 0xFF

            decoded.append(contentsOf: [red, green, blue, alpha])
            index = data.index(index, offsetBy: 2)
        }

        return decoded
    }

    func decodeCI4(_ data: Data, pixelCount: Int) -> Data {
        var decoded = Data()
        decoded.reserveCapacity(pixelCount)

        for byte in data {
            decoded.append(byte >> 4)
            if decoded.count == pixelCount {
                break
            }

            decoded.append(byte & 0x0F)
            if decoded.count == pixelCount {
                break
            }
        }

        return decoded
    }

    func decodeI4(_ data: Data, pixelCount: Int) -> Data {
        var decoded = Data()
        decoded.reserveCapacity(pixelCount)

        for byte in data {
            decoded.append(expand4BitTo8(byte >> 4))
            if decoded.count == pixelCount {
                break
            }

            decoded.append(expand4BitTo8(byte & 0x0F))
            if decoded.count == pixelCount {
                break
            }
        }

        return decoded
    }

    func decodeIA4(_ data: Data, pixelCount: Int) -> Data {
        var decoded = Data()
        decoded.reserveCapacity(pixelCount * 2)

        for byte in data {
            appendIA4Pixel(from: byte >> 4, to: &decoded)
            if decoded.count == pixelCount * 2 {
                break
            }

            appendIA4Pixel(from: byte & 0x0F, to: &decoded)
            if decoded.count == pixelCount * 2 {
                break
            }
        }

        return decoded
    }

    func decodeIA8(_ data: Data) -> Data {
        var decoded = Data()
        decoded.reserveCapacity(data.count * 2)

        for byte in data {
            let intensity = expand4BitTo8(byte >> 4)
            let alpha = expand4BitTo8(byte & 0x0F)
            decoded.append(contentsOf: [intensity, alpha])
        }

        return decoded
    }

    func decodeIA16Palette(_ data: Data) -> Data {
        var decoded = Data()
        decoded.reserveCapacity((data.count / 2) * 4)

        var index = data.startIndex
        while index < data.endIndex {
            let intensity = data[index]
            let alpha = data[data.index(after: index)]
            decoded.append(contentsOf: [intensity, intensity, intensity, alpha])
            index = data.index(index, offsetBy: 2)
        }

        return decoded
    }

    func appendIA4Pixel(from nibble: UInt8, to data: inout Data) {
        let intensity = expand3BitTo8((nibble >> 1) & 0x07)
        let alpha: UInt8 = (nibble & 0x01) == 0 ? 0x00 : 0xFF
        data.append(contentsOf: [intensity, alpha])
    }

    func expand5BitTo8(_ value: UInt8) -> UInt8 {
        (value << 3) | (value >> 2)
    }

    func expand4BitTo8(_ value: UInt8) -> UInt8 {
        (value << 4) | value
    }

    func expand3BitTo8(_ value: UInt8) -> UInt8 {
        UInt8((UInt16(value) * 255 + 3) / 7)
    }
}

public enum N64TextureDecoderError: LocalizedError, Equatable {
    case invalidDimensions(width: Int, height: Int)
    case invalidTexelCount(format: TextureFormat, expectedByteCount: Int, actualByteCount: Int)
    case invalidTLUTByteCount(actualByteCount: Int)
    case missingTLUT(format: TextureFormat)
    case unexpectedTLUT(format: TextureFormat)
    case unsupportedTLUTFormat(TextureFormat)

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions(let width, let height):
            return "Texture dimensions must be positive and non-overflowing; received \(width)x\(height)."
        case .invalidTexelCount(let format, let expectedByteCount, let actualByteCount):
            return "Texture format '\(format.rawValue)' expected \(expectedByteCount) source byte(s), found \(actualByteCount)."
        case .invalidTLUTByteCount(let actualByteCount):
            return "TLUT data must contain an even number of source bytes; found \(actualByteCount)."
        case .missingTLUT(let format):
            return "Texture format '\(format.rawValue)' requires TLUT source data."
        case .unexpectedTLUT(let format):
            return "Texture format '\(format.rawValue)' does not use TLUT data."
        case .unsupportedTLUTFormat(let format):
            return "Unsupported TLUT format '\(format.rawValue)'; expected rgba16 or ia16."
        }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { buffer in
            append(contentsOf: buffer)
        }
    }
}
