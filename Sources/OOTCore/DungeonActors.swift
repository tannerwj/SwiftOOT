import Foundation
import simd

@MainActor
public final class TorchActor: BaseActor, TalkRequestingActor, FireSourceActor, FireInteractableActor {
    private var isLit = false

    var providesFireSource: Bool {
        true
    }

    var isIgnited: Bool {
        isLit
    }

    public var talkPrompt: String {
        "Light"
    }

    public var talkInteractionRange: Float {
        isLit ? 0 : 72
    }

    public override func initialize(playState: PlayState) {
        guard let eventKey = dungeonEventKey(kind: .torchLit, playState: playState) else {
            return
        }

        isLit = playState.isDungeonEventTriggered(eventKey)
    }

    public func talkRequested(playState: PlayState) -> Bool {
        guard
            isLit == false,
            playState.currentInventoryState().dekuStickCount > 0,
            let eventKey = dungeonEventKey(kind: .torchLit, playState: playState)
        else {
            return false
        }

        playState.markDungeonEventTriggered(eventKey)
        isLit = true
        return true
    }

    func ignite(playState: PlayState) {
        guard
            isLit == false,
            let eventKey = dungeonEventKey(kind: .torchLit, playState: playState)
        else {
            return
        }

        playState.markDungeonEventTriggered(eventKey)
        isLit = true
    }
}

@MainActor
public final class DungeonSwitchActor: BaseActor, TalkRequestingActor {
    private var isPressed = false

    public var talkPrompt: String {
        "Press"
    }

    public var talkInteractionRange: Float {
        isPressed ? 0 : 72
    }

    public override func initialize(playState: PlayState) {
        guard let eventKey = dungeonEventKey(kind: .switchPressed, playState: playState) else {
            return
        }

        isPressed = playState.isDungeonEventTriggered(eventKey)
    }

    public func talkRequested(playState: PlayState) -> Bool {
        guard
            isPressed == false,
            let eventKey = dungeonEventKey(kind: .switchPressed, playState: playState)
        else {
            return false
        }

        playState.markDungeonEventTriggered(eventKey)
        isPressed = true
        return true
    }
}

@MainActor
public final class BurnableWebActor: BaseActor, TalkRequestingActor, FireInteractableActor {
    private var isBurned = false

    var isIgnited: Bool {
        isBurned
    }

    public var talkPrompt: String {
        "Burn"
    }

    public var talkInteractionRange: Float {
        isBurned ? 0 : 84
    }

    public override func initialize(playState: PlayState) {
        guard let eventKey = dungeonEventKey(kind: .webBurned, playState: playState) else {
            return
        }

        isBurned = playState.isDungeonEventTriggered(eventKey)
        if isBurned {
            playState.requestDestroy(self)
        }
    }

    public func talkRequested(playState: PlayState) -> Bool {
        guard
            isBurned == false,
            playState.currentInventoryState().dekuStickCount > 0,
            let eventKey = dungeonEventKey(kind: .webBurned, playState: playState)
        else {
            return false
        }

        playState.markDungeonEventTriggered(eventKey)
        isBurned = true
        playState.requestDestroy(self)
        return true
    }

    func ignite(playState: PlayState) {
        guard
            isBurned == false,
            let eventKey = dungeonEventKey(kind: .webBurned, playState: playState)
        else {
            return
        }

        playState.markDungeonEventTriggered(eventKey)
        isBurned = true
        playState.requestDestroy(self)
    }
}

@MainActor
public final class PushableBlockActor: BaseActor, TalkRequestingActor {
    private var hasMoved = false

    public var talkPrompt: String {
        "Push"
    }

    public var talkInteractionRange: Float {
        hasMoved ? 0 : 88
    }

    public override func initialize(playState: PlayState) {
        guard let eventKey = dungeonEventKey(kind: .blockMoved, playState: playState) else {
            return
        }

        hasMoved = playState.isDungeonEventTriggered(eventKey)
        if hasMoved {
            position = movedPosition
        }
    }

    public func talkRequested(playState: PlayState) -> Bool {
        guard
            hasMoved == false,
            let eventKey = dungeonEventKey(kind: .blockMoved, playState: playState)
        else {
            return false
        }

        playState.markDungeonEventTriggered(eventKey)
        hasMoved = true
        position = movedPosition
        return true
    }

    private var movedPosition: Vec3f {
        let yaw = rawRotationToRadians(Float(rotation.y))
        let offset = SIMD3<Float>(sin(yaw), 0, -cos(yaw)) * 80
        return Vec3f(position.simd + offset)
    }
}

@MainActor
public final class DekuScrubActor: CombatantBaseActor {
    private var isStunned = false
    private var stunFramesRemaining = 0
    private var attackCooldownFrames = 20
    private var emitsProjectileThisFrame = false
    private var defeatEventCommitted = false

    public init(spawnRecord: ActorSpawnRecord) {
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 1,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 18,
                hurtboxHeight: 36,
                targetAnchorHeight: 26,
                targetingRange: 260,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 0, knockbackDistance: 0),
                    overrides: [:]
                )
            )
        )
    }

    public override var isTargetable: Bool {
        isStunned && hitPoints > 0
    }

    public override func initialize(playState: PlayState) {
        guard let defeatEventKey = dungeonEventKey(kind: .enemyDefeated, playState: playState) else {
            return
        }

        if playState.isDungeonEventTriggered(defeatEventKey) {
            defeatEventCommitted = true
            hitPoints = 0
            playState.requestDestroy(self)
        }
    }

    public override func update(playState: PlayState) {
        if hitPoints <= 0 {
            commitDefeatEventIfNeeded(playState: playState)
            return
        }

        if stunFramesRemaining > 0 {
            stunFramesRemaining -= 1
            emitsProjectileThisFrame = false
            if stunFramesRemaining == 0 {
                isStunned = false
                combatProfile.damageTable = DamageTable(
                    defaultEffect: DamageEffect(damage: 0, knockbackDistance: 0),
                    overrides: [:]
                )
            }
            return
        }

        emitsProjectileThisFrame = false
        attackCooldownFrames = max(0, attackCooldownFrames - 1)
        if attackCooldownFrames == 0 {
            emitsProjectileThisFrame = true
            attackCooldownFrames = 24
        }
    }

    public override var activeAttacks: [CombatAttackDefinition] {
        guard hitPoints > 0, isStunned == false, emitsProjectileThisFrame else {
            return []
        }

        let yaw = rawRotationToRadians(Float(rotation.y))
        let forward = SIMD3<Float>(sin(yaw), 0, -cos(yaw))
        let attackCenter = position.simd + forward * 28

        return [
            CombatAttackDefinition(
                collider: CombatCollider(
                    initialization: ColliderInit(collisionMask: [.at]),
                    shape: .cylinder(
                        ColliderCylinder(
                            center: Vec3f(attackCenter),
                            radius: 20,
                            height: 32
                        )
                    )
                ),
                element: .projectile,
                effect: DamageEffect(damage: 1, knockbackDistance: 12, invincibilityFrames: 8),
                isProjectile: true
            ),
        ]
    }

    public override func combatDidReceiveHit(_ hit: CombatHit, playState: PlayState) {
        if hitPoints <= 0 {
            commitDefeatEventIfNeeded(playState: playState)
        }
    }

    public override func combatDidBlockHit(_ hit: CombatHit, playState: PlayState) {
        guard hit.element.canBeBlockedAsProjectile || hit.element == .flash else {
            return
        }

        isStunned = true
        stunFramesRemaining = 0
        emitsProjectileThisFrame = false
        attackCooldownFrames = 45
        hitPoints = 0
        commitDefeatEventIfNeeded(playState: playState)
    }

    private func commitDefeatEventIfNeeded(playState: PlayState) {
        guard defeatEventCommitted == false else {
            return
        }

        defeatEventCommitted = true
        if let defeatEventKey = dungeonEventKey(kind: .enemyDefeated, playState: playState) {
            playState.markDungeonEventTriggered(defeatEventKey)
        }
        playState.requestDestroy(self)
    }
}

private extension BaseActor {
    func dungeonEventKey(
        kind: DungeonEventKind,
        playState: PlayState
    ) -> DungeonEventFlagKey? {
        let sceneIdentity: SceneIdentity
        if let currentScene = playState.currentSceneIdentity {
            sceneIdentity = currentScene
        } else if let scene = playState.scene?.manifest {
            sceneIdentity = SceneIdentity(id: scene.id, name: scene.name)
        } else {
            return nil
        }

        return DungeonEventFlagKey(
            scene: sceneIdentity,
            kind: kind,
            roomID: roomID,
            actorID: profile.id,
            params: Int(Int16(bitPattern: params)),
            positionX: Int(spawnPosition.x),
            positionY: Int(spawnPosition.y),
            positionZ: Int(spawnPosition.z)
        )
    }

    func rawRotationToRadians(_ rawValue: Float) -> Float {
        rawValue * (.pi / 32_768)
    }
}
