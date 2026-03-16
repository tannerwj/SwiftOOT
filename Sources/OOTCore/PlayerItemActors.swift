import OOTDataModel
import simd

@MainActor
protocol PlayerItemEffectResolvingActor: Actor {
    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors: [any Actor]
    )
}

@MainActor
protocol FireSourceActor: Actor {
    var providesFireSource: Bool { get }
}

@MainActor
protocol FireInteractableActor: Actor {
    var isIgnited: Bool { get }
    func ignite(playState: PlayState)
}

@MainActor
protocol BombReactiveActor: Actor {
    func triggerBombReaction(playState: PlayState)
}

@MainActor
private func applyPlayerItemHit(
    to actor: any CombatActor,
    element: DamageElement,
    attackerPosition: Vec3f,
    playState: PlayState
) {
    guard actor.hitPoints > 0, actor.combatState.invincibilityFramesRemaining == 0 else {
        return
    }

    let direction = normalizedItemDirection(
        from: attackerPosition.simd,
        to: actor.position.simd
    )
    let proposedHit = CombatHit(
        source: .player,
        element: element,
        direction: Vec3f(direction),
        effect: actor.combatProfile.damageTable.effect(for: element)
    )

    switch actor.combatHitResolution(
        for: proposedHit,
        attackerPosition: attackerPosition,
        playState: playState
    ) {
    case .ignore:
        return
    case .block:
        var combatState = actor.combatState
        combatState.lastBlockedElement = element
        actor.combatState = combatState
        actor.combatDidBlockHit(
            CombatHit(
                source: .player,
                element: element,
                direction: Vec3f(direction),
                effect: proposedHit.effect,
                wasBlocked: true
            ),
            playState: playState
        )
    case .apply(let effect):
        actor.hitPoints = max(0, actor.hitPoints - effect.damage)
        var combatState = actor.combatState
        combatState.invincibilityFramesRemaining = effect.invincibilityFrames
        combatState.lastReceivedElement = element
        combatState.lastReceivedDamage = effect.damage
        combatState.lastBlockedElement = nil
        combatState.knockbackFramesRemaining = max(1, min(6, effect.invincibilityFrames / 2))
        combatState.knockbackVelocity = Vec3f(
            direction * (effect.knockbackDistance / Float(max(combatState.knockbackFramesRemaining, 1)))
        )
        actor.combatState = combatState
        actor.combatDidReceiveHit(
            CombatHit(
                source: .player,
                element: element,
                direction: Vec3f(direction),
                effect: effect
            ),
            playState: playState
        )
    }
}

private func normalizedItemDirection(
    from source: SIMD3<Float>,
    to target: SIMD3<Float>
) -> SIMD3<Float> {
    let offset = target - source
    let distanceSquared = simd_length_squared(offset)
    guard distanceSquared > 0.000_1 else {
        return SIMD3<Float>(0, 0, -1)
    }
    return simd_normalize(offset)
}

private func syntheticItemProfile(
    id: Int,
    category: ActorCategory
) -> ActorProfile {
    ActorProfile(
        id: id,
        category: category.rawValue,
        flags: 0,
        objectID: 0
    )
}

@MainActor
final class SlingshotProjectileActor: BaseActor, PlayerItemEffectResolvingActor {
    private var velocity: SIMD3<Float>
    private var remainingFrames: Int

    init(
        position: Vec3f,
        direction: SIMD3<Float>,
        roomID: Int
    ) {
        velocity = simd_normalize(direction) * 16
        remainingFrames = 28
        super.init(
            profile: syntheticItemProfile(id: 90_100, category: .item),
            category: .item,
            position: position,
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_SLINGSHOT"
        )
    }

    override func update(playState: PlayState) {
        position = Vec3f(position.simd + velocity)
        remainingFrames -= 1
        if remainingFrames <= 0 {
            playState.requestDestroy(self)
        }
    }

    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors _: [any Actor]
    ) {
        let pellet = ColliderCylinder(center: position, radius: 10, height: 10)

        for actor in combatActors {
            guard CombatCollisionResolver.intersects(pellet, with: actor.hurtbox) else {
                continue
            }

            applyPlayerItemHit(
                to: actor,
                element: .projectile,
                attackerPosition: position,
                playState: playState
            )
            playState.requestDestroy(self)
            return
        }
    }
}

@MainActor
final class BombActor: BaseActor, BombReactiveActor {
    private var velocity: SIMD3<Float>
    private var fuseFramesRemaining: Int

    init(
        position: Vec3f,
        velocity: SIMD3<Float>,
        roomID: Int
    ) {
        self.velocity = velocity
        fuseFramesRemaining = 55
        super.init(
            profile: syntheticItemProfile(id: 90_101, category: .bomb),
            category: .bomb,
            position: position,
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_BOMB"
        )
    }

    override func update(playState: PlayState) {
        position = Vec3f(position.simd + velocity)
        velocity *= 0.9
        if simd_length_squared(velocity) < 0.01 {
            velocity = .zero
        }

        fuseFramesRemaining -= 1
        if fuseFramesRemaining <= 0 {
            playState.requestSpawn(
                BombExplosionActor(position: position, roomID: roomID),
                category: .misc,
                roomID: roomID
            )
            playState.requestDestroy(self)
        }
    }

    func triggerBombReaction(playState _: PlayState) {
        fuseFramesRemaining = min(fuseFramesRemaining, 2)
    }
}

@MainActor
final class BombExplosionActor: BaseActor, PlayerItemEffectResolvingActor {
    private var didResolve = false
    private var remainingFrames = 2

    init(position: Vec3f, roomID: Int) {
        super.init(
            profile: syntheticItemProfile(id: 90_102, category: .misc),
            category: .misc,
            position: position,
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_BOMB_EXPLOSION"
        )
    }

    override func update(playState: PlayState) {
        remainingFrames -= 1
        if remainingFrames <= 0 {
            playState.requestDestroy(self)
        }
    }

    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors: [any Actor]
    ) {
        guard didResolve == false else {
            return
        }

        didResolve = true
        let blast = ColliderCylinder(center: position, radius: 90, height: 72)

        for actor in combatActors where CombatCollisionResolver.intersects(blast, with: actor.hurtbox) {
            applyPlayerItemHit(
                to: actor,
                element: .explosion,
                attackerPosition: position,
                playState: playState
            )
        }

        for actor in actors {
            guard ObjectIdentifier(actor) != ObjectIdentifier(self) else {
                continue
            }

            if
                let ignitable = actor as? any FireInteractableActor,
                simd_distance(actor.position.simd, position.simd) <= 96
            {
                ignitable.ignite(playState: playState)
            }

            if
                let reactive = actor as? any BombReactiveActor,
                simd_distance(actor.position.simd, position.simd) <= 96
            {
                reactive.triggerBombReaction(playState: playState)
            }
        }
    }
}

@MainActor
final class BoomerangActor: BaseActor, PlayerItemEffectResolvingActor {
    private var velocity: SIMD3<Float>
    private var frameCount = 0
    private var isReturning = false
    private var hitTargets: Set<ObjectIdentifier> = []

    init(
        position: Vec3f,
        direction: SIMD3<Float>,
        roomID: Int
    ) {
        velocity = simd_normalize(direction) * 13
        super.init(
            profile: syntheticItemProfile(id: 90_103, category: .item),
            category: .item,
            position: position,
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_BOOMERANG"
        )
    }

    override func update(playState: PlayState) {
        frameCount += 1

        if isReturning == false, frameCount >= 14 {
            isReturning = true
        }

        if isReturning, let playerPosition = playState.currentPlayerState?.position.simd {
            let toPlayer = normalizedItemDirection(from: position.simd, to: playerPosition)
            velocity = toPlayer * 13
            if simd_distance(playerPosition, position.simd) <= 20 {
                playState.requestDestroy(self)
                return
            }
        }

        position = Vec3f(position.simd + velocity)
    }

    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors _: [any Actor]
    ) {
        let boomerang = ColliderCylinder(center: position, radius: 14, height: 18)

        for actor in combatActors {
            let actorID = ObjectIdentifier(actor)
            guard hitTargets.contains(actorID) == false else {
                continue
            }
            guard CombatCollisionResolver.intersects(boomerang, with: actor.hurtbox) else {
                continue
            }
            applyPlayerItemHit(
                to: actor,
                element: .boomerang,
                attackerPosition: position,
                playState: playState
            )
            hitTargets.insert(actorID)
            isReturning = true
        }
    }
}

@MainActor
final class DekuNutFlashActor: BaseActor, PlayerItemEffectResolvingActor {
    private var didResolve = false
    private var remainingFrames = 2

    init(position: Vec3f, roomID: Int) {
        super.init(
            profile: syntheticItemProfile(id: 90_104, category: .misc),
            category: .misc,
            position: position,
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_DEKU_NUT"
        )
    }

    override func update(playState: PlayState) {
        remainingFrames -= 1
        if remainingFrames <= 0 {
            playState.requestDestroy(self)
        }
    }

    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors _: [any Actor]
    ) {
        guard didResolve == false else {
            return
        }

        didResolve = true
        let flash = ColliderCylinder(center: position, radius: 128, height: 72)
        for actor in combatActors where CombatCollisionResolver.intersects(flash, with: actor.hurtbox) {
            applyPlayerItemHit(
                to: actor,
                element: .flash,
                attackerPosition: position,
                playState: playState
            )
        }
    }
}

@MainActor
final class DekuStickSwingActor: BaseActor, PlayerItemEffectResolvingActor {
    private let isLit: Bool
    private var remainingFrames = 8
    private var hitTargets: Set<ObjectIdentifier> = []

    init(
        position: Vec3f,
        facingRadians: Float,
        isLit: Bool,
        roomID: Int
    ) {
        self.isLit = isLit
        super.init(
            profile: syntheticItemProfile(id: 90_105, category: .item),
            category: .item,
            position: position,
            rotation: Vector3s(x: 0, y: Int16((facingRadians * 32_768 / .pi).rounded()), z: 0),
            roomID: roomID,
            spawnActorName: "ACTOR_PLAYER_DEKU_STICK"
        )
    }

    override func update(playState: PlayState) {
        remainingFrames -= 1
        if let playerPosition = playState.currentPlayerState?.position {
            position = playerPosition
        }
        if remainingFrames <= 0 {
            playState.requestDestroy(self)
        }
    }

    func resolveGameplayEffects(
        playState: PlayState,
        combatActors: [any CombatActor],
        actors: [any Actor]
    ) {
        let yaw = Float(rotation.y) * (.pi / 32_768.0)
        let center = position.simd + SIMD3<Float>(sin(yaw), 0, -cos(yaw)) * 36
        let swing = ColliderCylinder(center: Vec3f(center), radius: 26, height: 44)

        for actor in combatActors {
            let actorID = ObjectIdentifier(actor)
            guard hitTargets.contains(actorID) == false else {
                continue
            }
            guard CombatCollisionResolver.intersects(swing, with: actor.hurtbox) else {
                continue
            }

            applyPlayerItemHit(
                to: actor,
                element: .melee,
                attackerPosition: position,
                playState: playState
            )
            hitTargets.insert(actorID)
        }

        guard isLit else {
            return
        }

        for actor in actors {
            guard let ignitable = actor as? any FireInteractableActor else {
                continue
            }
            if simd_distance(actor.position.simd, center) <= 48 {
                ignitable.ignite(playState: playState)
            }
        }
    }
}
