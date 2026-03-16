import Foundation
import simd

public struct ColliderCollisionMask: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let at = ColliderCollisionMask(rawValue: 1 << 0)
    public static let ac = ColliderCollisionMask(rawValue: 1 << 1)
    public static let oc = ColliderCollisionMask(rawValue: 1 << 2)
}

public struct ColliderInit: Sendable, Equatable {
    public var collisionMask: ColliderCollisionMask

    public init(collisionMask: ColliderCollisionMask) {
        self.collisionMask = collisionMask
    }
}

public struct ColliderCylinder: Sendable, Equatable {
    public var center: Vec3f
    public var radius: Float
    public var height: Float

    public init(
        center: Vec3f,
        radius: Float,
        height: Float
    ) {
        self.center = center
        self.radius = max(0, radius)
        self.height = max(0, height)
    }

    var minimumY: Float {
        center.y
    }

    var maximumY: Float {
        center.y + height
    }

    var midpoint: SIMD3<Float> {
        center.simd + SIMD3<Float>(0, height * 0.5, 0)
    }
}

public struct ColliderTri: Sendable, Equatable {
    public var a: Vec3f
    public var b: Vec3f
    public var c: Vec3f

    public init(
        a: Vec3f,
        b: Vec3f,
        c: Vec3f
    ) {
        self.a = a
        self.b = b
        self.c = c
    }
}

public struct ColliderTris: Sendable, Equatable {
    public var triangles: [ColliderTri]

    public init(triangles: [ColliderTri]) {
        self.triangles = triangles
    }
}

public enum CombatColliderShape: Sendable, Equatable {
    case cylinder(ColliderCylinder)
    case tris(ColliderTris)
}

public struct CombatCollider: Sendable, Equatable {
    public var initialization: ColliderInit
    public var shape: CombatColliderShape

    public init(
        initialization: ColliderInit,
        shape: CombatColliderShape
    ) {
        self.initialization = initialization
        self.shape = shape
    }
}

public enum DamageElement: String, Sendable, Codable, Equatable, Hashable {
    case swordSlash
    case swordJump
    case swordSpin
    case melee
    case projectile
    case boomerang
    case explosion
    case flash
}

public struct DamageEffect: Sendable, Codable, Equatable {
    public var damage: Int
    public var knockbackDistance: Float
    public var invincibilityFrames: Int

    public init(
        damage: Int,
        knockbackDistance: Float,
        invincibilityFrames: Int = 12
    ) {
        self.damage = max(0, damage)
        self.knockbackDistance = max(0, knockbackDistance)
        self.invincibilityFrames = max(0, invincibilityFrames)
    }
}

public struct DamageTable: Sendable, Codable, Equatable {
    public var defaultEffect: DamageEffect
    public var overrides: [DamageElement: DamageEffect]

    public init(
        defaultEffect: DamageEffect = DamageEffect(damage: 1, knockbackDistance: 14),
        overrides: [DamageElement: DamageEffect] = [:]
    ) {
        self.defaultEffect = defaultEffect
        self.overrides = overrides
    }

    public func effect(for element: DamageElement) -> DamageEffect {
        if let override = overrides[element] {
            return override
        }

        switch element {
        case .boomerang, .flash:
            return DamageEffect(damage: 0, knockbackDistance: 0, invincibilityFrames: 0)
        case .explosion:
            return DamageEffect(
                damage: max(defaultEffect.damage, 2),
                knockbackDistance: max(defaultEffect.knockbackDistance, 24),
                invincibilityFrames: max(defaultEffect.invincibilityFrames, 10)
            )
        case .swordSlash, .swordJump, .swordSpin, .melee, .projectile:
            return defaultEffect
        }
    }
}

public struct ActorCombatProfile: Sendable, Codable, Equatable {
    public var hurtboxRadius: Float
    public var hurtboxHeight: Float
    public var targetAnchorHeight: Float
    public var targetingRange: Float
    public var damageTable: DamageTable
    public var blocksProjectiles: Bool
    public var deflectsMeleeAttacks: Bool

    public init(
        hurtboxRadius: Float = 18,
        hurtboxHeight: Float = 44,
        targetAnchorHeight: Float = 44,
        targetingRange: Float = 280,
        damageTable: DamageTable = DamageTable(),
        blocksProjectiles: Bool = false,
        deflectsMeleeAttacks: Bool = false
    ) {
        self.hurtboxRadius = max(0, hurtboxRadius)
        self.hurtboxHeight = max(0, hurtboxHeight)
        self.targetAnchorHeight = max(0, targetAnchorHeight)
        self.targetingRange = max(0, targetingRange)
        self.damageTable = damageTable
        self.blocksProjectiles = blocksProjectiles
        self.deflectsMeleeAttacks = deflectsMeleeAttacks
    }
}

public struct ActorCombatState: Sendable, Equatable {
    public var invincibilityFramesRemaining: Int
    public var knockbackVelocity: Vec3f
    public var knockbackFramesRemaining: Int
    public var lastReceivedElement: DamageElement?
    public var lastReceivedDamage: Int
    public var lastBlockedElement: DamageElement?

    public init(
        invincibilityFramesRemaining: Int = 0,
        knockbackVelocity: Vec3f = Vec3f(x: 0, y: 0, z: 0),
        knockbackFramesRemaining: Int = 0,
        lastReceivedElement: DamageElement? = nil,
        lastReceivedDamage: Int = 0,
        lastBlockedElement: DamageElement? = nil
    ) {
        self.invincibilityFramesRemaining = max(0, invincibilityFramesRemaining)
        self.knockbackVelocity = knockbackVelocity
        self.knockbackFramesRemaining = max(0, knockbackFramesRemaining)
        self.lastReceivedElement = lastReceivedElement
        self.lastReceivedDamage = max(0, lastReceivedDamage)
        self.lastBlockedElement = lastBlockedElement
    }
}

public struct CombatHit: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case player
        case actor(profileID: Int, actorType: String)
    }

    public var source: Source
    public var element: DamageElement
    public var direction: Vec3f
    public var effect: DamageEffect
    public var wasBlocked: Bool

    public init(
        source: Source,
        element: DamageElement,
        direction: Vec3f,
        effect: DamageEffect,
        wasBlocked: Bool = false
    ) {
        self.source = source
        self.element = element
        self.direction = direction
        self.effect = effect
        self.wasBlocked = wasBlocked
    }
}

public struct CombatTargetSnapshot: Sendable, Equatable {
    public var actorID: Int
    public var actorType: String
    public var position: Vec3f
    public var anchorHeight: Float
    public var distance: Float

    public init(
        actorID: Int,
        actorType: String,
        position: Vec3f,
        anchorHeight: Float,
        distance: Float
    ) {
        self.actorID = actorID
        self.actorType = actorType
        self.position = position
        self.anchorHeight = anchorHeight
        self.distance = max(0, distance)
    }

    public var focusPoint: Vec3f {
        Vec3f(position.simd + SIMD3<Float>(0, anchorHeight, 0))
    }
}

public enum PlayerAttackKind: String, Sendable, Codable, Equatable {
    case slash
    case jump
    case spin
}

public struct PlayerAttackSnapshot: Sendable, Equatable {
    public var kind: PlayerAttackKind
    public var frame: Int
    public var totalFrames: Int
    public var activeFrameRange: ClosedRange<Int>
    public var isActive: Bool

    public init(
        kind: PlayerAttackKind,
        frame: Int,
        totalFrames: Int,
        activeFrameRange: ClosedRange<Int>,
        isActive: Bool
    ) {
        self.kind = kind
        self.frame = max(0, frame)
        self.totalFrames = max(0, totalFrames)
        self.activeFrameRange = activeFrameRange
        self.isActive = isActive
    }
}

public struct GameplayCombatState: Sendable, Equatable {
    public var lockOnTarget: CombatTargetSnapshot?
    public var activeAttack: PlayerAttackSnapshot?
    public var shieldRaised: Bool
    public var playerInvincibilityFramesRemaining: Int

    public init(
        lockOnTarget: CombatTargetSnapshot? = nil,
        activeAttack: PlayerAttackSnapshot? = nil,
        shieldRaised: Bool = false,
        playerInvincibilityFramesRemaining: Int = 0
    ) {
        self.lockOnTarget = lockOnTarget
        self.activeAttack = activeAttack
        self.shieldRaised = shieldRaised
        self.playerInvincibilityFramesRemaining = max(0, playerInvincibilityFramesRemaining)
    }
}

public struct CombatAttackDefinition: Sendable, Equatable {
    public var collider: CombatCollider
    public var element: DamageElement
    public var effect: DamageEffect
    public var isProjectile: Bool

    public init(
        collider: CombatCollider,
        element: DamageElement,
        effect: DamageEffect,
        isProjectile: Bool = false
    ) {
        self.collider = collider
        self.element = element
        self.effect = effect
        self.isProjectile = isProjectile
    }
}

public enum CombatHitResolution: Sendable, Equatable {
    case ignore
    case block
    case apply(DamageEffect)
}

@MainActor
public protocol TargetableActor: Actor {
    var targetingRange: Float { get }
    var targetAnchorHeight: Float { get }
    var isTargetable: Bool { get }
}

public extension TargetableActor {
    var targetingRange: Float { 280 }
    var targetAnchorHeight: Float { 44 }
    var isTargetable: Bool { true }
}

@MainActor
public protocol CombatActor: DamageableActor, TargetableActor {
    var combatProfile: ActorCombatProfile { get }
    var combatState: ActorCombatState { get set }
    var activeAttacks: [CombatAttackDefinition] { get }

    func combatHitResolution(
        for hit: CombatHit,
        attackerPosition: Vec3f?,
        playState: PlayState
    ) -> CombatHitResolution
    func combatDidReceiveHit(_ hit: CombatHit, playState: PlayState)
    func combatDidBlockHit(_ hit: CombatHit, playState: PlayState)
}

public extension CombatActor {
    var targetAnchorHeight: Float { combatProfile.targetAnchorHeight }
    var targetingRange: Float { combatProfile.targetingRange }
    var isTargetable: Bool { hitPoints > 0 }
    var activeAttacks: [CombatAttackDefinition] { [] }

    var hurtbox: ColliderCylinder {
        ColliderCylinder(
            center: position,
            radius: combatProfile.hurtboxRadius,
            height: combatProfile.hurtboxHeight
        )
    }

    func combatHitResolution(
        for hit: CombatHit,
        attackerPosition _: Vec3f?,
        playState _: PlayState
    ) -> CombatHitResolution {
        if hit.element.canBeBlockedAsProjectile, combatProfile.blocksProjectiles {
            return .block
        }

        if hit.element.isMelee, combatProfile.deflectsMeleeAttacks {
            return .block
        }

        let effect = combatProfile.damageTable.effect(for: hit.element)
        guard effect.damage > 0 else {
            return .ignore
        }

        return .apply(effect)
    }

    func combatDidReceiveHit(_ hit: CombatHit, playState: PlayState) {}

    func combatDidBlockHit(_ hit: CombatHit, playState: PlayState) {}
}

public extension CombatColliderShape {
    var approximateCylinder: ColliderCylinder {
        switch self {
        case .cylinder(let cylinder):
            return cylinder
        case .tris(let tris):
            let vertices = tris.triangles.flatMap { triangle in
                [triangle.a.simd, triangle.b.simd, triangle.c.simd]
            }

            guard let first = vertices.first else {
                return ColliderCylinder(center: Vec3f(x: 0, y: 0, z: 0), radius: 0, height: 0)
            }

            var minimum = first
            var maximum = first
            for vertex in vertices.dropFirst() {
                minimum = simd_min(minimum, vertex)
                maximum = simd_max(maximum, vertex)
            }

            let center = SIMD3<Float>(
                (minimum.x + maximum.x) * 0.5,
                minimum.y,
                (minimum.z + maximum.z) * 0.5
            )
            let radius = vertices.reduce(Float.zero) { partialResult, vertex in
                max(partialResult, simd_distance(SIMD2<Float>(vertex.x, vertex.z), SIMD2<Float>(center.x, center.z)))
            }

            return ColliderCylinder(
                center: Vec3f(center),
                radius: radius,
                height: maximum.y - minimum.y
            )
        }
    }
}

public enum CombatCollisionResolver {
    public static func intersects(
        _ lhs: CombatColliderShape,
        with rhs: ColliderCylinder
    ) -> Bool {
        intersects(lhs.approximateCylinder, with: rhs)
    }

    public static func intersects(
        _ lhs: ColliderCylinder,
        with rhs: ColliderCylinder
    ) -> Bool {
        let horizontalDistanceSquared = simd_distance_squared(
            SIMD2<Float>(lhs.center.x, lhs.center.z),
            SIMD2<Float>(rhs.center.x, rhs.center.z)
        )
        let combinedRadius = lhs.radius + rhs.radius
        guard horizontalDistanceSquared <= combinedRadius * combinedRadius else {
            return false
        }

        return lhs.minimumY <= rhs.maximumY && rhs.minimumY <= lhs.maximumY
    }
}

extension DamageElement {
    var isMelee: Bool {
        switch self {
        case .swordSlash, .swordJump, .swordSpin, .melee:
            return true
        case .projectile, .boomerang, .explosion, .flash:
            return false
        }
    }

    var canBeBlockedAsProjectile: Bool {
        switch self {
        case .projectile, .boomerang:
            return true
        case .swordSlash, .swordJump, .swordSpin, .melee, .explosion, .flash:
            return false
        }
    }

    var isProjectileLike: Bool {
        switch self {
        case .projectile, .boomerang:
            return true
        case .swordSlash, .swordJump, .swordSpin, .melee, .explosion, .flash:
            return false
        }
    }
}
