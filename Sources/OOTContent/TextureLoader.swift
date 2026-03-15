import Foundation
import Metal
import OOTDataModel

public protocol TextureLoader: AnyObject {
    @MainActor
    func loadTexture(at binaryURL: URL) throws -> MTLTexture
}

@MainActor
public final class MetalTextureLoader: TextureLoader {
    private let device: MTLDevice
    private let cacheCapacity: Int
    private let binaryDecoder: TextureBinaryDecoder
    private var cache: [String: CachedTexture]
    private var accessCounter: UInt64

    public init(
        device: MTLDevice,
        cacheCapacity: Int = 256
    ) {
        self.device = device
        self.cacheCapacity = max(0, cacheCapacity)
        self.binaryDecoder = TextureBinaryDecoder()
        self.cache = [:]
        self.accessCounter = 0
    }

    public func loadTexture(at binaryURL: URL) throws -> MTLTexture {
        let cacheKey = binaryURL.standardizedFileURL.path
        let accessIndex = nextAccessIndex()

        if var cachedTexture = cache[cacheKey] {
            cachedTexture.lastAccessIndex = accessIndex
            cache[cacheKey] = cachedTexture
            return cachedTexture.texture
        }

        let metadataURL = try Self.metadataURL(for: binaryURL)
        let metadata = try JSONDecoder().decode(
            TextureAssetMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        let binaryData = try Data(contentsOf: binaryURL)
        let decodedTexture = try binaryDecoder.decodeTextureData(
            binaryData: binaryData,
            metadata: metadata
        )
        let texture = try makeTexture(from: decodedTexture)

        insert(texture: texture, forKey: cacheKey, accessIndex: accessIndex)
        return texture
    }
}

struct TextureBinaryDecoder {
    func decodeTextureData(
        binaryData: Data,
        metadata: TextureAssetMetadata
    ) throws -> DecodedTextureData {
        let pixelCount = try validatedPixelCount(for: metadata)
        try validateTLUTUsage(for: metadata)

        switch metadata.format {
        case .rgba16, .rgba32:
            let expectedByteCount = try byteCount(
                pixelCount: pixelCount,
                bytesPerPixel: 4
            )
            let bytesPerRow = try rowBytes(
                width: metadata.width,
                bytesPerPixel: 4
            )
            try validateBinaryByteCount(
                actual: binaryData.count,
                expected: expectedByteCount,
                format: metadata.format
            )
            return DecodedTextureData(
                pixelFormat: .rgba8Unorm,
                width: metadata.width,
                height: metadata.height,
                bytesPerRow: bytesPerRow,
                pixelData: binaryData
            )
        case .ia4, .ia8, .ia16:
            let expectedByteCount = try byteCount(
                pixelCount: pixelCount,
                bytesPerPixel: 2
            )
            let bytesPerRow = try rowBytes(
                width: metadata.width,
                bytesPerPixel: 2
            )
            try validateBinaryByteCount(
                actual: binaryData.count,
                expected: expectedByteCount,
                format: metadata.format
            )
            return DecodedTextureData(
                pixelFormat: .rg8Unorm,
                width: metadata.width,
                height: metadata.height,
                bytesPerRow: bytesPerRow,
                pixelData: binaryData
            )
        case .i4, .i8:
            let expectedByteCount = try byteCount(
                pixelCount: pixelCount,
                bytesPerPixel: 1
            )
            let bytesPerRow = try rowBytes(
                width: metadata.width,
                bytesPerPixel: 1
            )
            try validateBinaryByteCount(
                actual: binaryData.count,
                expected: expectedByteCount,
                format: metadata.format
            )
            return DecodedTextureData(
                pixelFormat: .r8Unorm,
                width: metadata.width,
                height: metadata.height,
                bytesPerRow: bytesPerRow,
                pixelData: binaryData
            )
        case .ci4, .ci8:
            return try decodeColorIndexedTexture(
                binaryData: binaryData,
                metadata: metadata,
                pixelCount: pixelCount
            )
        }
    }
}

struct DecodedTextureData: Sendable, Equatable {
    let pixelFormat: MTLPixelFormat
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelData: Data
}

public enum TextureLoaderError: LocalizedError, Equatable {
    case invalidTextureBinaryPath(String)
    case invalidDimensions(width: Int, height: Int)
    case invalidBinaryByteCount(format: TextureFormat, expected: Int, actual: Int)
    case missingTLUT(format: TextureFormat)
    case unexpectedTLUT(format: TextureFormat)
    case invalidTLUTByteCount(format: TextureFormat, expected: Int, actual: Int)
    case paletteIndexOutOfRange(index: UInt8, paletteEntryCount: Int)
    case failedTextureCreation(pixelFormat: MTLPixelFormat, width: Int, height: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidTextureBinaryPath(let path):
            return "Texture binary path '\(path)' must end with .tex.bin."
        case .invalidDimensions(let width, let height):
            return "Texture dimensions must be positive and non-overflowing; received \(width)x\(height)."
        case .invalidBinaryByteCount(let format, let expected, let actual):
            return "Texture format '\(format.rawValue)' expected \(expected) byte(s), found \(actual)."
        case .missingTLUT(let format):
            return "Texture format '\(format.rawValue)' requires TLUT data."
        case .unexpectedTLUT(let format):
            return "Texture format '\(format.rawValue)' does not use TLUT data."
        case .invalidTLUTByteCount(let format, let expected, let actual):
            return "Texture format '\(format.rawValue)' expected \(expected) TLUT byte(s), found \(actual)."
        case .paletteIndexOutOfRange(let index, let paletteEntryCount):
            return "Palette index \(index) exceeded the available \(paletteEntryCount) TLUT entries."
        case .failedTextureCreation(let pixelFormat, let width, let height):
            return "Metal failed to create a \(width)x\(height) texture with pixel format \(pixelFormat)."
        }
    }
}

private extension MetalTextureLoader {
    struct CachedTexture {
        let texture: MTLTexture
        var lastAccessIndex: UInt64
    }

    static func metadataURL(for binaryURL: URL) throws -> URL {
        guard binaryURL.pathExtension == "bin",
              binaryURL.deletingPathExtension().pathExtension == "tex" else {
            throw TextureLoaderError.invalidTextureBinaryPath(binaryURL.path)
        }

        return binaryURL.deletingPathExtension().appendingPathExtension("json")
    }

    func makeTexture(from decodedTexture: DecodedTextureData) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: decodedTexture.pixelFormat,
            width: decodedTexture.width,
            height: decodedTexture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureLoaderError.failedTextureCreation(
                pixelFormat: decodedTexture.pixelFormat,
                width: decodedTexture.width,
                height: decodedTexture.height
            )
        }

        decodedTexture.pixelData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            texture.replace(
                region: MTLRegionMake2D(0, 0, decodedTexture.width, decodedTexture.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: decodedTexture.bytesPerRow
            )
        }

        return texture
    }

    func nextAccessIndex() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    func insert(texture: MTLTexture, forKey key: String, accessIndex: UInt64) {
        guard cacheCapacity > 0 else {
            return
        }

        cache[key] = CachedTexture(texture: texture, lastAccessIndex: accessIndex)
        guard cache.count > cacheCapacity else {
            return
        }

        guard let leastRecentlyUsedKey = cache.min(
            by: { $0.value.lastAccessIndex < $1.value.lastAccessIndex }
        )?.key else {
            return
        }

        cache.removeValue(forKey: leastRecentlyUsedKey)
    }
}

private extension TextureBinaryDecoder {
    func decodeColorIndexedTexture(
        binaryData: Data,
        metadata: TextureAssetMetadata,
        pixelCount: Int
    ) throws -> DecodedTextureData {
        guard metadata.hasTLUT else {
            throw TextureLoaderError.missingTLUT(format: metadata.format)
        }

        let texelByteCount = pixelCount
        let tlutByteCount = paletteByteCount(for: metadata.format)
        let expectedByteCount = texelByteCount + tlutByteCount
        try validateBinaryByteCount(
            actual: binaryData.count,
            expected: expectedByteCount,
            format: metadata.format
        )

        let texels = binaryData.prefix(texelByteCount)
        let tlut = binaryData.dropFirst(texelByteCount)
        guard tlut.count == tlutByteCount else {
            throw TextureLoaderError.invalidTLUTByteCount(
                format: metadata.format,
                expected: tlutByteCount,
                actual: tlut.count
            )
        }

        let palette = Array(tlut)
        let paletteEntryCount = palette.count / 4
        var resolvedPixels = Data()
        resolvedPixels.reserveCapacity(pixelCount * 4)

        for index in texels {
            let paletteOffset = Int(index) * 4
            guard paletteOffset + 3 < palette.count else {
                throw TextureLoaderError.paletteIndexOutOfRange(
                    index: index,
                    paletteEntryCount: paletteEntryCount
                )
            }

            resolvedPixels.append(contentsOf: palette[paletteOffset ..< paletteOffset + 4])
        }

        return DecodedTextureData(
            pixelFormat: .rgba8Unorm,
            width: metadata.width,
            height: metadata.height,
            bytesPerRow: try rowBytes(width: metadata.width, bytesPerPixel: 4),
            pixelData: resolvedPixels
        )
    }

    func validatedPixelCount(for metadata: TextureAssetMetadata) throws -> Int {
        guard metadata.width > 0, metadata.height > 0 else {
            throw TextureLoaderError.invalidDimensions(width: metadata.width, height: metadata.height)
        }

        let (pixelCount, overflow) = metadata.width.multipliedReportingOverflow(by: metadata.height)
        guard overflow == false else {
            throw TextureLoaderError.invalidDimensions(width: metadata.width, height: metadata.height)
        }

        return pixelCount
    }

    func validateTLUTUsage(for metadata: TextureAssetMetadata) throws {
        switch metadata.format {
        case .ci4, .ci8:
            return
        case .rgba16, .rgba32, .ia4, .ia8, .ia16, .i4, .i8:
            guard metadata.hasTLUT == false else {
                throw TextureLoaderError.unexpectedTLUT(format: metadata.format)
            }
        }
    }

    func byteCount(pixelCount: Int, bytesPerPixel: Int) throws -> Int {
        let (byteCount, overflow) = pixelCount.multipliedReportingOverflow(by: bytesPerPixel)
        guard overflow == false else {
            throw TextureLoaderError.invalidDimensions(width: pixelCount, height: bytesPerPixel)
        }
        return byteCount
    }

    func rowBytes(width: Int, bytesPerPixel: Int) throws -> Int {
        let (rowBytes, overflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard overflow == false else {
            throw TextureLoaderError.invalidDimensions(width: width, height: bytesPerPixel)
        }
        return rowBytes
    }

    func validateBinaryByteCount(actual: Int, expected: Int, format: TextureFormat) throws {
        guard actual == expected else {
            throw TextureLoaderError.invalidBinaryByteCount(
                format: format,
                expected: expected,
                actual: actual
            )
        }
    }

    func paletteByteCount(for format: TextureFormat) -> Int {
        switch format {
        case .ci4:
            return 16 * 4
        case .ci8:
            return 256 * 4
        default:
            return 0
        }
    }
}
