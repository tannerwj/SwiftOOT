import simd

struct SlingshotAimState: Sendable, Equatable {
    var yaw: Float
    var pitch: Float
}

struct EquippedDekuStickState: Sendable, Equatable {
    var isLit = false
    var burnFramesRemaining = 360
}

extension GameRuntime {
    public var availableChildCButtonItems: [GameplayUsableItem] {
        inventoryState.ownedChildAssignableItems
    }

    public func assignItem(
        _ item: GameplayUsableItem?,
        to button: GameplayCButton
    ) {
        inventoryState.assign(item, to: button)
        synchronizeHUDStateWithInventory()
        persistActiveSaveSlotState()
    }

    public func toggleCButtonItemEditor() {
        if isCButtonItemEditorPresented {
            isCButtonItemEditorPresented = false
            return
        }

        guard canPresentCButtonItemEditor else {
            return
        }

        isCButtonItemEditorPresented = true
    }

    public func setCButtonItemEditorPresented(_ isPresented: Bool) {
        guard isPresented else {
            isCButtonItemEditorPresented = false
            return
        }

        guard canPresentCButtonItemEditor else {
            return
        }

        isCButtonItemEditorPresented = true
    }

    public var itemAimYaw: Float? {
        activeSlingshotAimState?.yaw
    }

    public var itemAimPitch: Float? {
        activeSlingshotAimState?.pitch
    }

    var isGameplayItemAimActive: Bool {
        activeSlingshotAimState != nil
    }

    func updateGameplayItemState(currentInput: ControllerInputState) {
        updateSlingshotAimState(currentInput: currentInput)
        updateDekuStickState()
    }

    func handleGameplayItemButtons(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState
    ) {
        guard
            currentState == .gameplay,
            isGameplayPresentationActive == false,
            isCButtonItemEditorPresented == false
        else {
            return
        }

        if currentInput.cLeftPressed, previousInput.cLeftPressed == false {
            handleGameplayItemButton(.left)
        }
        if currentInput.cDownPressed, previousInput.cDownPressed == false {
            handleGameplayItemButton(.down)
        }
        if currentInput.cRightPressed, previousInput.cRightPressed == false {
            handleGameplayItemButton(.right)
        }
    }

    func resolvePlayerItemEffects(playState: PlayState) {
        let sceneActors = actors
        let combatActors = sceneActors.compactMap { $0 as? (any CombatActor) }

        for actor in sceneActors {
            guard let itemActor = actor as? any PlayerItemEffectResolvingActor else {
                continue
            }

            itemActor.resolveGameplayEffects(
                playState: playState,
                combatActors: combatActors,
                actors: sceneActors
            )
        }
    }
}

private extension GameRuntime {
    var canPresentCButtonItemEditor: Bool {
        guard currentState == .gameplay, availableChildCButtonItems.isEmpty == false else {
            return false
        }

        return itemGetSequence == nil && messageContext.isPresenting == false
    }

    func handleGameplayItemButton(_ button: GameplayCButton) {
        guard let item = inventoryState.cButtonLoadout[button] else {
            return
        }

        switch item {
        case .slingshot:
            toggleSlingshotAimOrFire()
        case .bombs:
            useBomb()
        case .boomerang:
            throwBoomerang()
        case .dekuStick:
            useDekuStick()
        case .dekuNut:
            throwDekuNut()
        case .ocarina, .bottle:
            return
        }
    }

    func toggleSlingshotAimOrFire() {
        guard let playerState else {
            return
        }

        if activeSlingshotAimState != nil {
            guard inventoryState.consume(.slingshot) else {
                activeSlingshotAimState = nil
                synchronizeHUDStateWithInventory()
                persistActiveSaveSlotState()
                return
            }

            let direction = aimedForwardVector(
                yaw: activeSlingshotAimState?.yaw ?? playerState.facingRadians,
                pitch: activeSlingshotAimState?.pitch ?? 0
            )
            spawnPlayerItemActor(
                SlingshotProjectileActor(
                    position: playerItemOrigin(using: direction),
                    direction: direction,
                    roomID: currentGameplayRoomID
                ),
                category: .item
            )
            activeSlingshotAimState = nil
            synchronizeHUDStateWithInventory()
            persistActiveSaveSlotState()
            return
        }

        guard inventoryState.canUse(.slingshot) else {
            return
        }

        activeSlingshotAimState = SlingshotAimState(
            yaw: playerState.facingRadians,
            pitch: 0
        )
    }

    func useBomb() {
        guard inventoryState.consume(.bombs), let playerState else {
            return
        }

        let throwSpeed: Float = controllerInputState.stick.isActive ? 6.5 : 1.5
        let direction = aimedForwardVector(yaw: playerState.facingRadians, pitch: 0)
        spawnPlayerItemActor(
            BombActor(
                position: playerItemOrigin(using: direction),
                velocity: direction * throwSpeed,
                roomID: currentGameplayRoomID
            ),
            category: .bomb
        )
        synchronizeHUDStateWithInventory()
        persistActiveSaveSlotState()
    }

    func throwBoomerang() {
        guard
            inventoryState.canUse(.boomerang),
            playerState != nil,
            actors.contains(where: { $0 is BoomerangActor }) == false
        else {
            return
        }

        let yaw = activeSlingshotAimState?.yaw ?? playerState?.facingRadians ?? 0
        let pitch = activeSlingshotAimState?.pitch ?? 0
        let direction = aimedForwardVector(yaw: yaw, pitch: pitch)
        spawnPlayerItemActor(
            BoomerangActor(
                position: playerItemOrigin(using: direction),
                direction: direction,
                roomID: currentGameplayRoomID
            ),
            category: .item
        )
    }

    func throwDekuNut() {
        guard inventoryState.consume(.dekuNut), let playerState else {
            return
        }

        let direction = aimedForwardVector(yaw: playerState.facingRadians, pitch: 0)
        spawnPlayerItemActor(
            DekuNutFlashActor(
                position: Vec3f(playerState.position.simd + direction * 26),
                roomID: currentGameplayRoomID
            ),
            category: .misc
        )
        synchronizeHUDStateWithInventory()
        persistActiveSaveSlotState()
    }

    func useDekuStick() {
        guard let playerState else {
            return
        }

        if activeDekuStickState == nil {
            guard inventoryState.consume(.dekuStick) else {
                return
            }
            activeDekuStickState = EquippedDekuStickState()
            synchronizeHUDStateWithInventory()
            persistActiveSaveSlotState()
        }

        let isLit = activeDekuStickState?.isLit ?? false
        spawnPlayerItemActor(
            DekuStickSwingActor(
                position: playerState.position,
                facingRadians: playerState.facingRadians,
                isLit: isLit,
                roomID: currentGameplayRoomID
            ),
            category: .item
        )
    }

    func updateSlingshotAimState(currentInput: ControllerInputState) {
        guard var aimState = activeSlingshotAimState else {
            return
        }

        aimState.yaw += currentInput.stick.x * 0.08
        aimState.pitch = max(-0.45, min(0.35, aimState.pitch + (currentInput.stick.y * 0.05)))
        activeSlingshotAimState = aimState

        if var playerState {
            playerState.facingRadians = aimState.yaw
            self.playerState = playerState
        }
    }

    func updateDekuStickState() {
        guard var stickState = activeDekuStickState, let playerState, let playState else {
            return
        }

        if stickState.isLit == false {
            for actor in actors {
                guard let fireSource = actor as? any FireSourceActor, fireSource.providesFireSource else {
                    continue
                }
                if simd_distance(actor.position.simd, playerState.position.simd) <= 48 {
                    stickState.isLit = true
                    break
                }
            }
        }

        if stickState.isLit {
            stickState.burnFramesRemaining -= 1
            for actor in actors {
                guard let ignitable = actor as? any FireInteractableActor else {
                    continue
                }
                if simd_distance(actor.position.simd, playerState.position.simd) <= 44 {
                    ignitable.ignite(playState: playState)
                }
            }
        }

        if stickState.burnFramesRemaining <= 0 {
            activeDekuStickState = nil
            synchronizeHUDStateWithInventory()
            return
        }

        activeDekuStickState = stickState
    }

    func spawnPlayerItemActor(
        _ actor: any Actor,
        category: ActorCategory
    ) {
        guard let playState else {
            return
        }

        playState.requestSpawn(
            actor,
            category: category,
            roomID: currentGameplayRoomID
        )
    }

    var currentGameplayRoomID: Int {
        playState?.currentRoomID ?? 0
    }

    func aimedForwardVector(
        yaw: Float,
        pitch: Float
    ) -> SIMD3<Float> {
        let horizontal = cos(pitch)
        return SIMD3<Float>(
            sin(yaw) * horizontal,
            sin(pitch),
            -cos(yaw) * horizontal
        )
    }

    func playerItemOrigin(using direction: SIMD3<Float>) -> Vec3f {
        let base = playerState?.position.simd ?? .zero
        return Vec3f(base + direction * 18 + SIMD3<Float>(0, 26, 0))
    }
}
