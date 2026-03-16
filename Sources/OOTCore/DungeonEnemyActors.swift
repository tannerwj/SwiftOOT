import Foundation
import OOTContent
import OOTDataModel
import simd

@MainActor
public final class DekuBabaActor: CombatantBaseActor, SkeletonRenderableActor {
    enum State: String {
        case dormant
        case lunging
        case stunned
        case dead
    }

    private enum Constants {
        static let triggerRange: Float = 150
        static let lungeRange: Float = 180
        static let lungeDuration = 36
        static let stunDuration = 54
        static let deathDuration = 18
        static let scale: Float = 0.0125
    }

    private(set) var state: State = .dormant
    private(set) var animationFrame: Float = 0

    private let homePosition: Vec3f
    private let idleCombatProfile = ActorCombatProfile(
        hurtboxRadius: 22,
        hurtboxHeight: 68,
        targetAnchorHeight: 78,
        targetingRange: 220,
        damageTable: DamageTable(defaultEffect: DamageEffect(damage: 0, knockbackDistance: 0))
    )
    private let stunnedCombatProfile = ActorCombatProfile(
        hurtboxRadius: 22,
        hurtboxHeight: 68,
        targetAnchorHeight: 78,
        targetingRange: 220,
        damageTable: DamageTable(
            defaultEffect: DamageEffect(damage: 1, knockbackDistance: 12, invincibilityFrames: 10),
            overrides: [
                .swordJump: DamageEffect(damage: 2, knockbackDistance: 20, invincibilityFrames: 12),
                .swordSpin: DamageEffect(damage: 2, knockbackDistance: 16, invincibilityFrames: 12),
                .projectile: DamageEffect(damage: 1, knockbackDistance: 10, invincibilityFrames: 8),
            ]
        )
    )

    private var stateTimer = 0
    private var grantedReward = false
    private var killingElement: DamageElement?

    public init(spawnRecord: ActorSpawnRecord) {
        homePosition = Vec3f(spawnRecord.spawn.position)
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 2,
            combatProfile: idleCombatProfile
        )
    }

    public override var isTargetable: Bool {
        state != .dead
    }

    public override var activeAttacks: [CombatAttackDefinition] {
        guard state == .lunging, stateTimer >= 10, stateTimer <= 24 else {
            return []
        }

        let forward = facingVector
        let center = position.simd + (forward * 34)
        return [
            CombatAttackDefinition(
                collider: CombatCollider(
                    initialization: ColliderInit(collisionMask: [.at]),
                    shape: .cylinder(
                        ColliderCylinder(
                            center: Vec3f(center),
                            radius: 20,
                            height: 54
                        )
                    )
                ),
                element: .melee,
                effect: DamageEffect(damage: 1, knockbackDistance: 10, invincibilityFrames: 12)
            )
        ]
    }

    public var skeletonRenderState: ActorSkeletonRenderState? {
        ActorSkeletonRenderState(
            objectName: "object_dekubaba",
            skeletonName: "gDekuBabaSkel",
            animationName: state == .lunging || state == .dead ? "gDekuBabaPauseChompAnim" : "gDekuBabaFastChompAnim",
            animationFrame: animationFrame,
            animationPlaybackMode: state == .dead ? .hold : .loop,
            modelMatrix: makeActorModelMatrix(
                position: position,
                yawRadians: renderYawRadians,
                scale: SIMD3<Float>(repeating: Constants.scale)
            )
        )
    }

    public override func update(playState: PlayState) {
        animationFrame += 1

        switch state {
        case .dormant:
            position = homePosition
            combatProfile = idleCombatProfile
            if distanceToPlayer(in: playState) <= Constants.triggerRange {
                state = .lunging
                stateTimer = 0
            }
        case .lunging:
            combatProfile = idleCombatProfile
            stateTimer += 1
            facePlayer(playState: playState)
            if stateTimer >= Constants.lungeDuration || distanceToPlayer(in: playState) > Constants.lungeRange {
                state = .dormant
                stateTimer = 0
            }
        case .stunned:
            combatProfile = stunnedCombatProfile
            stateTimer += 1
            if stateTimer >= Constants.stunDuration {
                state = .dormant
                stateTimer = 0
                combatProfile = idleCombatProfile
            }
        case .dead:
            combatProfile = idleCombatProfile
            stateTimer += 1
            if grantedReward == false {
                grantReward(playState: playState)
            }
            if stateTimer >= Constants.deathDuration {
                playState.requestDestroy(self)
            }
        }
    }

    public func combatHitResolution(
        for hit: CombatHit,
        attackerPosition _: Vec3f?,
        playState _: PlayState
    ) -> CombatHitResolution {
        guard state != .dead else {
            return .ignore
        }

        if state == .stunned {
            let effect = stunnedCombatProfile.damageTable.effect(for: hit.element)
            return effect.damage > 0 ? .apply(effect) : .ignore
        }

        if hit.element == .projectile || hit.element.isMelee {
            enterStunned()
        }
        return .ignore
    }

    public override func combatDidReceiveHit(_ hit: CombatHit, playState _: PlayState) {
        if hitPoints == 0 {
            state = .dead
            stateTimer = 0
            hitPoints = 1
            killingElement = hit.element
        }
    }

    private func enterStunned() {
        state = .stunned
        stateTimer = 0
        combatProfile = stunnedCombatProfile
    }

    private func grantReward(playState: PlayState) {
        grantedReward = true
        let reward: ActorReward
        if killingElement == .projectile {
            reward = .chest(.dekuNuts(5))
        } else {
            reward = .chest(.dekuSticks(1))
        }
        playState.requestReward(reward)
    }

    private func facePlayer(playState: PlayState) {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return
        }

        rotation.y = radiansToRawYaw(yawRadians(from: position.simd, to: playerPosition))
    }

    private func distanceToPlayer(in playState: PlayState) -> Float {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return .greatestFiniteMagnitude
        }

        return simd_distance(playerPosition, position.simd)
    }

    private var facingVector: SIMD3<Float> {
        let yaw = renderYawRadians
        return SIMD3<Float>(sin(yaw), 0, -cos(yaw))
    }

    private var renderYawRadians: Float {
        rawRotationToRadians(Float(rotation.y))
    }
}

@MainActor
public final class SkulltulaActor: CombatantBaseActor, SkeletonRenderableActor {
    enum State: String {
        case hanging
        case dropping
        case grounded
        case dead
    }

    private enum Constants {
        static let triggerRange: Float = 170
        static let scale: Float = 0.02
        static let deathDuration = 24
    }

    private(set) var state: State = .hanging
    private(set) var animationFrame: Float = 0
    private(set) var isGoldVariant: Bool

    private let ceilingPosition: Vec3f
    private var groundY: Float?
    private var verticalVelocity: Float = 0
    private var stateTimer = 0
    private var grantedReward = false

    public init(spawnRecord: ActorSpawnRecord) {
        ceilingPosition = Vec3f(spawnRecord.spawn.position)
        isGoldVariant = ((UInt16(bitPattern: spawnRecord.spawn.params) >> 13) & 0x7) > 0
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 2,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 24,
                hurtboxHeight: 40,
                targetAnchorHeight: 42,
                targetingRange: 250,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 1, knockbackDistance: 12, invincibilityFrames: 10),
                    overrides: [
                        .swordJump: DamageEffect(damage: 2, knockbackDistance: 18, invincibilityFrames: 12),
                        .swordSpin: DamageEffect(damage: 2, knockbackDistance: 16, invincibilityFrames: 12),
                    ]
                )
            )
        )
    }

    public override func initialize(playState: PlayState) {
        groundY = resolveGroundY(near: ceilingPosition, in: playState.scene) ?? (ceilingPosition.y - 90)
    }

    public override var isTargetable: Bool {
        state != .dead
    }

    public override var activeAttacks: [CombatAttackDefinition] {
        guard state == .grounded, distanceToPlayer(in: currentPlayState) <= 46 else {
            return []
        }

        return [
            CombatAttackDefinition(
                collider: CombatCollider(
                    initialization: ColliderInit(collisionMask: [.at]),
                    shape: .cylinder(
                        ColliderCylinder(
                            center: position,
                            radius: 26,
                            height: 36
                        )
                    )
                ),
                element: .melee,
                effect: DamageEffect(damage: 1, knockbackDistance: 10, invincibilityFrames: 12)
            )
        ]
    }

    public var skeletonRenderState: ActorSkeletonRenderState? {
        let animationName: String
        switch state {
        case .hanging:
            animationName = "object_st_Anim_000304"
        case .dropping, .grounded:
            animationName = "object_st_Anim_0055A8"
        case .dead:
            animationName = "object_st_Anim_005B98"
        }

        return ActorSkeletonRenderState(
            objectName: "object_st",
            skeletonName: "object_st_Skel_005298",
            animationName: animationName,
            animationFrame: animationFrame,
            animationPlaybackMode: state == .dead ? .hold : .loop,
            modelMatrix: makeActorModelMatrix(
                position: position,
                yawRadians: rawRotationToRadians(Float(rotation.y)),
                scale: SIMD3<Float>(repeating: Constants.scale)
            )
        )
    }

    public override func update(playState: PlayState) {
        currentPlayState = playState
        animationFrame += 1

        switch state {
        case .hanging:
            position = ceilingPosition
            if distanceToPlayer(in: playState) <= Constants.triggerRange {
                state = .dropping
                stateTimer = 0
                verticalVelocity = 0
            }
        case .dropping:
            verticalVelocity -= 1.4
            position.y = max((groundY ?? ceilingPosition.y), position.y + verticalVelocity)
            if position.y <= (groundY ?? position.y) + 0.5 {
                position.y = groundY ?? position.y
                state = .grounded
                stateTimer = 0
            }
        case .grounded:
            stateTimer += 1
            facePlayer(playState: playState)
        case .dead:
            stateTimer += 1
            if isGoldVariant, grantedReward == false {
                grantedReward = true
                playState.requestReward(.goldSkulltulaToken)
            }
            if stateTimer >= Constants.deathDuration {
                playState.requestDestroy(self)
            }
        }
    }

    public func combatHitResolution(
        for hit: CombatHit,
        attackerPosition: Vec3f?,
        playState: PlayState
    ) -> CombatHitResolution {
        guard state != .dead else {
            return .ignore
        }

        if hit.element.isMelee, hitComesFromFront(attackerPosition: attackerPosition) {
            return .block
        }

        return super.combatHitResolution(
            for: hit,
            attackerPosition: attackerPosition,
            playState: playState
        )
    }

    public override func combatDidReceiveHit(_ hit: CombatHit, playState _: PlayState) {
        if hitPoints == 0 {
            state = .dead
            stateTimer = 0
            hitPoints = 1
        }
    }

    private var currentPlayState: PlayState?

    private func hitComesFromFront(attackerPosition: Vec3f?) -> Bool {
        guard let attackerPosition else {
            return false
        }

        let forward = SIMD2<Float>(
            sin(rawRotationToRadians(Float(rotation.y))),
            -cos(rawRotationToRadians(Float(rotation.y)))
        )
        let toAttacker = normalizePlanar(attackerPosition.simd - position.simd)
        return simd_dot(forward, toAttacker) > 0.1
    }

    private func facePlayer(playState: PlayState) {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return
        }

        rotation.y = radiansToRawYaw(yawRadians(from: position.simd, to: playerPosition))
    }

    private func distanceToPlayer(in playState: PlayState?) -> Float {
        guard
            let playState,
            let playerPosition = playStatePlayerPosition(playState)
        else {
            return .greatestFiniteMagnitude
        }

        return simd_distance(playerPosition, position.simd)
    }
}

@MainActor
public final class GohmaLarvaActor: CombatantBaseActor, SkeletonRenderableActor {
    enum State: String {
        case standing
        case chasing
        case stunned
        case dead
    }

    private enum Constants {
        static let scale: Float = 0.01
        static let stunDuration = 40
        static let deathDuration = 20
        static let moveSpeed: Float = 1.4
    }

    private(set) var state: State = .standing
    private(set) var animationFrame: Float = 0

    private var groundY: Float
    private var stateTimer = 0

    private static let syntheticProfile = ActorProfile(
        id: 90_001,
        category: ActorCategory.enemy.rawValue,
        flags: 0,
        objectID: 0
    )

    public init(spawnRecord: ActorSpawnRecord) {
        groundY = Float(spawnRecord.spawn.position.y)
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 2,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 14,
                hurtboxHeight: 20,
                targetAnchorHeight: 18,
                targetingRange: 180,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 1, knockbackDistance: 10, invincibilityFrames: 8),
                    overrides: [
                        .swordJump: DamageEffect(damage: 2, knockbackDistance: 14, invincibilityFrames: 10),
                        .swordSpin: DamageEffect(damage: 2, knockbackDistance: 12, invincibilityFrames: 10),
                    ]
                )
            )
        )
    }

    init(position: Vec3f, roomID _: Int) {
        groundY = position.y
        super.init(
            profile: Self.syntheticProfile,
            category: .enemy,
            position: position,
            hitPoints: 2,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 14,
                hurtboxHeight: 20,
                targetAnchorHeight: 18,
                targetingRange: 180,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 1, knockbackDistance: 10, invincibilityFrames: 8)
                )
            )
        )
    }

    public override func initialize(playState: PlayState) {
        groundY = resolveGroundY(near: position, in: playState.scene) ?? groundY
    }

    public override var isTargetable: Bool {
        state != .dead
    }

    public override var activeAttacks: [CombatAttackDefinition] {
        guard state == .chasing else {
            return []
        }

        return [
            CombatAttackDefinition(
                collider: CombatCollider(
                    initialization: ColliderInit(collisionMask: [.at]),
                    shape: .cylinder(
                        ColliderCylinder(
                            center: position,
                            radius: 16,
                            height: 18
                        )
                    )
                ),
                element: .melee,
                effect: DamageEffect(damage: 1, knockbackDistance: 8, invincibilityFrames: 10)
            )
        ]
    }

    public var skeletonRenderState: ActorSkeletonRenderState? {
        let animationName: String
        switch state {
        case .standing:
            animationName = "gObjectGolStandAnim"
        case .chasing:
            animationName = "gObjectGolRunningAnim"
        case .stunned:
            animationName = "gObjectGolDamagedAnim"
        case .dead:
            animationName = "gObjectGolDeathAnim"
        }

        return ActorSkeletonRenderState(
            objectName: "object_gol",
            skeletonName: "gObjectGolSkel",
            animationName: animationName,
            animationFrame: animationFrame,
            animationPlaybackMode: state == .dead ? .hold : .loop,
            modelMatrix: makeActorModelMatrix(
                position: position,
                yawRadians: rawRotationToRadians(Float(rotation.y)),
                scale: SIMD3<Float>(repeating: Constants.scale)
            )
        )
    }

    public override func update(playState: PlayState) {
        animationFrame += 1
        position.y = groundY

        switch state {
        case .standing:
            stateTimer += 1
            if stateTimer >= 10 {
                state = .chasing
                stateTimer = 0
            }
        case .chasing:
            chasePlayer(playState: playState)
        case .stunned:
            stateTimer += 1
            if stateTimer >= Constants.stunDuration {
                state = .chasing
                stateTimer = 0
            }
        case .dead:
            stateTimer += 1
            if stateTimer >= Constants.deathDuration {
                playState.requestDestroy(self)
            }
        }
    }

    public func combatHitResolution(
        for hit: CombatHit,
        attackerPosition: Vec3f?,
        playState: PlayState
    ) -> CombatHitResolution {
        guard state != .dead else {
            return .ignore
        }

        if hit.element == .projectile {
            state = .stunned
            stateTimer = 0
            return .ignore
        }

        return super.combatHitResolution(
            for: hit,
            attackerPosition: attackerPosition,
            playState: playState
        )
    }

    public override func combatDidReceiveHit(_ hit: CombatHit, playState _: PlayState) {
        if hitPoints == 0 {
            state = .dead
            stateTimer = 0
            hitPoints = 1
        }
    }

    private func chasePlayer(playState: PlayState) {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return
        }

        let direction = normalizedDirection(
            from: position.simd,
            to: playerPosition,
            fallbackYaw: rawRotationToRadians(Float(rotation.y))
        )
        position = Vec3f(position.simd + (direction * Constants.moveSpeed))
        rotation.y = radiansToRawYaw(yawRadians(from: position.simd, to: playerPosition))
    }
}

@MainActor
public final class QueenGohmaActor: CombatantBaseActor, SkeletonRenderableActor {
    enum State: String {
        case ceilingIdle
        case ceilingPrepareSpawn
        case ceilingSpawnLarva
        case falling
        case floorStunned
        case floorPatrol
        case floorPrepareAttack
        case floorAttack
        case dead
    }

    private enum Constants {
        static let scale: Float = 0.01
        static let ceilingIdleDuration = 40
        static let ceilingPrepareDuration = 30
        static let spawnDuration = 45
        static let floorStunDuration = 60
        static let patrolDuration = 75
        static let prepareAttackDuration = 24
        static let attackDuration = 18
        static let deathDuration = 90
        static let moveSpeed: Float = 1.6
    }

    private(set) var state: State = .ceilingIdle
    private(set) var animationFrame: Float = 0
    private(set) var eyeIsRed = false
    private(set) var spawnedLarvaCount = 0

    private let homePosition: Vec3f
    private var groundY: Float
    private var stateTimer = 0
    private var grantedReward = false

    public init(spawnRecord: ActorSpawnRecord) {
        homePosition = Vec3f(spawnRecord.spawn.position)
        groundY = Float(spawnRecord.spawn.position.y)
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 12,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 44,
                hurtboxHeight: 86,
                targetAnchorHeight: 96,
                targetingRange: 480,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 0, knockbackDistance: 0),
                    overrides: [
                        .swordSlash: DamageEffect(damage: 1, knockbackDistance: 8, invincibilityFrames: 10),
                        .swordJump: DamageEffect(damage: 2, knockbackDistance: 14, invincibilityFrames: 12),
                        .swordSpin: DamageEffect(damage: 2, knockbackDistance: 12, invincibilityFrames: 12),
                    ]
                )
            )
        )
    }

    public override func initialize(playState: PlayState) {
        groundY = resolveGroundY(near: position, in: playState.scene) ?? groundY
    }

    public override var isTargetable: Bool {
        state != .dead
    }

    public override var activeAttacks: [CombatAttackDefinition] {
        guard state == .floorAttack else {
            return []
        }

        let forward = SIMD3<Float>(
            sin(rawRotationToRadians(Float(rotation.y))),
            0,
            -cos(rawRotationToRadians(Float(rotation.y)))
        )
        let center = position.simd + (forward * 42)
        return [
            CombatAttackDefinition(
                collider: CombatCollider(
                    initialization: ColliderInit(collisionMask: [.at]),
                    shape: .cylinder(
                        ColliderCylinder(
                            center: Vec3f(center),
                            radius: 34,
                            height: 70
                        )
                    )
                ),
                element: .melee,
                effect: DamageEffect(damage: 1, knockbackDistance: 12, invincibilityFrames: 14)
            )
        ]
    }

    public var skeletonRenderState: ActorSkeletonRenderState? {
        ActorSkeletonRenderState(
            objectName: "object_goma",
            skeletonName: "gGohmaSkel",
            animationName: animationName,
            animationFrame: animationFrame,
            animationPlaybackMode: state == .dead ? .hold : .loop,
            modelMatrix: makeActorModelMatrix(
                position: position,
                yawRadians: rawRotationToRadians(Float(rotation.y)),
                scale: SIMD3<Float>(repeating: Constants.scale)
            )
        )
    }

    public override func update(playState: PlayState) {
        animationFrame += 1

        switch state {
        case .ceilingIdle:
            position = homePosition
            position.y = homePosition.y
            eyeIsRed = false
            stateTimer += 1
            if stateTimer >= Constants.ceilingIdleDuration {
                state = .ceilingPrepareSpawn
                stateTimer = 0
            }
        case .ceilingPrepareSpawn:
            eyeIsRed = true
            stateTimer += 1
            if stateTimer >= Constants.ceilingPrepareDuration {
                state = .ceilingSpawnLarva
                stateTimer = 0
            }
        case .ceilingSpawnLarva:
            eyeIsRed = false
            if spawnedLarvaCount == 0 {
                spawnLarvaWave(playState: playState)
            }
            stateTimer += 1
            if stateTimer >= Constants.spawnDuration {
                state = .falling
                stateTimer = 0
            }
        case .falling:
            eyeIsRed = false
            position.y = max(groundY, position.y - 6)
            if position.y <= groundY + 0.5 {
                position.y = groundY
                state = .floorStunned
                stateTimer = 0
                eyeIsRed = true
            }
        case .floorStunned:
            eyeIsRed = true
            stateTimer += 1
            if stateTimer >= Constants.floorStunDuration {
                state = .floorPatrol
                stateTimer = 0
                eyeIsRed = false
            }
        case .floorPatrol:
            eyeIsRed = false
            stateTimer += 1
            walkTowardPlayer(playState: playState, speed: Constants.moveSpeed)
            if stateTimer >= Constants.patrolDuration || distanceToPlayer(in: playState) <= 95 {
                state = .floorPrepareAttack
                stateTimer = 0
            }
        case .floorPrepareAttack:
            eyeIsRed = true
            stateTimer += 1
            facePlayer(playState: playState)
            if stateTimer >= Constants.prepareAttackDuration {
                state = .floorAttack
                stateTimer = 0
                eyeIsRed = false
            }
        case .floorAttack:
            eyeIsRed = false
            stateTimer += 1
            facePlayer(playState: playState)
            if stateTimer >= Constants.attackDuration {
                state = .floorPatrol
                stateTimer = 0
            }
        case .dead:
            eyeIsRed = false
            stateTimer += 1
            if grantedReward == false {
                grantedReward = true
                playState.requestReward(.chest(.heartContainer))
            }
            if stateTimer >= Constants.deathDuration {
                playState.requestDestroy(self)
            }
        }
    }

    public func combatHitResolution(
        for hit: CombatHit,
        attackerPosition: Vec3f?,
        playState: PlayState
    ) -> CombatHitResolution {
        guard state != .dead else {
            return .ignore
        }

        if hit.element == .projectile {
            if state == .ceilingPrepareSpawn {
                state = .falling
                stateTimer = 0
            } else if state == .floorPrepareAttack || state == .floorAttack {
                state = .floorStunned
                stateTimer = 0
                eyeIsRed = true
            }
            return .ignore
        }

        guard state == .floorStunned else {
            return .block
        }

        return super.combatHitResolution(
            for: hit,
            attackerPosition: attackerPosition,
            playState: playState
        )
    }

    public override func combatDidReceiveHit(_ hit: CombatHit, playState _: PlayState) {
        if hitPoints == 0 {
            state = .dead
            stateTimer = 0
            hitPoints = 1
        }
    }

    private var animationName: String {
        switch state {
        case .ceilingIdle:
            return "gGohmaHangAnim"
        case .ceilingPrepareSpawn:
            return "gGohmaPrepareEggsAnim"
        case .ceilingSpawnLarva:
            return "gGohmaLayEggsAnim"
        case .falling:
            return "gGohmaCrashAnim"
        case .floorStunned:
            return "gGohmaStunnedAnim"
        case .floorPatrol:
            return "gGohmaWalkAnim"
        case .floorPrepareAttack:
            return "gGohmaPrepareAttackAnim"
        case .floorAttack:
            return "gGohmaAttackAnim"
        case .dead:
            return "gGohmaDeathAnim"
        }
    }

    private func spawnLarvaWave(playState: PlayState) {
        let roomID = playState.currentRoomID ?? 0
        let offsets: [SIMD3<Float>] = [
            SIMD3<Float>(-28, -8, -12),
            SIMD3<Float>(0, -8, 20),
            SIMD3<Float>(26, -8, -10),
        ]

        for offset in offsets {
            let larva = GohmaLarvaActor(
                position: Vec3f(position.simd + offset),
                roomID: roomID
            )
            playState.requestSpawn(larva, category: .enemy, roomID: roomID)
            spawnedLarvaCount += 1
        }
    }

    private func walkTowardPlayer(playState: PlayState, speed: Float) {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return
        }

        let direction = normalizedDirection(
            from: position.simd,
            to: playerPosition,
            fallbackYaw: rawRotationToRadians(Float(rotation.y))
        )
        position = Vec3f(position.simd + (direction * speed))
        position.y = groundY
        rotation.y = radiansToRawYaw(yawRadians(from: position.simd, to: playerPosition))
    }

    private func facePlayer(playState: PlayState) {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return
        }

        rotation.y = radiansToRawYaw(yawRadians(from: position.simd, to: playerPosition))
    }

    private func distanceToPlayer(in playState: PlayState) -> Float {
        guard let playerPosition = playStatePlayerPosition(playState) else {
            return .greatestFiniteMagnitude
        }

        return simd_distance(playerPosition, position.simd)
    }
}

private func rawRotationToRadians(_ rawValue: Float) -> Float {
    rawValue * (.pi / 32_768)
}

private func radiansToRawYaw(_ radians: Float) -> Int16 {
    Int16(clamping: Int((radians / .pi) * 32_768))
}

private func yawRadians(from source: SIMD3<Float>, to target: SIMD3<Float>) -> Float {
    atan2(target.x - source.x, -(target.z - source.z))
}

private func makeActorModelMatrix(
    position: Vec3f,
    yawRadians: Float,
    scale: SIMD3<Float>
) -> simd_float4x4 {
    let translation = simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(position.x, position.y, position.z, 1)
    )
    let cosine = cos(yawRadians)
    let sine = sin(yawRadians)
    let rotation = simd_float4x4(
        SIMD4<Float>(cosine, 0, -sine, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(sine, 0, cosine, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
    let scaling = simd_float4x4(
        SIMD4<Float>(scale.x, 0, 0, 0),
        SIMD4<Float>(0, scale.y, 0, 0),
        SIMD4<Float>(0, 0, scale.z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
    return translation * rotation * scaling
}

private func resolveGroundY(near position: Vec3f, in scene: LoadedScene?) -> Float? {
    guard let scene else {
        return nil
    }

    let collisionSystem = CollisionSystem(scene: scene)
    let samplePosition = SIMD3<Float>(position.x, position.y + 200, position.z)
    return collisionSystem.findFloor(at: samplePosition)?.floorY
}

@MainActor
private func playStatePlayerPosition(_ playState: PlayState) -> SIMD3<Float>? {
    playState.currentPlayerState?.position.simd
}

private func normalizePlanar(_ vector: SIMD3<Float>) -> SIMD2<Float> {
    let planar = SIMD2<Float>(vector.x, vector.z)
    let length = simd_length(planar)
    guard length > 0.001 else {
        return .zero
    }
    return planar / length
}

private func normalizedDirection(
    from source: SIMD3<Float>,
    to destination: SIMD3<Float>,
    fallbackYaw: Float
) -> SIMD3<Float> {
    let delta = destination - source
    let planar = SIMD2<Float>(delta.x, delta.z)
    let planarLength = simd_length(planar)

    guard planarLength > 0.001 else {
        return SIMD3<Float>(
            sin(fallbackYaw),
            0,
            -cos(fallbackYaw)
        )
    }

    return SIMD3<Float>(planar.x / planarLength, 0, planar.y / planarLength)
}
