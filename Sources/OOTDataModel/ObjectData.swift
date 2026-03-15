public struct ObjectManifest: Codable, Sendable, Equatable {
    public var name: String
    public var skeletonPath: String?
    public var animations: [ObjectAnimationReference]
    public var meshes: [ObjectMeshAsset]
    public var textures: [TextureDescriptor]

    public init(
        name: String,
        skeletonPath: String? = nil,
        animations: [ObjectAnimationReference] = [],
        meshes: [ObjectMeshAsset] = [],
        textures: [TextureDescriptor] = []
    ) {
        self.name = name
        self.skeletonPath = skeletonPath
        self.animations = animations
        self.meshes = meshes
        self.textures = textures
    }
}

public struct ObjectAnimationReference: Codable, Sendable, Equatable {
    public var name: String
    public var kind: ObjectAnimationKind
    public var path: String

    public init(name: String, kind: ObjectAnimationKind, path: String) {
        self.name = name
        self.kind = kind
        self.path = path
    }
}

public struct ObjectMeshAsset: Codable, Sendable, Equatable {
    public var name: String
    public var displayListPath: String
    public var vertexPaths: [String]

    public init(name: String, displayListPath: String, vertexPaths: [String] = []) {
        self.name = name
        self.displayListPath = displayListPath
        self.vertexPaths = vertexPaths
    }
}

public struct ObjectSkeletonFile: Codable, Sendable, Equatable {
    public var skeletons: [NamedSkeletonData]

    public init(skeletons: [NamedSkeletonData]) {
        self.skeletons = skeletons
    }
}

public struct NamedSkeletonData: Codable, Sendable, Equatable {
    public var name: String
    public var skeleton: SkeletonData

    public init(name: String, skeleton: SkeletonData) {
        self.name = name
        self.skeleton = skeleton
    }
}

public enum ObjectAnimationKind: String, Codable, Sendable, CaseIterable {
    case standard
    case player
}

public struct ObjectAnimationData: Codable, Sendable, Equatable {
    public var name: String
    public var kind: ObjectAnimationKind
    public var frameCount: Int
    public var values: [Int16]
    public var jointIndices: [AnimationJointIndex]
    public var staticIndexMax: Int?
    public var limbCount: Int?

    public init(
        name: String,
        kind: ObjectAnimationKind,
        frameCount: Int,
        values: [Int16],
        jointIndices: [AnimationJointIndex] = [],
        staticIndexMax: Int? = nil,
        limbCount: Int? = nil
    ) {
        self.name = name
        self.kind = kind
        self.frameCount = frameCount
        self.values = values
        self.jointIndices = jointIndices
        self.staticIndexMax = staticIndexMax
        self.limbCount = limbCount
    }
}

public struct AnimationJointIndex: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}
