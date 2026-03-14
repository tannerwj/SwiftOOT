public struct TextureAssetMetadata: Codable, Sendable, Equatable {
    public var format: TextureFormat
    public var width: Int
    public var height: Int
    public var hasTLUT: Bool

    public init(format: TextureFormat, width: Int, height: Int, hasTLUT: Bool) {
        self.format = format
        self.width = width
        self.height = height
        self.hasTLUT = hasTLUT
    }
}
