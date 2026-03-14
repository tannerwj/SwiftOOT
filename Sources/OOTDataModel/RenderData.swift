public struct Vector2s: Codable, Sendable, Equatable {
    public var x: Int16
    public var y: Int16

    public init(x: Int16, y: Int16) {
        self.x = x
        self.y = y
    }
}

public struct Vector3s: Codable, Sendable, Equatable {
    public var x: Int16
    public var y: Int16
    public var z: Int16

    public init(x: Int16, y: Int16, z: Int16) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct RGBA8: Codable, Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct N64Vertex: Codable, Sendable, Equatable {
    public var position: Vector3s
    public var flag: UInt16
    public var textureCoordinate: Vector2s
    public var colorOrNormal: RGBA8

    public init(
        position: Vector3s,
        flag: UInt16,
        textureCoordinate: Vector2s,
        colorOrNormal: RGBA8
    ) {
        self.position = position
        self.flag = flag
        self.textureCoordinate = textureCoordinate
        self.colorOrNormal = colorOrNormal
    }
}

public struct MeshData: Codable, Sendable, Equatable {
    public var vertices: [N64Vertex]
    public var indices: [UInt16]

    public init(vertices: [N64Vertex], indices: [UInt16]) {
        self.vertices = vertices
        self.indices = indices
    }
}

public enum TextureFormat: String, Codable, Sendable, CaseIterable {
    case rgba16
    case ci4
    case ci8
    case i4
    case i8
    case ia4
    case ia8
    case ia16
    case rgba32
}

public enum TexelSize: UInt8, Codable, Sendable, CaseIterable {
    case bits4 = 4
    case bits8 = 8
    case bits16 = 16
    case bits32 = 32
}

public struct TextureDescriptor: Codable, Sendable, Equatable {
    public var format: TextureFormat
    public var width: Int
    public var height: Int
    public var path: String

    public init(format: TextureFormat, width: Int, height: Int, path: String) {
        self.format = format
        self.width = width
        self.height = height
        self.path = path
    }
}
