import simd

public enum ActorAnimationPlaybackMode: String, Sendable, Equatable {
    case loop
    case hold
}

public struct ActorSkeletonRenderState: Sendable {
    public var objectName: String
    public var skeletonName: String
    public var animationName: String?
    public var animationFrame: Float
    public var animationPlaybackMode: ActorAnimationPlaybackMode
    public var modelMatrix: simd_float4x4
    public var useLowDetailDisplayLists: Bool

    public init(
        objectName: String,
        skeletonName: String,
        animationName: String? = nil,
        animationFrame: Float = 0,
        animationPlaybackMode: ActorAnimationPlaybackMode = .loop,
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        useLowDetailDisplayLists: Bool = false
    ) {
        self.objectName = objectName
        self.skeletonName = skeletonName
        self.animationName = animationName
        self.animationFrame = animationFrame
        self.animationPlaybackMode = animationPlaybackMode
        self.modelMatrix = modelMatrix
        self.useLowDetailDisplayLists = useLowDetailDisplayLists
    }
}
