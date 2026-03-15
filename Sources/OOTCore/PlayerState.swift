import OOTContent
import OOTDataModel
import simd

public struct StickInput: Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = StickInput()

    public var magnitude: Float {
        min(simd_length(vector), 1)
    }

    public var isActive: Bool {
        magnitude > 0.001
    }

    public var normalized: StickInput {
        let length = simd_length(vector)
        guard length > 0.001 else {
            return .zero
        }

        let clamped = min(length, 1)
        let resolved = (vector / length) * clamped
        return StickInput(x: resolved.x, y: resolved.y)
    }

    public var vector: SIMD2<Float> {
        SIMD2<Float>(x, y)
    }
}

public struct ControllerInputState: Sendable, Equatable {
    public var stick: StickInput
    public var aPressed: Bool
    public var bPressed: Bool
    public var zPressed: Bool
    public var startPressed: Bool

    public init(
        stick: StickInput = .zero,
        aPressed: Bool = false,
        bPressed: Bool = false,
        zPressed: Bool = false,
        startPressed: Bool = false
    ) {
        self.stick = stick
        self.aPressed = aPressed
        self.bPressed = bPressed
        self.zPressed = zPressed
        self.startPressed = startPressed
    }
}

public enum PlayerLocomotionState: String, Sendable, Equatable {
    case idle
    case walking
    case running
    case falling
}

public enum PlayerAnimationClip: String, Sendable, Equatable {
    case idle
    case walk
    case run
}

public struct PlayerAnimationState: Sendable, Equatable {
    public var currentClip: PlayerAnimationClip
    public var previousClip: PlayerAnimationClip?
    public var currentFrame: Float
    public var morphWeight: Float

    public init(
        currentClip: PlayerAnimationClip = .idle,
        previousClip: PlayerAnimationClip? = nil,
        currentFrame: Float = 0,
        morphWeight: Float = 0
    ) {
        self.currentClip = currentClip
        self.previousClip = previousClip
        self.currentFrame = currentFrame
        self.morphWeight = morphWeight
    }

    mutating func transition(to clip: PlayerAnimationClip) {
        guard clip != currentClip else {
            return
        }

        previousClip = currentClip
        currentClip = clip
        currentFrame = 0
        morphWeight = 1
    }
}

public struct PlayerState: Sendable, Equatable {
    public var position: Vec3f
    public var velocity: Vec3f
    public var facingRadians: Float
    public var isGrounded: Bool
    public var locomotionState: PlayerLocomotionState
    public var animationState: PlayerAnimationState
    public var floorHeight: Float?

    public init(
        position: Vec3f = Vec3f(x: 0, y: 0, z: 0),
        velocity: Vec3f = Vec3f(x: 0, y: 0, z: 0),
        facingRadians: Float = 0,
        isGrounded: Bool = true,
        locomotionState: PlayerLocomotionState = .idle,
        animationState: PlayerAnimationState = PlayerAnimationState(),
        floorHeight: Float? = nil
    ) {
        self.position = position
        self.velocity = velocity
        self.facingRadians = facingRadians
        self.isGrounded = isGrounded
        self.locomotionState = locomotionState
        self.animationState = animationState
        self.floorHeight = floorHeight
    }
}

public struct PlayerMovementConfiguration: Sendable, Equatable {
    public var walkThreshold: Float
    public var runThreshold: Float
    public var walkSpeed: Float
    public var runSpeed: Float
    public var gravity: Float
    public var floorSnapDistance: Float
    public var maxStepHeight: Float
    public var floorProbeHeight: Float
    public var collisionRadius: Float
    public var animationMorphDecay: Float

    public init(
        walkThreshold: Float = 0.35,
        runThreshold: Float = 0.75,
        walkSpeed: Float = 4,
        runSpeed: Float = 8,
        gravity: Float = 1.5,
        floorSnapDistance: Float = 6,
        maxStepHeight: Float = 10,
        floorProbeHeight: Float = 24,
        collisionRadius: Float = 18,
        animationMorphDecay: Float = 0.18
    ) {
        self.walkThreshold = walkThreshold
        self.runThreshold = runThreshold
        self.walkSpeed = walkSpeed
        self.runSpeed = runSpeed
        self.gravity = gravity
        self.floorSnapDistance = floorSnapDistance
        self.maxStepHeight = maxStepHeight
        self.floorProbeHeight = floorProbeHeight
        self.collisionRadius = collisionRadius
        self.animationMorphDecay = animationMorphDecay
    }
}

extension PlayerState {
    func updating(
        input: ControllerInputState,
        collisionSystem: CollisionSystem?,
        configuration: PlayerMovementConfiguration
    ) -> PlayerState {
        let stick = input.stick.normalized
        let desiredDisplacement = desiredMovement(for: stick, configuration: configuration)

        var nextPosition = position.simd
        var nextVelocity = velocity.simd
        var nextFacingRadians = facingRadians

        if simd_length_squared(desiredDisplacement) > 0.000_1 {
            nextFacingRadians = atan2(desiredDisplacement.x, -desiredDisplacement.z)
        }

        nextPosition = applyWallSlide(
            from: nextPosition,
            displacement: desiredDisplacement,
            collisionSystem: collisionSystem,
            configuration: configuration
        )

        let floorProbe = nextPosition + SIMD3<Float>(0, configuration.floorProbeHeight, 0)
        let snapHit = collisionSystem?.findFloor(at: floorProbe)
        let snapDelta = snapHit.map { $0.floorY - nextPosition.y }

        var isGrounded = false
        var floorHeight: Float?

        if let snapHit, let snapDelta {
            let canSnap = snapDelta <= configuration.maxStepHeight && snapDelta >= -configuration.floorSnapDistance
            if canSnap {
                nextPosition.y = snapHit.floorY
                nextVelocity.y = 0
                isGrounded = true
                floorHeight = snapHit.floorY
            }
        }

        if isGrounded == false {
            nextVelocity.y -= configuration.gravity
            nextPosition.y += nextVelocity.y

            let landingProbe = nextPosition + SIMD3<Float>(0, configuration.floorProbeHeight, 0)
            if let landingHit = collisionSystem?.findFloor(at: landingProbe), nextPosition.y <= landingHit.floorY {
                nextPosition.y = landingHit.floorY
                nextVelocity.y = 0
                isGrounded = true
                floorHeight = landingHit.floorY
            }
        }

        let locomotionState = resolveLocomotionState(
            stickMagnitude: stick.magnitude,
            isGrounded: isGrounded,
            configuration: configuration
        )

        var animationState = animationState
        animationState.transition(to: animationClip(for: locomotionState))
        animationState.currentFrame += animationPlaybackSpeed(for: locomotionState)
        animationState.morphWeight = max(0, animationState.morphWeight - configuration.animationMorphDecay)
        if animationState.morphWeight == 0 {
            animationState.previousClip = nil
        }

        return PlayerState(
            position: Vec3f(nextPosition),
            velocity: Vec3f(nextVelocity),
            facingRadians: nextFacingRadians,
            isGrounded: isGrounded,
            locomotionState: locomotionState,
            animationState: animationState,
            floorHeight: floorHeight
        )
    }

    private func desiredMovement(
        for stick: StickInput,
        configuration: PlayerMovementConfiguration
    ) -> SIMD3<Float> {
        guard stick.isActive else {
            return .zero
        }

        let direction = simd_normalize(SIMD3<Float>(stick.x, 0, -stick.y))
        let magnitude = stick.magnitude

        let speed: Float
        if magnitude >= configuration.runThreshold {
            speed = configuration.runSpeed * magnitude
        } else {
            let scaledWalkMagnitude = max(magnitude / max(configuration.walkThreshold, 0.001), 0.35)
            speed = configuration.walkSpeed * scaledWalkMagnitude
        }

        return direction * speed
    }

    private func applyWallSlide(
        from position: SIMD3<Float>,
        displacement: SIMD3<Float>,
        collisionSystem: CollisionSystem?,
        configuration: PlayerMovementConfiguration
    ) -> SIMD3<Float> {
        guard let collisionSystem, simd_length_squared(displacement) > 0.000_1 else {
            return position + displacement
        }

        guard let wallHit = collisionSystem.checkWall(
            at: position,
            radius: configuration.collisionRadius,
            displacement: displacement
        ) else {
            return position + displacement
        }

        let wallNormal = horizontalNormal(from: wallHit.displacement)
        guard simd_length_squared(wallNormal) > 0.000_1 else {
            return position + displacement + wallHit.displacement
        }

        let slideDisplacement = displacement - (wallNormal * simd_dot(displacement, wallNormal))
        var resolved = position + slideDisplacement

        if let slideHit = collisionSystem.checkWall(
            at: position,
            radius: configuration.collisionRadius,
            displacement: slideDisplacement
        ) {
            resolved += slideHit.displacement
        }

        return resolved
    }

    private func horizontalNormal(from displacement: SIMD3<Float>) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(displacement.x, 0, displacement.z)
        let length = simd_length(horizontal)
        guard length > 0.000_1 else {
            return .zero
        }

        return horizontal / length
    }

    private func resolveLocomotionState(
        stickMagnitude: Float,
        isGrounded: Bool,
        configuration: PlayerMovementConfiguration
    ) -> PlayerLocomotionState {
        guard isGrounded else {
            return .falling
        }

        if stickMagnitude >= configuration.runThreshold {
            return .running
        }
        if stickMagnitude >= configuration.walkThreshold {
            return .walking
        }
        return .idle
    }

    private func animationClip(for locomotionState: PlayerLocomotionState) -> PlayerAnimationClip {
        switch locomotionState {
        case .idle, .falling:
            return .idle
        case .walking:
            return .walk
        case .running:
            return .run
        }
    }

    private func animationPlaybackSpeed(for locomotionState: PlayerLocomotionState) -> Float {
        switch locomotionState {
        case .idle:
            return 0.6
        case .walking:
            return 1.0
        case .running:
            return 1.6
        case .falling:
            return 0.4
        }
    }
}

extension Vec3f {
    init(_ vector: SIMD3<Float>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }

    var simd: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
