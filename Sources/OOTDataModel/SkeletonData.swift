public struct SkeletonData: Codable, Sendable, Equatable {
    public var type: SkeletonType
    public var limbs: [LimbData]

    public init(type: SkeletonType, limbs: [LimbData]) {
        self.type = type
        self.limbs = limbs
    }
}

public enum SkeletonType: String, Codable, Sendable, CaseIterable {
    case normal
    case flex
    case curve
}

public struct LimbData: Codable, Sendable, Equatable {
    public var translation: Vector3s
    public var childIndex: Int?
    public var siblingIndex: Int?
    public var displayListPath: String?
    public var lowDetailDisplayListPath: String?

    public init(
        translation: Vector3s,
        childIndex: Int? = nil,
        siblingIndex: Int? = nil,
        displayListPath: String? = nil,
        lowDetailDisplayListPath: String? = nil
    ) {
        self.translation = translation
        self.childIndex = childIndex
        self.siblingIndex = siblingIndex
        self.displayListPath = displayListPath
        self.lowDetailDisplayListPath = lowDetailDisplayListPath
    }
}

public struct AnimationData: Codable, Sendable, Equatable {
    public var frameCount: Int
    public var jointTracks: [JointAnimationTrack]

    public init(frameCount: Int, jointTracks: [JointAnimationTrack]) {
        self.frameCount = frameCount
        self.jointTracks = jointTracks
    }
}

public struct JointAnimationTrack: Codable, Sendable, Equatable {
    public var translations: [Vector3s]
    public var rotations: [Vector3s]

    public init(translations: [Vector3s], rotations: [Vector3s]) {
        self.translations = translations
        self.rotations = rotations
    }
}
