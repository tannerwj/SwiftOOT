import simd

struct ActivePlayerAttackState {
    let kind: PlayerAttackKind
    let element: DamageElement
    let totalFrames: Int
    let activeFrameRange: ClosedRange<Int>
    let movementFrames: Range<Int>
    let movementDistancePerFrame: Float

    var frame: Int = 0
    var hitTargets: Set<ObjectIdentifier> = []

    var isActive: Bool {
        activeFrameRange.contains(frame)
    }

    var snapshot: PlayerAttackSnapshot {
        PlayerAttackSnapshot(
            kind: kind,
            frame: frame,
            totalFrames: totalFrames,
            activeFrameRange: activeFrameRange,
            isActive: isActive
        )
    }
}

private struct CombatTargetCandidate {
    let actor: any TargetableActor
    let actorIndex: Int
    let worldPosition: SIMD3<Float>
    let distanceSquared: Float
    let facingAlignment: Float
}

extension GameRuntime {
    var combatActionLabel: String? {
        guard currentState == .gameplay else {
            return nil
        }

        if canBeginJumpAttack(with: controllerInputState) {
            return "Jump"
        }
        if shieldShouldBeRaised(for: controllerInputState) {
            return "Guard"
        }
        return nil
    }

    func resetCombatState() {
        combatLockOnTargetID = nil
        activePlayerAttackState = nil
        playerInvincibilityFramesRemaining = 0
        bButtonChargeFrames = 0
        syncCombatObservationState()
    }

    func movementInputState(for input: ControllerInputState) -> ControllerInputState {
        if activePlayerAttackState == nil, isGameplayItemAimActive == false {
            return input
        }

        return ControllerInputState(
            stick: .zero,
            aPressed: false,
            bPressed: input.bPressed,
            lPressed: input.lPressed,
            rPressed: input.rPressed,
            cLeftPressed: input.cLeftPressed,
            cDownPressed: input.cDownPressed,
            cRightPressed: input.cRightPressed,
            zPressed: input.zPressed,
            startPressed: input.startPressed
        )
    }

    func currentLockOnTargetFocusPoint() -> SIMD3<Float>? {
        currentLockOnTargetSnapshot()?.focusPoint.simd
    }

    func activePlayerAttackForcedDisplacement() -> SIMD3<Float> {
        guard
            let attack = activePlayerAttackState,
            attack.movementFrames.contains(attack.frame),
            let playerState
        else {
            return .zero
        }

        let facing = SIMD3<Float>(
            sin(playerState.facingRadians),
            0,
            -cos(playerState.facingRadians)
        )
        return facing * attack.movementDistancePerFrame
    }

    func canUsePrimaryGameplayInput(for input: ControllerInputState) -> Bool {
        if activePlayerAttackState != nil {
            return false
        }
        if isGameplayItemAimActive {
            return false
        }
        if canBeginJumpAttack(with: input) {
            return false
        }
        return true
    }

    func updateCombatStateBeforeActorStep(currentInput: ControllerInputState) {
        tickActorCombatState()
        tickPlayerInvincibility()
        updateLockOnState(currentInput: currentInput)
        updatePlayerAttackInput(currentInput: currentInput)
        syncCombatObservationState()
    }

    func updateCombatStateAfterActorStep(
        playState: PlayState,
        currentInput: ControllerInputState
    ) {
        resolvePlayerAttackHits(playState: playState)
        resolvePlayerItemEffects(playState: playState)
        resolveIncomingActorAttacks(playState: playState)
        advanceActivePlayerAttack()
        updateLockOnState(currentInput: currentInput)
    }

    func syncCombatObservationState() {
        combatState = GameplayCombatState(
            lockOnTarget: currentLockOnTargetSnapshot(),
            activeAttack: activePlayerAttackState?.snapshot,
            shieldRaised: shieldShouldBeRaised(for: controllerInputState),
            playerInvincibilityFramesRemaining: playerInvincibilityFramesRemaining
        )
    }

    func currentXRayPlayerAttackCollider() -> CombatCollider? {
        guard
            let attack = activePlayerAttackState,
            let playerState,
            attack.isActive
        else {
            return nil
        }

        return playerAttackCollider(for: attack, playerState: playerState)
    }
}

private extension GameRuntime {
    var combatActors: [any CombatActor] {
        actors.compactMap { $0 as? (any CombatActor) }
    }

    func currentLockOnTargetActor() -> (any TargetableActor)? {
        guard let combatLockOnTargetID else {
            return nil
        }

        return actors.first { ObjectIdentifier($0) == combatLockOnTargetID } as? (any TargetableActor)
    }

    func currentLockOnTargetSnapshot() -> CombatTargetSnapshot? {
        guard
            let playerState,
            let target = currentLockOnTargetActor()
        else {
            return nil
        }

        let position = target.position
        let distance = simd_distance(playerState.position.simd, position.simd)
        return CombatTargetSnapshot(
            actorID: target.profile.id,
            actorType: String(describing: type(of: target)),
            position: position,
            anchorHeight: target.targetAnchorHeight,
            distance: distance
        )
    }

    func shieldShouldBeRaised(for input: ControllerInputState) -> Bool {
        currentState == .gameplay &&
            isGameplayPresentationActive == false &&
            inventoryContext.equipment.equippedShield != nil &&
            input.zPressed &&
            currentLockOnTargetActor() == nil
    }

    func tickPlayerInvincibility() {
        playerInvincibilityFramesRemaining = max(0, playerInvincibilityFramesRemaining - 1)
    }

    func tickActorCombatState() {
        for actor in combatActors {
            var state = actor.combatState
            state.invincibilityFramesRemaining = max(0, state.invincibilityFramesRemaining - 1)

            if state.knockbackFramesRemaining > 0 {
                actor.position = Vec3f(actor.position.simd + state.knockbackVelocity.simd)
                state.knockbackFramesRemaining -= 1
                state.knockbackVelocity = Vec3f(state.knockbackVelocity.simd * 0.72)
            } else {
                state.knockbackVelocity = Vec3f(x: 0, y: 0, z: 0)
            }

            actor.combatState = state
        }
    }

    func updateLockOnState(currentInput: ControllerInputState) {
        guard currentState == .gameplay, let playerState else {
            combatLockOnTargetID = nil
            return
        }

        guard currentInput.zPressed else {
            combatLockOnTargetID = nil
            return
        }

        if
            let currentTarget = currentLockOnTargetActor(),
            isValidTarget(currentTarget, playerState: playerState)
        {
            if let switchDirection = targetSwitchDirection(
                previous: previousControllerInputState.stick,
                current: currentInput.stick
            ),
               let switchedTarget = resolveSwitchedTarget(
                   direction: switchDirection,
                   currentTarget: currentTarget,
                   playerState: playerState
               )
            {
                combatLockOnTargetID = ObjectIdentifier(switchedTarget.actor)
            }
            return
        }

        combatLockOnTargetID = resolveNearestTarget(playerState: playerState).map { ObjectIdentifier($0.actor) }
    }

    func resolveNearestTarget(playerState: PlayerState) -> CombatTargetCandidate? {
        let playerPosition = playerState.position.simd
        let playerForward = SIMD2<Float>(
            sin(playerState.facingRadians),
            -cos(playerState.facingRadians)
        )

        return targetCandidates(playerState: playerState)
            .min { lhs, rhs in
                let lhsAhead = lhs.facingAlignment >= -0.1
                let rhsAhead = rhs.facingAlignment >= -0.1
                if lhsAhead != rhsAhead {
                    return lhsAhead
                }
                if abs(lhs.distanceSquared - rhs.distanceSquared) > 0.001 {
                    return lhs.distanceSquared < rhs.distanceSquared
                }
                if abs(lhs.facingAlignment - rhs.facingAlignment) > 0.001 {
                    return lhs.facingAlignment > rhs.facingAlignment
                }
                let lhsOffset = lhs.worldPosition - playerPosition
                let rhsOffset = rhs.worldPosition - playerPosition
                let lhsPlanar = SIMD2<Float>(lhsOffset.x, lhsOffset.z)
                let rhsPlanar = SIMD2<Float>(rhsOffset.x, rhsOffset.z)
                return simd_dot(lhsPlanar, playerForward) > simd_dot(rhsPlanar, playerForward)
            }
    }

    func resolveSwitchedTarget(
        direction: Float,
        currentTarget: any TargetableActor,
        playerState: PlayerState
    ) -> CombatTargetCandidate? {
        let playerPosition = playerState.position.simd
        let currentOffset = currentTarget.position.simd - playerPosition
        let currentPlanar = normalizedPlanarVector(from: currentOffset)

        let sidedCandidates = targetCandidates(playerState: playerState)
            .filter { ObjectIdentifier($0.actor) != ObjectIdentifier(currentTarget) }
            .compactMap { candidate -> (CombatTargetCandidate, Float)? in
                let offset = candidate.worldPosition - playerPosition
                let planar = normalizedPlanarVector(from: offset)
                let cross = currentPlanar.x * planar.y - currentPlanar.y * planar.x
                guard direction > 0 ? cross > 0.05 : cross < -0.05 else {
                    return nil
                }

                return (candidate, abs(cross))
            }

        return sidedCandidates.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.001 {
                return lhs.1 > rhs.1
            }
            return lhs.0.distanceSquared < rhs.0.distanceSquared
        }?.0
    }

    func targetCandidates(playerState: PlayerState) -> [CombatTargetCandidate] {
        let playerPosition = playerState.position.simd
        let playerForward = SIMD2<Float>(
            sin(playerState.facingRadians),
            -cos(playerState.facingRadians)
        )

        return actors.enumerated().compactMap { index, actor -> CombatTargetCandidate? in
            guard let target = actor as? (any TargetableActor), isValidTarget(target, playerState: playerState) else {
                return nil
            }

            let offset = target.position.simd - playerPosition
            let planarOffset = SIMD2<Float>(offset.x, offset.z)
            let distanceSquared = simd_length_squared(planarOffset)
            let facingAlignment: Float
            if simd_length_squared(planarOffset) > 0.000_1 {
                facingAlignment = simd_dot(playerForward, simd_normalize(planarOffset))
            } else {
                facingAlignment = 1
            }

            return CombatTargetCandidate(
                actor: target,
                actorIndex: index,
                worldPosition: target.position.simd,
                distanceSquared: distanceSquared,
                facingAlignment: facingAlignment
            )
        }
    }

    func isValidTarget(
        _ target: any TargetableActor,
        playerState: PlayerState
    ) -> Bool {
        guard target.isTargetable else {
            return false
        }

        let planarOffset = SIMD2<Float>(
            target.position.x - playerState.position.x,
            target.position.z - playerState.position.z
        )
        let rangeSquared = target.targetingRange * target.targetingRange
        return simd_length_squared(planarOffset) <= rangeSquared
    }

    func targetSwitchDirection(
        previous: StickInput,
        current: StickInput
    ) -> Float? {
        let threshold: Float = 0.7
        guard abs(current.x) > abs(current.y) else {
            return nil
        }
        guard abs(previous.x) < threshold, abs(current.x) >= threshold else {
            return nil
        }
        return current.x
    }

    func updatePlayerAttackInput(currentInput: ControllerInputState) {
        guard currentState == .gameplay else {
            activePlayerAttackState = nil
            bButtonChargeFrames = 0
            return
        }

        guard isGameplayPresentationActive == false else {
            bButtonChargeFrames = 0
            return
        }

        guard activePlayerAttackState == nil else {
            bButtonChargeFrames = 0
            return
        }

        guard inventoryContext.equipment.equippedSword != nil else {
            bButtonChargeFrames = 0
            return
        }

        if canBeginJumpAttack(with: currentInput) {
            beginPlayerAttack(.jump)
            bButtonChargeFrames = 0
            return
        }

        if currentInput.bPressed {
            bButtonChargeFrames += 1
            return
        }

        if previousControllerInputState.bPressed, bButtonChargeFrames > 0 {
            beginPlayerAttack(bButtonChargeFrames >= 18 ? .spin : .slash)
        }
        bButtonChargeFrames = 0
    }

    func canBeginJumpAttack(with input: ControllerInputState) -> Bool {
        guard
            activePlayerAttackState == nil,
            currentState == .gameplay,
            isGameplayPresentationActive == false,
            input.aPressed,
            previousControllerInputState.aPressed == false
        else {
            return false
        }

        return input.stick.y > 0.65
    }

    func beginPlayerAttack(_ kind: PlayerAttackKind) {
        switch kind {
        case .slash:
            activePlayerAttackState = ActivePlayerAttackState(
                kind: .slash,
                element: .swordSlash,
                totalFrames: 14,
                activeFrameRange: 4...7,
                movementFrames: 0..<0,
                movementDistancePerFrame: 0
            )
            queueSoundEffect(.swordSlash, sourcePosition: playerState?.position)
        case .jump:
            activePlayerAttackState = ActivePlayerAttackState(
                kind: .jump,
                element: .swordJump,
                totalFrames: 18,
                activeFrameRange: 5...9,
                movementFrames: 0..<6,
                movementDistancePerFrame: 4.5
            )
        case .spin:
            activePlayerAttackState = ActivePlayerAttackState(
                kind: .spin,
                element: .swordSpin,
                totalFrames: 24,
                activeFrameRange: 8...16,
                movementFrames: 0..<0,
                movementDistancePerFrame: 0
            )
        }
    }

    func advanceActivePlayerAttack() {
        guard var attack = activePlayerAttackState else {
            return
        }

        attack.frame += 1
        activePlayerAttackState = attack.frame > attack.totalFrames ? nil : attack
    }

    func resolvePlayerAttackHits(playState: PlayState) {
        guard
            var attack = activePlayerAttackState,
            attack.isActive,
            let playerState
        else {
            return
        }

        let hitbox = playerAttackCollider(for: attack, playerState: playerState)

        for actor in combatActors {
            let actorID = ObjectIdentifier(actor)
            guard attack.hitTargets.contains(actorID) == false else {
                continue
            }
            guard actor.hitPoints > 0, actor.combatState.invincibilityFramesRemaining == 0 else {
                continue
            }
            guard CombatCollisionResolver.intersects(hitbox.shape, with: actor.hurtbox) else {
                continue
            }

            let direction = normalizedDirection(
                from: playerState.position.simd,
                to: actor.position.simd,
                fallbackYaw: playerState.facingRadians
            )

            let proposedHit = CombatHit(
                source: .player,
                element: attack.element,
                direction: Vec3f(direction),
                effect: actor.combatProfile.damageTable.effect(for: attack.element)
            )

            switch actor.combatHitResolution(
                for: proposedHit,
                attackerPosition: playerState.position,
                playState: playState
            ) {
            case .ignore:
                attack.hitTargets.insert(actorID)
                continue
            case .block:
                var combatState = actor.combatState
                combatState.lastBlockedElement = attack.element
                actor.combatState = combatState
                actor.combatDidBlockHit(
                    CombatHit(
                        source: .player,
                        element: attack.element,
                        direction: Vec3f(direction),
                        effect: proposedHit.effect,
                        wasBlocked: true
                    ),
                    playState: playState
                )
                attack.hitTargets.insert(actorID)
                continue
            case .apply(let effect):
                actor.hitPoints = max(0, actor.hitPoints - effect.damage)
                var combatState = actor.combatState
                combatState.invincibilityFramesRemaining = effect.invincibilityFrames
                combatState.lastReceivedElement = attack.element
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
                        element: attack.element,
                        direction: Vec3f(direction),
                        effect: effect
                    ),
                    playState: playState
                )
                attack.hitTargets.insert(actorID)
            }
        }

        activePlayerAttackState = attack
    }

    func resolveIncomingActorAttacks(playState: PlayState) {
        guard
            let playerState,
            playerInvincibilityFramesRemaining == 0
        else {
            return
        }

        let playerHurtbox = ColliderCylinder(
            center: playerState.position,
            radius: 16,
            height: 44
        )

        for actor in combatActors where actor.hitPoints > 0 {
            for attack in actor.activeAttacks {
                guard CombatCollisionResolver.intersects(attack.collider.shape, with: playerHurtbox) else {
                    continue
                }

                let direction = normalizedDirection(
                    from: actor.position.simd,
                    to: playerState.position.simd,
                    fallbackYaw: playerState.facingRadians
                )
                let hit = CombatHit(
                    source: .actor(
                        profileID: actor.profile.id,
                        actorType: String(describing: type(of: actor))
                    ),
                    element: attack.element,
                    direction: Vec3f(direction),
                    effect: attack.effect,
                    wasBlocked: shieldBlocksAttack(
                        attack,
                        actor: actor,
                        playerState: playerState
                    )
                )

                if hit.wasBlocked {
                    var combatState = actor.combatState
                    combatState.lastBlockedElement = attack.element
                    actor.combatState = combatState
                    actor.combatDidBlockHit(hit, playState: playState)
                    continue
                }

                inventoryState.currentHealthUnits = max(0, inventoryState.currentHealthUnits - attack.effect.damage)
                synchronizeHUDStateWithInventory()
                playerInvincibilityFramesRemaining = attack.effect.invincibilityFrames
                if var playerState = self.playerState {
                    playerState.position = Vec3f(
                        playerState.position.simd +
                            (direction * min(attack.effect.knockbackDistance, 12))
                    )
                    self.playerState = playerState
                }
                return
            }
        }
    }

    func shieldBlocksAttack(
        _ attack: CombatAttackDefinition,
        actor: any CombatActor,
        playerState: PlayerState
    ) -> Bool {
        guard shieldShouldBeRaised(for: controllerInputState) else {
            return false
        }

        let playerForward = SIMD2<Float>(
            sin(playerState.facingRadians),
            -cos(playerState.facingRadians)
        )
        let incomingOffset = SIMD2<Float>(
            actor.position.x - playerState.position.x,
            actor.position.z - playerState.position.z
        )
        guard simd_length_squared(incomingOffset) > 0.000_1 else {
            return true
        }

        let facingAlignment = simd_dot(playerForward, simd_normalize(incomingOffset))
        if attack.element.canBeBlockedAsProjectile || attack.isProjectile {
            return facingAlignment >= 0.1
        }
        return facingAlignment >= -0.05
    }

    func playerAttackCollider(
        for attack: ActivePlayerAttackState,
        playerState: PlayerState
    ) -> CombatCollider {
        let facing = SIMD3<Float>(
            sin(playerState.facingRadians),
            0,
            -cos(playerState.facingRadians)
        )
        let right = SIMD3<Float>(-facing.z, 0, facing.x)
        let base = playerState.position.simd

        switch attack.kind {
        case .spin:
            return CombatCollider(
                initialization: ColliderInit(collisionMask: [.at]),
                shape: .cylinder(
                    ColliderCylinder(
                        center: Vec3f(base),
                        radius: 56,
                        height: 44
                    )
                )
            )
        case .slash, .jump:
            let reach: Float = attack.kind == .jump ? 92 : 68
            let width: Float = attack.kind == .jump ? 34 : 26
            let forwardInset: Float = attack.kind == .jump ? 44 : 28
            let hand = Vec3f(base + facing * 18 + SIMD3<Float>(0, 22, 0))
            let left = Vec3f(base + facing * reach - right * width + SIMD3<Float>(0, 34, 0))
            let rightPoint = Vec3f(base + facing * reach + right * width + SIMD3<Float>(0, 16, 0))
            let lower = Vec3f(base + facing * forwardInset + SIMD3<Float>(0, 4, 0))

            return CombatCollider(
                initialization: ColliderInit(collisionMask: [.at]),
                shape: .tris(
                    ColliderTris(
                        triangles: [
                            ColliderTri(a: hand, b: left, c: rightPoint),
                            ColliderTri(a: hand, b: rightPoint, c: lower),
                        ]
                    )
                )
            )
        }
    }

    func normalizedPlanarVector(from offset: SIMD3<Float>) -> SIMD2<Float> {
        let planar = SIMD2<Float>(offset.x, offset.z)
        guard simd_length_squared(planar) > 0.000_1 else {
            return SIMD2<Float>(0, -1)
        }

        return simd_normalize(planar)
    }

    func normalizedDirection(
        from source: SIMD3<Float>,
        to target: SIMD3<Float>,
        fallbackYaw: Float
    ) -> SIMD3<Float> {
        let offset = target - source
        let planar = SIMD2<Float>(offset.x, offset.z)
        guard simd_length_squared(planar) > 0.000_1 else {
            return SIMD3<Float>(sin(fallbackYaw), 0, -cos(fallbackYaw))
        }

        let normalizedPlanar = simd_normalize(planar)
        return SIMD3<Float>(normalizedPlanar.x, 0, normalizedPlanar.y)
    }
}
