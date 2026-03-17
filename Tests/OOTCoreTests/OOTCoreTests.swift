import XCTest
import OOTContent
import OOTDataModel
import OOTTelemetry
@testable import OOTCore
import simd

final class OOTCoreTests: XCTestCase {
    func testTimeSystemAdvancesOneGameMinutePerRealSecond() {
        let timeSystem = TimeSystem()
        let updated = timeSystem.advance(
            GameTime(frameCount: 0, timeOfDay: 6.0),
            byRealSeconds: 1.0
        )

        XCTAssertEqual(updated.timeOfDay, 6.0 + (1.0 / 60.0), accuracy: 0.000_1)
    }

    @MainActor
    func testGameRuntimeDefaultTimeSystemAdvancesAtUsableSceneViewerRate() {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        runtime.advanceGameTime(byRealSeconds: 1.0)

        XCTAssertEqual(runtime.gameTime.timeOfDay, 6.0 + (0.1 / 60.0), accuracy: 0.000_1)
    }

    func testTimeSystemUsesExplicitSceneStartTimeWhenPresent() {
        let timeSystem = TimeSystem()
        let environment = SceneEnvironmentFile(
            sceneName: "market",
            time: SceneTimeSettings(hour: 14, minute: 30, timeSpeed: 0),
            skybox: SceneSkyboxSettings(
                skyboxID: 1,
                skyboxConfig: 0,
                environmentLightingMode: "LIGHT_MODE_TIME",
                skyboxDisabled: false,
                sunMoonDisabled: false
            ),
            lightSettings: []
        )

        XCTAssertEqual(try XCTUnwrap(timeSystem.initialTimeOfDay(for: environment)), 14.5, accuracy: 0.000_1)
    }

    func testGameRuntimeBootstrapsSpot04ByDefault() async {
        let runtime = await MainActor.run {
            GameRuntime(
                sceneLoader: MockSceneLoader(),
                telemetryPublisher: TelemetryPublisher(),
                suspender: { _ in }
            )
        }

        await runtime.bootstrapSceneViewer()

        await MainActor.run {
            XCTAssertEqual(runtime.sceneViewerState, .running)
            XCTAssertEqual(runtime.selectedSceneID, 0x55)
            XCTAssertEqual(runtime.availableScenes.map(\.index), [0x01, 0x55])
            XCTAssertEqual(runtime.loadedScene?.manifest.name, "spot04")
            XCTAssertEqual(
                runtime.textureAssetURLs[OOTAssetID.stableID(for: "gSpot04MainTex")]?.lastPathComponent,
                "gSpot04MainTex.tex.bin"
            )
        }
    }

    @MainActor
    func testGameRuntimeStartsWithBootStateAndRequiredProperties() {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        XCTAssertEqual(runtime.currentState, .boot)
        XCTAssertNil(runtime.playState)
        XCTAssertEqual(runtime.saveContext.slots.count, 3)
        XCTAssertFalse(runtime.canContinue)
        XCTAssertEqual(runtime.inputState.selectionIndex, 0)
        XCTAssertEqual(runtime.sceneViewerState, .idle)
    }

    @MainActor
    func testStartAdvancesFromBootToTitleScreen() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        await runtime.start()

        XCTAssertEqual(runtime.currentState, .titleScreen)
        XCTAssertEqual(runtime.gameTime.frameCount, 2)
    }

    @MainActor
    func testChoosingNewGameOpensFileSelectAndStartsGameplay() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()

        runtime.chooseTitleOption(.newGame)

        XCTAssertEqual(runtime.currentState, .fileSelect)
        XCTAssertEqual(runtime.fileSelectMode, .newGame)
        XCTAssertEqual(runtime.saveContext.selectedSlotIndex, 0)

        runtime.selectSaveSlot(2)
        runtime.confirmSelectedSaveSlot()

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .newGame)
        XCTAssertEqual(runtime.playState?.activeSaveSlot, 2)
        XCTAssertTrue(runtime.saveContext.slots[2].hasSaveData)
        XCTAssertEqual(runtime.hudState.currentHealthUnits, 6)
        XCTAssertEqual(runtime.hudState.maximumHealthUnits, 6)
        XCTAssertEqual(runtime.hudState.bButtonItem, .sword)
    }

    @MainActor
    func testPauseMenuTogglesFromStartInputAndCyclesSubscreens() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()
        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()

        runtime.setControllerInput(ControllerInputState(startPressed: true))
        runtime.updateFrame()

        XCTAssertTrue(runtime.isPauseMenuPresented)
        XCTAssertEqual(runtime.pauseMenuState.activeSubscreen, .items)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        runtime.setControllerInput(ControllerInputState(rPressed: true))
        runtime.updateFrame()
        XCTAssertEqual(runtime.pauseMenuState.activeSubscreen, .equipment)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        runtime.setControllerInput(ControllerInputState(lPressed: true))
        runtime.updateFrame()
        XCTAssertEqual(runtime.pauseMenuState.activeSubscreen, .items)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        runtime.setControllerInput(ControllerInputState(bPressed: true))
        runtime.updateFrame()
        XCTAssertFalse(runtime.isPauseMenuPresented)
    }

    @MainActor
    func testPauseMenuAssignsSelectedInventoryItemToCButtons() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()
        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()

        runtime.inventoryState = GameplayInventoryState(
            hasSlingshot: true,
            slingshotAmmo: 20,
            cButtonLoadout: GameplayCButtonLoadout()
        )
        runtime.pauseMenuState = PauseMenuState(
            isPresented: true,
            activeSubscreen: .items,
            itemCursor: PauseMenuCursor(row: 1, column: 0)
        )

        runtime.assignSelectedPauseMenuItem(to: .left)

        XCTAssertEqual(runtime.inventoryState.cButtonLoadout.left, .slingshot)
        XCTAssertEqual(runtime.hudState.cButtons.left.item, .slingshot)
        XCTAssertEqual(runtime.saveContext.slots[0].inventoryContext.gameplay.cButtonLoadout.left, .slingshot)
    }

    @MainActor
    func testPauseMenuEquipmentSelectionUpdatesEquippedGearAndHUDState() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()
        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()

        runtime.inventoryContext.equipment.ownedTunics = [.kokiri, .zora]
        runtime.inventoryContext.equipment.ownedBoots = [.kokiri, .hover]
        runtime.pauseMenuState = PauseMenuState(
            isPresented: true,
            activeSubscreen: .equipment,
            equipmentCursor: PauseMenuCursor(row: 0, column: 0)
        )

        runtime.activatePauseMenuSelection()
        XCTAssertNil(runtime.inventoryContext.equipment.equippedSword)
        XCTAssertEqual(runtime.hudState.bButtonItem, .none)

        runtime.pauseMenuState.equipmentCursor = PauseMenuCursor(row: 1, column: 0)
        runtime.activatePauseMenuSelection()
        XCTAssertEqual(runtime.inventoryContext.equipment.equippedSword, .masterSword)
        XCTAssertEqual(runtime.hudState.bButtonItem, .sword)

        runtime.pauseMenuState.equipmentCursor = PauseMenuCursor(row: 2, column: 2)
        runtime.activatePauseMenuSelection()
        XCTAssertEqual(runtime.inventoryContext.equipment.equippedTunic, .zora)

        runtime.pauseMenuState.equipmentCursor = PauseMenuCursor(row: 2, column: 3)
        runtime.activatePauseMenuSelection()
        XCTAssertEqual(runtime.inventoryContext.equipment.equippedBoots, .hover)
        XCTAssertEqual(runtime.saveContext.slots[0].inventoryContext.equipment.equippedBoots, .hover)
    }

    @MainActor
    func testDeveloperRuntimeStateSnapshotIncludesPauseAndInventoryContext() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()
        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()

        runtime.inventoryState = GameplayInventoryState(
            hasSlingshot: true,
            slingshotAmmo: 20,
            cButtonLoadout: GameplayCButtonLoadout(left: .slingshot)
        )
        runtime.pauseMenuState = PauseMenuState(
            isPresented: true,
            activeSubscreen: .questStatus,
            itemCursor: PauseMenuCursor(row: 1, column: 0),
            equipmentCursor: PauseMenuCursor(row: 2, column: 3)
        )
        runtime.inventoryContext.equipment.ownedBoots = [.kokiri, .hover]
        runtime.inventoryContext.equipment.equippedBoots = .hover
        runtime.synchronizeHUDStateWithInventory()

        let snapshot = runtime.developerRuntimeStateSnapshot()

        XCTAssertTrue(snapshot.inventoryContext.pauseMenu.isPresented)
        XCTAssertEqual(snapshot.inventoryContext.pauseMenu.activeSubscreen, .questStatus)
        XCTAssertEqual(snapshot.inventoryContext.gameplay.cButtonLoadout.left, .slingshot)
        XCTAssertEqual(snapshot.inventoryContext.equipment.equippedBoots, .hover)
        XCTAssertEqual(snapshot.hudState.cButtons.left.item, .slingshot)
    }

    @MainActor
    func testContinueWithoutSaveStaysOnTitleScreen() async {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()

        runtime.chooseTitleOption(.continueGame)

        XCTAssertEqual(runtime.currentState, .titleScreen)
        XCTAssertNil(runtime.fileSelectMode)
        XCTAssertEqual(runtime.statusMessage, "No saved games are available yet.")
    }

    @MainActor
    func testContinueUsesFirstOccupiedSaveSlot() async {
        let runtime = GameRuntime(
            saveContext: SaveContext(
                slots: [
                    .empty(id: 0),
                    SaveSlot(id: 1, playerName: "Link", locationName: "Hyrule Field", hearts: 4, hasSaveData: true),
                    .empty(id: 2),
                ]
            ),
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await runtime.start()

        runtime.chooseTitleOption(.continueGame)

        XCTAssertEqual(runtime.currentState, .fileSelect)
        XCTAssertEqual(runtime.fileSelectMode, .continueGame)
        XCTAssertEqual(runtime.saveContext.selectedSlotIndex, 1)

        runtime.confirmSelectedSaveSlot()

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .continueGame)
        XCTAssertEqual(runtime.playState?.currentSceneName, "Hyrule Field")
        XCTAssertEqual(runtime.hudState.currentHealthUnits, 8)
        XCTAssertEqual(runtime.hudState.maximumHealthUnits, 8)
    }

    func testSaveRepositoryRoundTripsVersionedSaveContext() throws {
        let fileURL = uniqueSaveFileURL()
        let repository = SaveRepository(fileURL: fileURL)
        let scene = SceneIdentity(id: 0x55, name: "spot04")
        let saveContext = SaveContext(
            slots: [
                SaveSlot(
                    id: 0,
                    playerName: "Link",
                    locationName: "Temple of Time",
                    hearts: 5,
                    hasSaveData: true,
                    inventoryContext: InventoryContext(
                        gameplay: GameplayInventoryState(
                            hasSlingshot: true,
                            slingshotAmmo: 20,
                            currentHealthUnits: 9,
                            maximumHealthUnits: 10
                        ),
                        equipment: EquipmentCollection(
                            ownedSwords: [.masterSword],
                            equippedSword: .masterSword,
                            ownedShields: [.hylianShield],
                            equippedShield: .hylianShield,
                            ownedTunics: [.kokiri],
                            equippedTunic: .kokiri,
                            ownedBoots: [.kokiri],
                            equippedBoots: .kokiri
                        ),
                        questStatus: QuestStatus(
                            medallions: [.forest],
                            stones: [.kokiriEmerald],
                            songs: [.zeldasLullaby]
                        )
                    ),
                    runtimeState: SaveRuntimeState(
                        currentMagic: 32,
                        maximumMagic: 64,
                        rupees: 99,
                        globalEventFlags: [1, 3, 5],
                        sceneEventFlags: [scene: [2, 4]],
                        spawnLocation: SaveSpawnLocation(
                            sceneID: scene.id,
                            sceneName: scene.name,
                            entranceIndex: 1,
                            spawnIndex: 2
                        ),
                        playTimeFrames: 7_260,
                        deathCount: 2,
                        goldSkulltulaFlags: [TreasureFlagKey(scene: scene, flag: 8)]
                    )
                ),
                .empty(id: 1),
                .empty(id: 2),
            ],
            selectedSlotIndex: 1
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try repository.save(saveContext)
        let reloadedContext = try XCTUnwrap(repository.loadSaveContextIfPresent())

        XCTAssertEqual(reloadedContext, saveContext)
    }

    func testSaveRepositoryRejectsChecksumMismatch() throws {
        let fileURL = uniqueSaveFileURL()
        let repository = SaveRepository(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try repository.save(
            SaveContext(
                slots: [
                    SaveSlot.starter(id: 0),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            )
        )

        let originalData = try Data(contentsOf: fileURL)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        envelope["checksum"] = String(repeating: "0", count: 64)
        let corruptedData = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        try corruptedData.write(to: fileURL, options: .atomic)

        XCTAssertThrowsError(try repository.loadSaveContextIfPresent()) { error in
            guard case SaveRepository.Error.checksumMismatch = error else {
                return XCTFail("Expected checksum mismatch, got \(error)")
            }
        }
    }

    @MainActor
    func testPauseMenuSaveShortcutPersistsActiveSaveSlot() throws {
        let fileURL = uniqueSaveFileURL()
        let repository = SaveRepository(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let runtime = GameRuntime(
            currentState: .gameplay,
            playState: PlayState(
                activeSaveSlot: 0,
                entryMode: .continueGame,
                currentSceneName: "Kokiri Forest",
                currentSceneID: 0x55,
                currentEntranceIndex: 3,
                currentSpawnIndex: 1,
                playerName: "Link"
            ),
            saveContext: SaveContext(
                slots: [
                    SaveSlot.starter(id: 0),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            hudState: GameplayHUDState(
                currentHealthUnits: 5,
                maximumHealthUnits: 6,
                currentMagic: 24,
                maximumMagic: 48,
                rupees: 77
            ),
            inventoryContext: InventoryContext(
                gameplay: GameplayInventoryState(
                    hasSlingshot: true,
                    slingshotAmmo: 15,
                    currentHealthUnits: 5,
                    maximumHealthUnits: 6
                ),
                questStatus: QuestStatus(
                    songs: [.zeldasLullaby]
                ),
                pauseMenu: PauseMenuState(
                    isPresented: true,
                    activeSubscreen: .items
                )
            ),
            sceneLoader: MockSceneLoader(),
            saveRepository: repository,
            suspender: { _ in }
        )
        runtime.globalEventFlags = [7]
        runtime.sceneEventFlags = [SceneIdentity(id: 0x55, name: "Kokiri Forest"): [9]]
        runtime.deathCount = 4
        runtime.goldSkulltulaFlags = [TreasureFlagKey(scene: SceneIdentity(id: 0x55, name: "Kokiri Forest"), flag: 12)]

        runtime.setControllerInput(ControllerInputState(zPressed: true))
        runtime.updateFrame()

        let persistedContext = try XCTUnwrap(repository.loadSaveContextIfPresent())
        let slot = persistedContext.slots[0]
        XCTAssertEqual(slot.runtimeState.rupees, 77)
        XCTAssertEqual(slot.runtimeState.currentMagic, 24)
        XCTAssertEqual(slot.runtimeState.spawnLocation.sceneID, 0x55)
        XCTAssertEqual(slot.runtimeState.spawnLocation.entranceIndex, 3)
        XCTAssertEqual(slot.runtimeState.spawnLocation.spawnIndex, 1)
        XCTAssertEqual(slot.runtimeState.deathCount, 4)
        XCTAssertEqual(slot.runtimeState.globalEventFlags, [7])
        XCTAssertEqual(slot.runtimeState.sceneEventFlags[SceneIdentity(id: 0x55, name: "Kokiri Forest")], [9])
        XCTAssertEqual(slot.runtimeState.goldSkulltulaFlags.count, 1)
        XCTAssertEqual(runtime.statusMessage, "Saved File 1.")
    }

    @MainActor
    func testSceneTransitionAutoSavePersistsUpdatedScenePreview() throws {
        let fileURL = uniqueSaveFileURL()
        let repository = SaveRepository(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let kokiriScene = makeScene(sceneID: 0x55, sceneName: "spot04", roomSpawns: [0: []])
        let kakarikoScene = makeScene(sceneID: 0x01, sceneName: "spot01", roomSpawns: [0: []])
        let contentLoader = MockContentLoader(
            scenesByID: [
                0x55: kokiriScene,
                0x01: kakarikoScene,
            ],
            actorTable: []
        )
        let sceneLoader = ConfigurableSceneLoader(
            sceneEntries: [
                SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
                SceneTableEntry(index: 0x01, segmentName: "spot01_scene", enumName: "SCENE_KAKARIKO_VILLAGE"),
            ],
            scenesByID: [
                0x55: kokiriScene,
                0x01: kakarikoScene,
            ]
        )
        let runtime = GameRuntime(
            currentState: .gameplay,
            playState: PlayState(
                activeSaveSlot: 0,
                entryMode: .continueGame,
                currentSceneName: "spot04",
                currentSceneID: 0x55,
                playerName: "Link"
            ),
            saveContext: SaveContext(
                slots: [
                    SaveSlot.starter(id: 0),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            saveRepository: repository,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        try runtime.loadScene(id: 0x01)

        let persistedContext = try XCTUnwrap(repository.loadSaveContextIfPresent())
        XCTAssertEqual(persistedContext.slots[0].locationName, "spot01")
        XCTAssertEqual(persistedContext.slots[0].runtimeState.spawnLocation.sceneID, 0x01)
    }

    @MainActor
    func testSaveFlowReloadsSlotFromRepositoryAfterRelaunch() async throws {
        let fileURL = uniqueSaveFileURL()
        let repository = SaveRepository(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let scene = makeScene(sceneID: 0x55, sceneName: "spot04", roomSpawns: [0: []])
        let contentLoader = MockContentLoader(
            scenesByID: [0x55: scene],
            actorTable: []
        )
        let sceneLoader = ConfigurableSceneLoader(
            sceneEntries: [
                SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
            ],
            scenesByID: [0x55: scene]
        )

        let runtime = GameRuntime(
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            saveRepository: repository,
            suspender: { _ in }
        )
        await runtime.start()
        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()
        try runtime.loadScene(id: 0x55)
        runtime.hudState.rupees = 123
        runtime.hudState.currentMagic = 20
        runtime.pauseMenuState = PauseMenuState(isPresented: true, activeSubscreen: .items)
        runtime.setControllerInput(ControllerInputState(zPressed: true))
        runtime.updateFrame()

        let persistedContext = try XCTUnwrap(repository.loadSaveContextIfPresent())
        let reloadedRuntime = GameRuntime(
            saveContext: persistedContext,
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            saveRepository: repository,
            suspender: { _ in }
        )
        await reloadedRuntime.start()
        reloadedRuntime.chooseTitleOption(.continueGame)
        reloadedRuntime.confirmSelectedSaveSlot()

        XCTAssertEqual(reloadedRuntime.currentState, .gameplay)
        XCTAssertEqual(reloadedRuntime.fileSelectMode, nil)
        XCTAssertEqual(reloadedRuntime.hudState.rupees, 123)
        XCTAssertEqual(reloadedRuntime.hudState.currentMagic, 20)
        XCTAssertEqual(reloadedRuntime.playState?.currentSceneID, 0x55)
    }

    @MainActor
    func testGameplayHUDActionLabelFallsBackToHUDButtonAction() {
        let runtime = GameRuntime(
            hudState: GameplayHUDState(
                bButtonItem: .bomb,
                actionLabelOverride: "Lift"
            ),
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        XCTAssertEqual(runtime.gameplayHUDActionLabel, "Lift")
    }

    func testMessageContextRevealsPlayerNameDelayAndChoices() {
        var context = MessageContext(
            catalog: MessageCatalog(
                messageList: [
                    MessageDefinition(
                        id: 0x1000,
                        variant: .blue,
                        segments: [
                            .text("Hello "),
                            .playerName,
                            .delay(2),
                            .color(.yellow),
                            .text("!"),
                            .choice([
                                MessageChoiceOption(title: "Yes"),
                                MessageChoiceOption(title: "No"),
                            ]),
                        ]
                    ),
                ]
            )
        )

        context.enqueue(messageID: 0x1000, playerName: "Link")
        XCTAssertEqual(context.phase, .opening)

        for _ in 0..<6 {
            context.tick(playerName: "Link")
        }

        XCTAssertEqual(context.phase, .displaying)

        for _ in 0..<64 where context.phase != .waitingForChoice {
            context.tick(playerName: "Link")
        }

        XCTAssertEqual(
            context.activePresentation?.textRuns,
            [
                MessageTextRun(text: "Hello Link", color: .white),
                MessageTextRun(text: "!", color: .yellow),
            ]
        )
        XCTAssertEqual(context.phase, .waitingForChoice)
        XCTAssertEqual(context.activePresentation?.choiceState?.options.map(\.title), ["Yes", "No"])

        context.moveSelection(delta: 1)
        XCTAssertEqual(context.activePresentation?.choiceState?.selectedIndex, 1)

        context.advanceOrConfirm(playerName: "Link")
        XCTAssertEqual(context.phase, .closing)
    }

    func testCollisionSystemFindsFloorAndCeiling() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        let floor = system.findFloor(at: SIMD3<Float>(2, 4, 2))
        let ceiling = system.checkCeiling(at: SIMD3<Float>(2, 4, 2))

        XCTAssertNotNil(floor)
        XCTAssertNotNil(ceiling)
        XCTAssertEqual(Double(floor!.floorY), 0, accuracy: 0.001)
        XCTAssertEqual(floor?.polygon.surfaceType?.floorType, 4)
        XCTAssertEqual(Double(ceiling!.ceilingY), 8, accuracy: 0.001)
        XCTAssertEqual(ceiling?.polygon.surfaceType?.canHookshot, true)
    }

    func testCollisionSystemPushesSphereOutOfWall() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        let hit = system.checkWall(
            at: SIMD3<Float>(4.2, 2, 5),
            radius: 0.5,
            displacement: SIMD3<Float>(1, 0, 0)
        )

        XCTAssertNotNil(hit)
        XCTAssertLessThan(hit!.displacement.x, 0)
        XCTAssertEqual(hit?.polygon.surfaceType?.wallType, 7)
    }

    func testCollisionSystemReportsLineOcclusion() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])

        XCTAssertTrue(
            system.checkLineOcclusion(
                from: SIMD3<Float>(2, 2, 5),
                to: SIMD3<Float>(8, 2, 5)
            )
        )
        XCTAssertFalse(
            system.checkLineOcclusion(
                from: SIMD3<Float>(2, 9, 5),
                to: SIMD3<Float>(8, 9, 5)
            )
        )
    }

    func testPlayerStateTransitionsBetweenIdleWalkRunAndUpdatesFacing() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])
        let configuration = PlayerMovementConfiguration(
            walkSpeed: 1,
            runSpeed: 1.5,
            floorProbeHeight: 4,
            collisionRadius: 0.5
        )
        let initialState = PlayerState(
            position: Vec3f(x: 2, y: 0, z: 8),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            locomotionState: .idle,
            animationState: PlayerAnimationState(),
            floorHeight: 0
        )

        let walking = initialState.updating(
            input: ControllerInputState(stick: StickInput(x: 0, y: 0.5)),
            movementReferenceYaw: nil,
            collisionSystem: system,
            configuration: configuration
        )
        XCTAssertEqual(walking.locomotionState, .walking)
        XCTAssertEqual(walking.animationState.currentClip, .walk)
        XCTAssertEqual(Double(walking.facingRadians), 0, accuracy: 0.001)

        let running = initialState.updating(
            input: ControllerInputState(stick: StickInput(x: 1, y: 0)),
            movementReferenceYaw: nil,
            collisionSystem: system,
            configuration: configuration
        )
        XCTAssertEqual(running.locomotionState, .running)
        XCTAssertEqual(running.animationState.currentClip, .run)
        XCTAssertEqual(Double(running.facingRadians), Double.pi / 2, accuracy: 0.001)
    }

    func testPlayerStateMovesRelativeToFacingDirection() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])
        let configuration = PlayerMovementConfiguration(
            walkSpeed: 1,
            runSpeed: 1.5,
            floorProbeHeight: 4,
            collisionRadius: 0.5
        )
        let initialState = PlayerState(
            position: Vec3f(x: 2, y: 0, z: 8),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: .pi / 2,
            isGrounded: true,
            locomotionState: .idle,
            animationState: PlayerAnimationState(),
            floorHeight: 0
        )

        let movedForward = initialState.updating(
            input: ControllerInputState(stick: StickInput(x: 0, y: 1)),
            movementReferenceYaw: nil,
            collisionSystem: system,
            configuration: configuration
        )

        XCTAssertGreaterThan(movedForward.position.x, initialState.position.x)
        XCTAssertEqual(Double(movedForward.position.z), Double(initialState.position.z), accuracy: 0.001)
        XCTAssertEqual(Double(movedForward.facingRadians), Double.pi / 2, accuracy: 0.001)
    }

    func testPlayerStateSnapsToNearbyFloorAndFallsWithoutSupport() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])
        let configuration = PlayerMovementConfiguration()

        let nearFloor = PlayerState(
            position: Vec3f(x: 2, y: 4, z: 2),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: false,
            locomotionState: .falling,
            animationState: PlayerAnimationState(currentClip: .idle),
            floorHeight: nil
        )
        let snapped = nearFloor.updating(
            input: ControllerInputState(),
            movementReferenceYaw: nil,
            collisionSystem: system,
            configuration: configuration
        )
        XCTAssertTrue(snapped.isGrounded)
        XCTAssertEqual(Double(snapped.position.y), 0, accuracy: 0.001)
        XCTAssertEqual(snapped.locomotionState, .idle)

        let unsupported = PlayerState(
            position: Vec3f(x: 20, y: 20, z: 20),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: false,
            locomotionState: .falling,
            animationState: PlayerAnimationState(currentClip: .idle),
            floorHeight: nil
        )
        let falling = unsupported.updating(
            input: ControllerInputState(),
            movementReferenceYaw: nil,
            collisionSystem: system,
            configuration: configuration
        )
        XCTAssertFalse(falling.isGrounded)
        XCTAssertEqual(falling.locomotionState, .falling)
        XCTAssertLessThan(falling.position.y, unsupported.position.y)
    }

    func testPlayerStateUsesMovementReferenceYawWhenProvided() {
        let system = CollisionSystem(staticMeshes: [fixtureCollisionMesh()])
        let configuration = PlayerMovementConfiguration(
            walkSpeed: 1,
            runSpeed: 1.5,
            floorProbeHeight: 4,
            collisionRadius: 0.5
        )
        let initialState = PlayerState(
            position: Vec3f(x: 2, y: 0, z: 8),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            locomotionState: .idle,
            animationState: PlayerAnimationState(),
            floorHeight: 0
        )

        let movedForward = initialState.updating(
            input: ControllerInputState(stick: StickInput(x: 0, y: 1)),
            movementReferenceYaw: .pi / 2,
            collisionSystem: system,
            configuration: configuration
        )

        XCTAssertGreaterThan(movedForward.position.x, initialState.position.x)
        XCTAssertEqual(Double(movedForward.position.z), Double(initialState.position.z), accuracy: 0.001)
        XCTAssertEqual(Double(movedForward.facingRadians), Double.pi / 2, accuracy: 0.001)
    }

    @MainActor
    func testLoadSceneSpawnsBaselineActorsUsingDefaultRegistry() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_EN_KO"),
                        makeSpawn(id: 2, name: "ACTOR_DOOR_SHUTTER"),
                        makeSpawn(id: 3, name: "ACTOR_EN_KANBAN"),
                        makeSpawn(id: 4, name: "ACTOR_OBJ_HANA"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_EN_KO", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_DOOR_SHUTTER", category: .door),
                makeActorTableEntry(id: 3, name: "ACTOR_EN_KANBAN", category: .prop),
                makeActorTableEntry(id: 4, name: "ACTOR_OBJ_HANA", category: .prop),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [0])
        XCTAssertEqual(
            runtime.actors.map { String(describing: type(of: $0)) },
            [
                "KokiriChildActor",
                "SignActor",
                "GenericPropActor",
                "DoorActor",
            ]
        )
    }

    @MainActor
    func testLoadScenePublishesXRayTelemetrySnapshotForSceneAndActorState() throws {
        let collision = CollisionMesh(
            vertices: [
                Vector3s(x: -16, y: 0, z: -16),
                Vector3s(x: 16, y: 0, z: -16),
                Vector3s(x: 0, y: 0, z: 16),
            ],
            polygons: [
                CollisionPoly(
                    surfaceType: 0,
                    vertexA: 0,
                    vertexB: 1,
                    vertexC: 2,
                    normal: Vector3s(x: 0, y: 0x7FFF, z: 0),
                    distance: 0
                )
            ],
            surfaceTypes: [
                CollisionSurfaceType(low: 0, high: 0)
            ],
            bgCameras: [
                CollisionBgCamera(
                    setting: 0,
                    count: 1,
                    cameraData: CollisionBgCameraData(
                        position: Vector3s(x: 0, y: 40, z: 80),
                        rotation: Vector3s(x: 0, y: 0, z: 0),
                        fov: 60,
                        parameter: 0,
                        unknown: 0
                    )
                )
            ],
            waterBoxes: [
                CollisionWaterBox(
                    xMin: -12,
                    ySurface: 6,
                    zMin: -12,
                    xLength: 24,
                    zLength: 24,
                    properties: 0
                )
            ]
        )
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: 1,
                            name: "ACTOR_EN_KO",
                            position: Vector3s(x: 12, y: 0, z: -18)
                        )
                    ]
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    )
                ],
                transitionTriggers: [
                    SceneTransitionTrigger(
                        id: 7,
                        kind: .loadingZone,
                        roomID: 0,
                        destinationRoomID: 1,
                        effect: .fade,
                        volume: SceneTriggerVolume(
                            minimum: Vector3s(x: -4, y: 0, z: -4),
                            maximum: Vector3s(x: 4, y: 12, z: 4)
                        )
                    )
                ],
                cutsceneTriggers: [
                    SceneCutsceneTrigger(
                        id: 3,
                        roomID: 0,
                        actorName: "ACTOR_EN_OKARINA_TAG",
                        params: 0x1BFF,
                        kind: "ocarinaTag",
                        volume: SceneCylinderTriggerVolume(
                            center: Vector3s(x: 24, y: 14, z: -18),
                            radius: 530,
                            minimumY: -66,
                            maximumY: 94
                        )
                    )
                ],
                eventRegionTriggers: [
                    SceneEventRegionTrigger(
                        id: 4,
                        roomID: 0,
                        actorName: "ACTOR_EN_WEATHER_TAG",
                        params: 0x0607,
                        kind: "thunderstormGraveyard",
                        volume: SceneCylinderTriggerVolume(
                            center: Vector3s(x: -16, y: 8, z: 22),
                            radius: 600
                        )
                    )
                ],
                collision: collision,
                paths: [
                    ScenePathDefinition(
                        index: 0,
                        pointsName: "path_0",
                        points: [
                            Vector3s(x: -8, y: 0, z: 0),
                            Vector3s(x: 8, y: 0, z: 0),
                        ]
                    )
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_EN_KO", category: .npc)
            ]
        )
        let publisher = TelemetryPublisher()
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            telemetryPublisher: publisher,
            suspender: { _ in }
        )

        XCTAssertNil(runtime.xrayTelemetrySnapshot)

        try runtime.loadScene(id: 0x55)

        let snapshot = try XCTUnwrap(runtime.xrayTelemetrySnapshot)
        let scene = try XCTUnwrap(snapshot.scene)

        XCTAssertEqual(scene.collisionPolygons.count, 1)
        XCTAssertEqual(scene.collisionPolygons.first?.kind, .walkable)
        XCTAssertEqual(scene.bgCameras.count, 1)
        XCTAssertEqual(scene.waterBoxes.count, 1)
        XCTAssertEqual(scene.paths.count, 1)
        XCTAssertEqual(scene.triggerVolumes.count, 3)
        XCTAssertEqual(scene.spawnPoints.count, 1)
        XCTAssertEqual(scene.actorSpawns.count, 1)
        XCTAssertEqual(scene.triggerVolumes[0].source, .transition)
        XCTAssertEqual(scene.triggerVolumes[1].source, .cutscene)
        XCTAssertEqual(scene.triggerVolumes[1].cylinder, XRayCylinder(center: XRayVector3(x: 24, y: -66, z: -18), radius: 530, height: 160))
        XCTAssertEqual(scene.triggerVolumes[2].source, .eventRegion)
        XCTAssertEqual(scene.triggerVolumes[2].kind, "thunderstormGraveyard")
        XCTAssertEqual(scene.triggerVolumes[2].cylinder, XRayCylinder(center: XRayVector3(x: -16, y: -192, z: 22), radius: 600, height: 400))

        let playerSnapshot = try XCTUnwrap(snapshot.activeActors.first { $0.category == "player" })
        XCTAssertNotNil(playerSnapshot.boundsCollider)
        XCTAssertNotNil(playerSnapshot.bodyCollider)

        let npcSnapshot = try XCTUnwrap(snapshot.activeActors.first { $0.profileID == 1 })
        XCTAssertEqual(npcSnapshot.category, "npc")
        XCTAssertEqual(npcSnapshot.position, XRayVector3(x: 12, y: 0, z: -18))
        XCTAssertEqual(npcSnapshot.spawnPosition, XRayVector3(x: 12, y: 0, z: -18))

        XCTAssertEqual(publisher.xraySnapshot, snapshot)
    }

    @MainActor
    func testLoadSceneSpawnsGenericNPCActorsUsingDefaultRegistry() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_EN_HY"),
                        makeSpawn(id: 2, name: "ACTOR_EN_HEISHI2"),
                    ],
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_EN_HY", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_EN_HEISHI2", category: .npc),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(
            runtime.actors.map { String(describing: type(of: $0)) },
            [
                "GenericNPCActor",
                "GenericNPCActor",
            ]
        )
    }

    @MainActor
    func testLoadSceneSpawnsDekuTreeActorsUsingDefaultRegistry() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_OBJ_SWITCH", position: Vector3s(x: 0, y: 0, z: -24)),
                        makeSpawn(id: 20, name: "ACTOR_BG_YDAN_SP", position: Vector3s(x: 20, y: 0, z: -24)),
                        makeSpawn(id: 30, name: "ACTOR_EN_HINTNUTS", position: Vector3s(x: -20, y: 0, z: -24)),
                        makeSpawn(id: 40, name: "ACTOR_OBJ_SYOKUDAI", position: Vector3s(x: 40, y: 0, z: -24)),
                        makeSpawn(id: 50, name: "ACTOR_OBJ_OSHIHIKI", position: Vector3s(x: 60, y: 0, z: -24)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_OBJ_SWITCH", category: .switchActor),
                makeActorTableEntry(id: 20, name: "ACTOR_BG_YDAN_SP", category: .bg),
                makeActorTableEntry(id: 30, name: "ACTOR_EN_HINTNUTS", category: .enemy),
                makeActorTableEntry(id: 40, name: "ACTOR_OBJ_SYOKUDAI", category: .prop),
                makeActorTableEntry(id: 50, name: "ACTOR_OBJ_OSHIHIKI", category: .prop),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(
            runtime.actors.map { String(describing: type(of: $0)) },
            [
                "DungeonSwitchActor",
                "BurnableWebActor",
                "DekuScrubActor",
                "TorchActor",
                "PushableBlockActor",
            ]
        )
    }

    @MainActor
    func testContinueResolvesDungeonSceneNameFromSceneTable() async throws {
        let dungeonScene = makeScene(
            sceneID: 0x00,
            sceneName: "ydan",
            roomSpawns: [0: []],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 0, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                ),
            ]
        )
        let fixture = RuntimeFixture(scene: dungeonScene, actorTable: [])
        let sceneLoader = ConfigurableSceneLoader(
            sceneEntries: [
                SceneTableEntry(index: 0x00, segmentName: "ydan_scene", enumName: "SCENE_DEKU_TREE"),
            ],
            scenesByID: [0x00: dungeonScene]
        )
        let runtime = makeRuntime(
            saveContext: SaveContext(
                slots: [
                    SaveSlot(
                        id: 0,
                        playerName: "Link",
                        locationName: "ydan",
                        hearts: 3,
                        hasSaveData: true
                    ),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            contentLoader: fixture.contentLoader,
            sceneLoader: sceneLoader,
            suspender: { _ in }
        )

        await runtime.start()
        runtime.chooseTitleOption(.continueGame)
        runtime.confirmSelectedSaveSlot()

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.currentSceneID, 0x00)
        XCTAssertEqual(runtime.loadedScene?.manifest.name, "ydan")
    }

    @MainActor
    func testDungeonSwitchPersistsPressedStateAcrossReload() throws {
        let switchActorID = 10
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: switchActorID,
                            name: "ACTOR_OBJ_SWITCH",
                            position: Vector3s(x: 0, y: 0, z: -36)
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: switchActorID, name: "ACTOR_OBJ_SWITCH", category: .switchActor),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        XCTAssertEqual(runtime.gameplayActionLabel, "Press")

        runtime.handlePrimaryGameplayInput()

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)
    }

    @MainActor
    func testBurnableWebPersistsDestroyedStateAcrossReload() throws {
        let webActorID = 10
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: webActorID,
                            name: "ACTOR_BG_YDAN_SP",
                            position: Vector3s(x: 0, y: 0, z: -36)
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: webActorID, name: "ACTOR_BG_YDAN_SP", category: .bg),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        runtime.inventoryState.dekuStickCount = 1
        XCTAssertEqual(runtime.gameplayActionLabel, "Burn")

        runtime.handlePrimaryGameplayInput()
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertEqual(runtime.actors.count, 0)

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertEqual(runtime.actors.count, 0)
        XCTAssertNil(runtime.gameplayActionLabel)
    }

    @MainActor
    func testTorchPersistsLitStateAcrossReload() throws {
        let torchActorID = 10
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: torchActorID,
                            name: "ACTOR_OBJ_SYOKUDAI",
                            position: Vector3s(x: 0, y: 0, z: -36)
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: torchActorID, name: "ACTOR_OBJ_SYOKUDAI", category: .prop),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        runtime.inventoryState.dekuStickCount = 1
        XCTAssertEqual(runtime.gameplayActionLabel, "Light")

        runtime.handlePrimaryGameplayInput()

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)
    }

    @MainActor
    func testPushableBlockPersistsMovedStateAcrossReload() throws {
        let blockActorID = 10
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: blockActorID,
                            name: "ACTOR_OBJ_OSHIHIKI",
                            position: Vector3s(x: 0, y: 0, z: -36)
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: blockActorID, name: "ACTOR_OBJ_OSHIHIKI", category: .prop),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        let initialPosition = try XCTUnwrap((runtime.actors.first as? PushableBlockActor)?.position)
        XCTAssertEqual(runtime.gameplayActionLabel, "Push")

        runtime.handlePrimaryGameplayInput()

        let movedPosition = try XCTUnwrap((runtime.actors.first as? PushableBlockActor)?.position)
        XCTAssertNotEqual(movedPosition, initialPosition)
        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)

        try runtime.loadScene(id: 0x55)

        let reloadedPosition = try XCTUnwrap((runtime.actors.first as? PushableBlockActor)?.position)
        XCTAssertNotEqual(reloadedPosition, initialPosition)
        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertNil(runtime.gameplayActionLabel)
    }

    @MainActor
    func testAutomaticDoorTriggerTransitionsWhenPlayerIsNearDoorPoint() throws {
        let scene = makeScene(
            roomSpawns: [
                0: [],
                1: [],
            ],
            entrances: [SceneEntranceDefinition(index: 0, spawnIndex: 0)],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 0, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                ),
            ],
            transitionTriggers: [
                SceneTransitionTrigger(
                    id: 77,
                    kind: .door,
                    roomID: 0,
                    destinationRoomID: 1,
                    effect: .fade,
                    volume: SceneTriggerVolume(
                        minimum: Vector3s(x: 0, y: 0, z: 0),
                        maximum: Vector3s(x: 0, y: 0, z: 0)
                    )
                ),
            ]
        )
        let fixture = RuntimeFixture(scene: scene, actorTable: [])
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.updateFrame()

        XCTAssertEqual(runtime.playState?.currentRoomID, 1)
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [0, 1])
    }

    @MainActor
    func testDekuScrubProjectileCanBeBlockedAndDefeatPersistsAcrossReload() throws {
        let scrubActorID = 10
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: scrubActorID,
                            name: "ACTOR_EN_HINTNUTS",
                            position: Vector3s(x: 0, y: 0, z: -40),
                            rotation: Vector3s(x: 0, y: Int16.min, z: 0)
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: scrubActorID, name: "ACTOR_EN_HINTNUTS", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        let scrub = try XCTUnwrap(runtime.actors.first as? DekuScrubActor)
        let playState = try XCTUnwrap(runtime.playState)

        scrub.combatDidBlockHit(
            CombatHit(
                source: .player,
                element: .projectile,
                direction: Vec3f(x: 0, y: 0, z: 1),
                effect: DamageEffect(damage: 0, knockbackDistance: 0),
                wasBlocked: true
            ),
            playState: playState
        )
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertEqual(runtime.actors.count, 0)

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertEqual(runtime.actors.count, 0)
    }

    @MainActor
    func testUpdateCycleRespectsCategoryOrderAndDestroysActorsOnce() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "switch",
                recorder: recorder
            ) { actor, playState in
                playState.requestDestroy(actor)
            }
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "npc",
                recorder: recorder
            ) { actor, _ in
                actor.hitPoints = 0
            }
        }
        registry.register(actorID: 30) {
            RecordingActor(
                spawnRecord: $0,
                label: "door",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_SWITCH_TEST"),
                        makeSpawn(id: 20, name: "ACTOR_NPC_TEST"),
                        makeSpawn(id: 30, name: "ACTOR_DOOR_TEST"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_SWITCH_TEST", category: .switchActor),
                makeActorTableEntry(id: 20, name: "ACTOR_NPC_TEST", category: .npc),
                makeActorTableEntry(id: 30, name: "ACTOR_DOOR_TEST", category: .door),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        recorder.reset()

        runtime.updateFrame()

        XCTAssertEqual(
            recorder.events,
            [
                "update:switch",
                "destroy:switch",
                "update:npc",
                "destroy:npc",
                "update:door",
            ]
        )
        XCTAssertEqual(runtime.actors.count, 1)
    }

    @MainActor
    func testChangingActiveRoomsDespawnsLeavingActorsAndSpawnsNewRoomActors() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "room0",
                recorder: recorder
            )
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "room1",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [makeSpawn(id: 10, name: "ACTOR_ROOM0_TEST")],
                    1: [makeSpawn(id: 20, name: "ACTOR_ROOM1_TEST")],
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_ROOM0_TEST", category: .npc),
                makeActorTableEntry(id: 20, name: "ACTOR_ROOM1_TEST", category: .npc),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        XCTAssertEqual(recorder.events, ["init:room0"])

        runtime.setActiveRooms([1])

        XCTAssertEqual(
            recorder.events,
            [
                "init:room0",
                "destroy:room0",
                "init:room1",
            ]
        )
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [1])
        XCTAssertEqual(runtime.actors.count, 1)
    }

    @MainActor
    func testLoadSceneResolvesEntranceToSpawnRoomAndObjectSlots() throws {
        let scene = makeScene(
            roomSpawns: [
                0: [makeSpawn(id: 10, name: "ACTOR_ROOM0_TEST")],
                1: [makeSpawn(id: 20, name: "ACTOR_ROOM1_TEST")],
            ],
            sceneObjectIDs: [100, 101],
            roomObjectIDs: [0: [200], 1: [300]],
            entrances: [SceneEntranceDefinition(index: 5, spawnIndex: 1)],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 0, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                ),
                SceneSpawnPoint(
                    index: 1,
                    roomID: 1,
                    position: Vector3s(x: 10, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0x4000, z: 0)
                ),
            ]
        )
        let fixture = RuntimeFixture(
            scene: scene,
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_ROOM0_TEST", category: .npc, objectID: 210),
                makeActorTableEntry(id: 20, name: "ACTOR_ROOM1_TEST", category: .npc, objectID: 310),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55, entranceIndex: 5)

        XCTAssertEqual(runtime.playState?.currentSceneID, 0x55)
        XCTAssertEqual(runtime.playState?.currentEntranceIndex, 5)
        XCTAssertEqual(runtime.playState?.currentSpawnIndex, 1)
        XCTAssertEqual(runtime.playState?.currentRoomID, 1)
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [1])
        XCTAssertEqual(runtime.playState?.loadedObjectIDs, [100, 101, 300, 310])
        XCTAssertFalse(runtime.playState?.objectSlotOverflow ?? true)
    }

    @MainActor
    func testLoadScenePrefersExplicitSpawnOverrideOverEntranceSpawn() throws {
        let scene = makeScene(
            roomSpawns: [
                0: [],
                1: [],
            ],
            entrances: [SceneEntranceDefinition(index: 5, spawnIndex: 0)],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 10, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                ),
                SceneSpawnPoint(
                    index: 1,
                    roomID: 1,
                    position: Vector3s(x: 40, y: 0, z: -20),
                    rotation: Vector3s(x: 0, y: 0x4000, z: 0)
                ),
            ]
        )
        let fixture = RuntimeFixture(scene: scene, actorTable: [])
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55, entranceIndex: 5, spawnIndex: 1)

        XCTAssertEqual(runtime.playState?.currentEntranceIndex, 5)
        XCTAssertEqual(runtime.playState?.currentSpawnIndex, 1)
        XCTAssertEqual(runtime.playState?.currentRoomID, 1)
        XCTAssertEqual(runtime.playerState?.position, Vec3f(x: 40, y: 0, z: -20))
        XCTAssertEqual(Double(try XCTUnwrap(runtime.playerState?.facingRadians)), .pi / 2, accuracy: 0.000_1)
    }

    @MainActor
    func testLaunchDeveloperSceneResolvesSceneNameAndLocksTimeOfDay() async throws {
        let runtime = GameRuntime(
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try await runtime.launchDeveloperScene(
            DeveloperSceneLaunchConfiguration(
                scene: .name("spot01"),
                fixedTimeOfDay: 18.25
            )
        )

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.currentSceneID, 0x01)
        XCTAssertEqual(runtime.playState?.currentSceneName, "spot01")
        XCTAssertEqual(runtime.gameTime.timeOfDay, 18.25, accuracy: 0.000_1)

        runtime.updateFrame()
        XCTAssertEqual(runtime.gameTime.timeOfDay, 18.25, accuracy: 0.000_1)

        runtime.advanceGameTime(byRealSeconds: 5)
        XCTAssertEqual(runtime.gameTime.timeOfDay, 18.25, accuracy: 0.000_1)
    }

    @MainActor
    func testDoorTransitionKeepsAtMostTwoRoomsActiveAndReloadsObjects() throws {
        let scene = makeScene(
            roomSpawns: [
                0: [makeSpawn(id: 10, name: "ACTOR_ROOM0_TEST")],
                1: [makeSpawn(id: 20, name: "ACTOR_ROOM1_TEST")],
            ],
            sceneObjectIDs: [100],
            roomObjectIDs: [0: [200], 1: [300]],
            transitionTriggers: [
                SceneTransitionTrigger(
                    id: 77,
                    kind: .door,
                    roomID: 0,
                    destinationRoomID: 1,
                    effect: .circleIris,
                    volume: SceneTriggerVolume(
                        minimum: Vector3s(x: 0, y: 0, z: 0),
                        maximum: Vector3s(x: 10, y: 10, z: 10)
                    )
                )
            ]
        )
        let fixture = RuntimeFixture(
            scene: scene,
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_ROOM0_TEST", category: .npc, objectID: 210),
                makeActorTableEntry(id: 20, name: "ACTOR_ROOM1_TEST", category: .npc, objectID: 310),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        try runtime.activateDoorTransition(id: 77)

        XCTAssertEqual(runtime.playState?.currentRoomID, 1)
        XCTAssertEqual(runtime.playState?.activeRoomIDs, [0, 1])
        XCTAssertEqual(runtime.playState?.loadedObjectIDs, [100, 200, 210, 300, 310])
        XCTAssertEqual(runtime.playState?.transitionEffect, .circleIris)
    }

    @MainActor
    func testLoadingZoneTransitionsToDestinationSceneUsingEntranceTable() throws {
        let sourceScene = makeScene(
            sceneID: 0x55,
            sceneName: "source_scene",
            roomSpawns: [0: [makeSpawn(id: 10, name: "ACTOR_SOURCE_TEST")]],
            entrances: [SceneEntranceDefinition(index: 5, spawnIndex: 0)],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 0, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                )
            ],
            transitionTriggers: [
                SceneTransitionTrigger(
                    id: 88,
                    kind: .loadingZone,
                    roomID: 0,
                    exitIndex: 0,
                    effect: .wipe,
                    volume: SceneTriggerVolume(
                        minimum: Vector3s(x: -5, y: -5, z: -5),
                        maximum: Vector3s(x: 5, y: 5, z: 5)
                    )
                )
            ],
            exits: [
                SceneExitDefinition(index: 0, entranceIndex: 9, entranceName: "ENTR_DEST_0")
            ]
        )
        let destinationScene = makeScene(
            sceneID: 0x66,
            sceneName: "destination_scene",
            roomSpawns: [2: [makeSpawn(id: 20, name: "ACTOR_DEST_TEST")]],
            entrances: [SceneEntranceDefinition(index: 9, spawnIndex: 1)],
            spawns: [
                SceneSpawnPoint(
                    index: 1,
                    roomID: 2,
                    position: Vector3s(x: 50, y: 0, z: 0),
                    rotation: Vector3s(x: 0, y: 0x2000, z: 0)
                )
            ]
        )
        let contentLoader = MockContentLoader(
            scenesByID: [
                0x55: sourceScene,
                0x66: destinationScene,
            ],
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_SOURCE_TEST", category: .npc, objectID: 210),
                makeActorTableEntry(id: 20, name: "ACTOR_DEST_TEST", category: .npc, objectID: 310),
            ],
            entranceTable: [
                EntranceTableEntry(
                    index: 9,
                    name: "ENTR_DEST_0",
                    sceneID: 0x66,
                    spawnIndex: 1,
                    continueBGM: false,
                    displayTitleCard: true,
                    transitionIn: .fade,
                    transitionOut: .fade
                )
            ]
        )
        let runtime = makeRuntime(
            contentLoader: contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55, entranceIndex: 5)
        try runtime.evaluateLoadingZone(at: Vector3s(x: 0, y: 0, z: 0))

        XCTAssertEqual(runtime.playState?.currentSceneID, 0x66)
        XCTAssertEqual(runtime.playState?.currentEntranceIndex, 9)
        XCTAssertEqual(runtime.playState?.currentRoomID, 2)
        XCTAssertEqual(runtime.playState?.transitionEffect, .wipe)
    }

    @MainActor
    func testLoadSceneUsesResolvedSpawnPointToPlacePlayerOnGroundWhenNoPlayerActorExists() throws {
        let scene = makeScene(
            roomSpawns: [0: []],
            entrances: [SceneEntranceDefinition(index: 5, spawnIndex: 1)],
            spawns: [
                SceneSpawnPoint(
                    index: 0,
                    roomID: 0,
                    position: Vector3s(x: 1, y: 99, z: 1),
                    rotation: Vector3s(x: 0, y: 0, z: 0)
                ),
                SceneSpawnPoint(
                    index: 1,
                    roomID: 0,
                    position: Vector3s(x: 8, y: 99, z: 2),
                    rotation: Vector3s(x: 0, y: 0x2000, z: 0)
                ),
            ],
            collision: fixtureCollisionMesh()
        )
        let fixture = RuntimeFixture(scene: scene, actorTable: [])
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55, entranceIndex: 5)

        let playerState = try XCTUnwrap(runtime.playerState)

        XCTAssertEqual(runtime.playState?.currentSpawnIndex, 1)
        XCTAssertEqual(playerState.position.x, 8, accuracy: 0.001)
        XCTAssertEqual(playerState.position.z, 2, accuracy: 0.001)
        XCTAssertEqual(playerState.position.y, 0, accuracy: 0.001)
        XCTAssertTrue(playerState.isGrounded)
        XCTAssertEqual(playerState.locomotionState, .idle)
        XCTAssertEqual(playerState.facingRadians, .pi / 4, accuracy: 0.001)
    }

    @MainActor
    func testSceneManagerCapsLoadedObjectSlotsAtNineteen() throws {
        let scene = makeScene(
            roomSpawns: [0: []],
            sceneObjectIDs: Array(1...25)
        )
        let fixture = RuntimeFixture(scene: scene, actorTable: [])
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.playState?.loadedObjectIDs.count, 19)
        XCTAssertTrue(runtime.playState?.objectSlotOverflow ?? false)
    }

    func testPrimaryGameplayInputRequestsDialogueFromTalkActor() async throws {
        try await MainActor.run {
            let fixture = RuntimeFixture(
                scene: makeScene(
                    roomSpawns: [
                        0: [
                            makeSpawn(id: 1, name: "ACTOR_EN_KO", params: 0x1000),
                        ],
                    ]
                ),
                actorTable: [
                    makeActorTableEntry(id: 1, name: "ACTOR_EN_KO", category: .npc),
                ],
                messageCatalog: MessageCatalog(
                    messageList: [
                        MessageDefinition(
                            id: 0x1000,
                            variant: .white,
                            segments: [.text("Welcome to Kokiri Forest.") ]
                        ),
                    ]
                )
            )
            let runtime = GameRuntime(
                contentLoader: fixture.contentLoader,
                sceneLoader: MockSceneLoader(),
                suspender: { _ in }
            )

            try runtime.loadScene(id: 0x55)
            runtime.handlePrimaryGameplayInput()

            XCTAssertEqual(runtime.activeMessagePresentation?.messageID, 0x1000)
            XCTAssertEqual(runtime.gameplayActionLabel, "Next")
        }
    }

    func testPrimaryGameplayInputRequestsDialogueFromGenericNPCActor() async throws {
        try await MainActor.run {
            let fixture = RuntimeFixture(
                scene: makeScene(
                    roomSpawns: [
                        0: [
                            makeSpawn(id: 1, name: "ACTOR_EN_HY", params: 0x1000),
                        ],
                    ]
                ),
                actorTable: [
                    makeActorTableEntry(id: 1, name: "ACTOR_EN_HY", category: .npc),
                ],
                messageCatalog: MessageCatalog(
                    messageList: [
                        MessageDefinition(
                            id: 0x1000,
                            variant: .white,
                            segments: [.text("Welcome to Castle Town.")]
                        ),
                    ]
                )
            )
            let runtime = GameRuntime(
                contentLoader: fixture.contentLoader,
                sceneLoader: MockSceneLoader(),
                suspender: { _ in }
            )

            try runtime.loadScene(id: 0x55)

            XCTAssertEqual(runtime.gameplayActionLabel, "Talk")

            runtime.handlePrimaryGameplayInput()

            XCTAssertEqual(runtime.activeMessagePresentation?.messageID, 0x1000)
            XCTAssertEqual(runtime.gameplayActionLabel, "Next")
        }
    }

    @MainActor
    func testGameplayActionLabelIsNilWhenTalkActorsAreOutOfRangeOrBehindPlayer() throws {
        var registry = ActorRegistry()
        registry.register(actorID: 1) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "Behind",
                messageID: 0x1000
            )
        }
        registry.register(actorID: 2) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "Far",
                messageID: 0x1001
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_TALK_BEHIND", position: Vector3s(x: 0, y: 0, z: 60)),
                        makeSpawn(id: 2, name: "ACTOR_TALK_FAR", position: Vector3s(x: 0, y: 0, z: -180)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_TALK_BEHIND", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_TALK_FAR", category: .npc),
            ],
            messageCatalog: MessageCatalog(
                messageList: [
                    MessageDefinition(id: 0x1000, variant: .white, segments: [.text("Behind")]),
                    MessageDefinition(id: 0x1001, variant: .white, segments: [.text("Far")]),
                ]
            )
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertNil(runtime.gameplayActionLabel)

        runtime.handlePrimaryGameplayInput()

        XCTAssertNil(runtime.activeMessagePresentation)
    }

    @MainActor
    func testPrimaryGameplayInputTargetsNearestTalkActorInsteadOfSpawnOrder() throws {
        var registry = ActorRegistry()
        registry.register(actorID: 1) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "Far",
                messageID: 0x1000
            )
        }
        registry.register(actorID: 2) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "Near",
                messageID: 0x1001
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_TALK_FAR", position: Vector3s(x: 0, y: 0, z: -110)),
                        makeSpawn(id: 2, name: "ACTOR_TALK_NEAR", position: Vector3s(x: 0, y: 0, z: -50)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_TALK_FAR", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_TALK_NEAR", category: .npc),
            ],
            messageCatalog: MessageCatalog(
                messageList: [
                    MessageDefinition(id: 0x1000, variant: .white, segments: [.text("Far")]),
                    MessageDefinition(id: 0x1001, variant: .white, segments: [.text("Near")]),
                ]
            )
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.gameplayActionLabel, "Near")

        runtime.handlePrimaryGameplayInput()

        XCTAssertEqual(runtime.activeMessagePresentation?.messageID, 0x1001)
        XCTAssertEqual(runtime.gameplayActionLabel, "Next")
    }

    @MainActor
    func testTalkTargetingBreaksPerfectTiesBySpawnOrder() throws {
        var registry = ActorRegistry()
        registry.register(actorID: 1) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "First",
                messageID: 0x1000
            )
        }
        registry.register(actorID: 2) {
            TestTalkActor(
                spawnRecord: $0,
                prompt: "Second",
                messageID: 0x1001
            )
        }

        let tiePosition = Vector3s(x: 0, y: 0, z: -40)
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 1, name: "ACTOR_TALK_FIRST", position: tiePosition),
                        makeSpawn(id: 2, name: "ACTOR_TALK_SECOND", position: tiePosition),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 1, name: "ACTOR_TALK_FIRST", category: .npc),
                makeActorTableEntry(id: 2, name: "ACTOR_TALK_SECOND", category: .npc),
            ],
            messageCatalog: MessageCatalog(
                messageList: [
                    MessageDefinition(id: 0x1000, variant: .white, segments: [.text("First")]),
                    MessageDefinition(id: 0x1001, variant: .white, segments: [.text("Second")]),
                ]
            )
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.gameplayActionLabel, "First")

        runtime.handlePrimaryGameplayInput()

        XCTAssertEqual(runtime.activeMessagePresentation?.messageID, 0x1000)
    }

    @MainActor
    func testZTargetingLocksOntoNearestActorEnablesStrafingAndSwitchesTargets() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(
                spawnRecord: $0,
                label: "left",
                recorder: recorder
            )
        }
        registry.register(actorID: 20) {
            TestCombatActor(
                spawnRecord: $0,
                label: "right",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_COMBAT_LEFT", position: Vector3s(x: -18, y: 0, z: -56)),
                        makeSpawn(id: 20, name: "ACTOR_COMBAT_RIGHT", position: Vector3s(x: 52, y: 0, z: -60)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_COMBAT_LEFT", category: .enemy),
                makeActorTableEntry(id: 20, name: "ACTOR_COMBAT_RIGHT", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        runtime.setControllerInput(ControllerInputState(zPressed: true))
        runtime.updateFrame()
        runtime.updateFrame()

        XCTAssertEqual(runtime.combatState.lockOnTarget?.actorID, 10)
        XCTAssertEqual(runtime.combatState.lockOnTarget?.actorType, "TestCombatActor")
        XCTAssertEqual(runtime.playerState?.isStrafing, true)

        runtime.setControllerInput(
            ControllerInputState(
                stick: StickInput(x: 1, y: 0),
                zPressed: true
            )
        )
        runtime.updateFrame()

        XCTAssertEqual(runtime.combatState.lockOnTarget?.actorID, 20)
        XCTAssertEqual(runtime.playerState?.isStrafing, true)
    }

    @MainActor
    func testSwordCombatAppliesDamageKnockbackAndActorInvincibilityFrames() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(
                spawnRecord: $0,
                label: "enemy",
                recorder: recorder,
                combatProfile: ActorCombatProfile(
                    hurtboxRadius: 18,
                    hurtboxHeight: 44,
                    targetAnchorHeight: 44,
                    targetingRange: 240,
                    damageTable: DamageTable(
                        defaultEffect: DamageEffect(damage: 0, knockbackDistance: 0),
                        overrides: [
                            .swordSlash: DamageEffect(damage: 1, knockbackDistance: 24, invincibilityFrames: 12),
                        ]
                    )
                )
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_COMBAT_ENEMY", position: Vector3s(x: 0, y: 0, z: -40)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_COMBAT_ENEMY", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        runtime.setControllerInput(ControllerInputState(bPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        XCTAssertEqual(runtime.combatState.activeAttack?.kind, .slash)

        for _ in 0..<6 {
            runtime.updateFrame()
        }

        let actor = try XCTUnwrap(runtime.actors.first as? TestCombatActor)
        XCTAssertEqual(actor.hitPoints, 2)
        XCTAssertEqual(actor.combatState.lastReceivedElement, .swordSlash)
        XCTAssertEqual(actor.combatState.lastReceivedDamage, 1)
        XCTAssertLessThan(actor.position.z, -40)
        XCTAssertTrue(recorder.events.contains("hit:enemy:swordSlash:1"))

        runtime.setControllerInput(ControllerInputState(bPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()
        for _ in 0..<6 {
            runtime.updateFrame()
        }

        XCTAssertEqual(actor.hitPoints, 2)
    }

    @MainActor
    func testDefaultRegistrySpawnsConcreteDekuTreeEnemyActors() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_EN_DEKUBABA", position: Vector3s(x: -40, y: 0, z: -60)),
                        makeSpawn(id: 20, name: "ACTOR_EN_SW", position: Vector3s(x: 0, y: 80, z: -80)),
                        makeSpawn(id: 30, name: "ACTOR_BOSS_GOMA", position: Vector3s(x: 40, y: 120, z: -120)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_EN_DEKUBABA", category: .enemy),
                makeActorTableEntry(id: 20, name: "ACTOR_EN_SW", category: .npc),
                makeActorTableEntry(id: 30, name: "ACTOR_BOSS_GOMA", category: .boss),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertTrue(runtime.actors.contains { $0 is DekuBabaActor })
        XCTAssertTrue(runtime.actors.contains { $0 is SkulltulaActor })
        XCTAssertTrue(runtime.actors.contains { $0 is QueenGohmaActor })
    }

    @MainActor
    func testDekuBabaStunsThenGrantsStickRewardWhenFinishedDuringStunWindow() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_EN_DEKUBABA", position: Vector3s(x: 0, y: 0, z: -48)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_EN_DEKUBABA", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        for _ in 0..<4 {
            runtime.updateFrame()
        }

        let playState = try XCTUnwrap(runtime.playState)
        let baba = try XCTUnwrap(runtime.actors.first(where: { $0 is DekuBabaActor }) as? DekuBabaActor)
        XCTAssertEqual(baba.state, .lunging)
        let firstHit = CombatHit(
            source: .player,
            element: .swordSlash,
            direction: Vec3f(x: 0, y: 0, z: -1),
            effect: DamageEffect(damage: 1, knockbackDistance: 12)
        )
        XCTAssertEqual(
            baba.combatHitResolution(
                for: firstHit,
                attackerPosition: Vec3f(x: 0, y: 0, z: 0),
                playState: playState
            ),
            .ignore
        )
        for _ in 0..<1 {
            runtime.updateFrame()
        }

        XCTAssertEqual(baba.state, .stunned)
        XCTAssertEqual(runtime.inventoryState.dekuStickCount, 0)

        baba.hitPoints = 1
        applyPlayerHit(
            to: baba,
            element: .swordSlash,
            attackerPosition: Vec3f(x: 0, y: 0, z: 0),
            playState: playState
        )
        for _ in 0..<24 {
            runtime.updateFrame()
        }

        XCTAssertEqual(runtime.inventoryState.dekuStickCount, 1)
        XCTAssertFalse(runtime.actors.contains { $0 is DekuBabaActor })
    }

    @MainActor
    func testGoldSkulltulaDropsWhenApproachedBlocksFrontHitsAndAwardsTokenFromBehind() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: 10,
                            name: "ACTOR_EN_SW",
                            position: Vector3s(x: 0, y: 96, z: -56),
                            params: Int16(bitPattern: UInt16(1 << 13))
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_EN_SW", category: .npc),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        var skulltula = try XCTUnwrap(runtime.actors.first(where: { $0 is SkulltulaActor }) as? SkulltulaActor)
        XCTAssertEqual(skulltula.state, .hanging)

        for _ in 0..<24 {
            runtime.updateFrame()
        }

        skulltula = try XCTUnwrap(runtime.actors.first(where: { $0 is SkulltulaActor }) as? SkulltulaActor)
        XCTAssertEqual(skulltula.state, .grounded)
        runtime.updateFrame()

        let playState = try XCTUnwrap(runtime.playState)
        let frontHit = CombatHit(
            source: .player,
            element: .swordSlash,
            direction: Vec3f(x: 0, y: 0, z: -1),
            effect: DamageEffect(damage: 1, knockbackDistance: 12)
        )
        XCTAssertEqual(
            skulltula.combatHitResolution(
                for: frontHit,
                attackerPosition: Vec3f(x: 0, y: 0, z: 0),
                playState: playState
            ),
            .block
        )
        XCTAssertEqual(skulltula.hitPoints, 2)

        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: -86),
            facingRadians: .pi,
            isGrounded: true,
            floorHeight: 0
        )

        applyPlayerHit(
            to: skulltula,
            element: .swordSlash,
            attackerPosition: Vec3f(x: 0, y: 0, z: -86),
            playState: playState
        )
        applyPlayerHit(
            to: skulltula,
            element: .swordJump,
            attackerPosition: Vec3f(x: 0, y: 0, z: -86),
            playState: playState
        )
        for _ in 0..<28 {
            runtime.updateFrame()
        }

        XCTAssertEqual(runtime.inventoryState.goldSkulltulaTokenCount, 1)
        XCTAssertFalse(runtime.actors.contains { $0 is SkulltulaActor })
    }

    @MainActor
    func testQueenGohmaSpawnsLarvaTransitionsToGroundAndAwardsHeartContainer() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_BOSS_GOMA", position: Vector3s(x: 0, y: 120, z: -72)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_BOSS_GOMA", category: .boss),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        for _ in 0..<80 {
            runtime.updateFrame()
        }

        let gohma = try XCTUnwrap(runtime.actors.first(where: { $0 is QueenGohmaActor }) as? QueenGohmaActor)
        XCTAssertEqual(gohma.spawnedLarvaCount, 3)
        XCTAssertEqual(runtime.actors.filter { $0 is GohmaLarvaActor }.count, 3)

        for _ in 0..<80 where gohma.state != .floorStunned {
            runtime.updateFrame()
        }

        XCTAssertEqual(gohma.state, .floorStunned)
        gohma.hitPoints = 1

        applyPlayerHit(
            to: gohma,
            element: .swordJump,
            attackerPosition: Vec3f(x: 0, y: 0, z: 0),
            playState: try XCTUnwrap(runtime.playState)
        )
        for _ in 0..<96 {
            runtime.updateFrame()
        }

        XCTAssertEqual(runtime.inventoryState.maximumHealthUnits, 8)
        XCTAssertFalse(runtime.actors.contains { $0 is QueenGohmaActor })
    }

    @MainActor
    func testJumpAndSpinAttacksPublishExpectedAttackKinds() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(
                spawnRecord: $0,
                label: "enemy",
                recorder: recorder
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_COMBAT_ENEMY", position: Vector3s(x: 0, y: 0, z: -48)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_COMBAT_ENEMY", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.setControllerInput(
            ControllerInputState(
                stick: StickInput(x: 0, y: 1),
                aPressed: true
            )
        )
        runtime.updateFrame()

        XCTAssertEqual(runtime.combatState.activeAttack?.kind, .jump)

        for _ in 0..<20 {
            runtime.updateFrame()
        }

        runtime.setControllerInput(ControllerInputState(bPressed: true))
        for _ in 0..<18 {
            runtime.updateFrame()
        }
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        XCTAssertEqual(runtime.combatState.activeAttack?.kind, .spin)
    }

    @MainActor
    func testShieldBlocksProjectileAttacksWhenNoTargetIsLocked() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(
                spawnRecord: $0,
                label: "projectile",
                recorder: recorder,
                targetable: false,
                attackBuilder: { actor in
                    [
                        CombatAttackDefinition(
                            collider: CombatCollider(
                                initialization: ColliderInit(collisionMask: [.at]),
                                shape: .cylinder(
                                    ColliderCylinder(
                                        center: Vec3f(x: 0, y: 0, z: 0),
                                        radius: 24,
                                        height: 44
                                    )
                                )
                            ),
                            element: .projectile,
                            effect: DamageEffect(damage: 1, knockbackDistance: 12, invincibilityFrames: 8),
                            isProjectile: true
                        ),
                    ]
                }
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_PROJECTILE_TEST", position: Vector3s(x: 0, y: 0, z: -24)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_PROJECTILE_TEST", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        runtime.setControllerInput(ControllerInputState(zPressed: true))
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.currentHealthUnits, 6)
        XCTAssertEqual(runtime.combatState.shieldRaised, true)
        XCTAssertTrue(recorder.events.contains("block:projectile:projectile"))

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.currentHealthUnits, 5)
    }

    @MainActor
    func testSlingshotEntersAimModeAndDamagesEnemyWhenFiredFromCButton() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(spawnRecord: $0, label: "slingshot-target", recorder: recorder)
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_SLINGSHOT_TARGET", position: Vector3s(x: 0, y: 0, z: -72)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_SLINGSHOT_TARGET", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )
        runtime.inventoryState = GameplayInventoryState(
            hasSlingshot: true,
            slingshotAmmo: 6,
            cButtonLoadout: GameplayCButtonLoadout(left: .slingshot)
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.setControllerInput(ControllerInputState(cLeftPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        XCTAssertNotNil(runtime.activeSlingshotAimState)

        runtime.setControllerInput(ControllerInputState(cLeftPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())

        for _ in 0..<8 {
            runtime.updateFrame()
        }

        XCTAssertNil(runtime.activeSlingshotAimState)
        XCTAssertEqual(runtime.inventoryState.slingshotAmmo, 5)
        XCTAssertTrue(recorder.events.contains("hit:slingshot-target:projectile:1"))
    }

    @MainActor
    func testBombExplosionDamagesEnemyAndTriggersNearbyBombChainReaction() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            TestCombatActor(spawnRecord: $0, label: "bomb-target", recorder: recorder)
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_BOMB_TARGET", position: Vector3s(x: 0, y: 0, z: -40)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_BOMB_TARGET", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )
        runtime.inventoryState = GameplayInventoryState(
            hasBombBag: true,
            bombCount: 2,
            cButtonLoadout: GameplayCButtonLoadout(down: .bombs)
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.playState?.requestSpawn(
            BombActor(
                position: Vec3f(x: 0, y: 0, z: -36),
                velocity: SIMD3<Float>(0, 0, 0),
                roomID: 0
            ),
            category: .bomb,
            roomID: 0
        )
        runtime.playState?.requestSpawn(
            BombActor(
                position: Vec3f(x: 12, y: 0, z: -44),
                velocity: SIMD3<Float>(0, 0, 0),
                roomID: 0
            ),
            category: .bomb,
            roomID: 0
        )

        runtime.setControllerInput(ControllerInputState(cDownPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())

        for _ in 0..<60 {
            runtime.updateFrame()
        }

        XCTAssertEqual(runtime.inventoryState.bombCount, 1)
        XCTAssertTrue(recorder.events.contains { $0 == "hit:bomb-target:explosion:2" })
        XCTAssertFalse(runtime.actors.contains { $0 is BombActor })
    }

    @MainActor
    func testBoomerangStunsEnemyAndReturnsToPlayer() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_EN_DEKUBABA", position: Vector3s(x: 0, y: 0, z: -48)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_EN_DEKUBABA", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        runtime.inventoryState = GameplayInventoryState(
            hasBoomerang: true,
            cButtonLoadout: GameplayCButtonLoadout(right: .boomerang)
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.setControllerInput(ControllerInputState(cRightPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())

        for _ in 0..<28 {
            runtime.updateFrame()
        }

        let baba = try XCTUnwrap(runtime.actors.first(where: { $0 is DekuBabaActor }) as? DekuBabaActor)
        XCTAssertEqual(baba.state, .stunned)
        XCTAssertFalse(runtime.actors.contains { $0 is BoomerangActor })
    }

    @MainActor
    func testDekuStickLightsFromTorchAndBurnsWeb() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_OBJ_SYOKUDAI", position: Vector3s(x: 0, y: 0, z: -20)),
                        makeSpawn(id: 20, name: "ACTOR_BG_YDAN_SP", position: Vector3s(x: 0, y: 0, z: -76)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_OBJ_SYOKUDAI", category: .prop),
                makeActorTableEntry(id: 20, name: "ACTOR_BG_YDAN_SP", category: .bg),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        runtime.inventoryState = GameplayInventoryState(
            dekuStickCount: 1,
            cButtonLoadout: GameplayCButtonLoadout(left: .dekuStick)
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: -18),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.setControllerInput(ControllerInputState(cLeftPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.dekuStickCount, 0)
        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 1)
        XCTAssertTrue(runtime.activeDekuStickState?.isLit == true)

        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: -74),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.triggeredDungeonEventFlags.count, 2)
        XCTAssertFalse(runtime.actors.contains { $0 is BurnableWebActor })
    }

    @MainActor
    func testDekuNutFlashStunsAllEnemiesInRange() throws {
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_EN_DEKUBABA", position: Vector3s(x: -24, y: 0, z: -48)),
                        makeSpawn(id: 20, name: "ACTOR_EN_DEKUBABA", position: Vector3s(x: 24, y: 0, z: -48)),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ],
                collision: fixtureCollisionMesh()
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_EN_DEKUBABA", category: .enemy),
                makeActorTableEntry(id: 20, name: "ACTOR_EN_DEKUBABA", category: .enemy),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        runtime.inventoryState = GameplayInventoryState(
            dekuNutCount: 3,
            cButtonLoadout: GameplayCButtonLoadout(down: .dekuNut)
        )

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )

        runtime.setControllerInput(ControllerInputState(cDownPressed: true))
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()

        let babaStates = runtime.actors.compactMap { ($0 as? DekuBabaActor)?.state }
        XCTAssertEqual(babaStates.count, 2)
        XCTAssertTrue(babaStates.allSatisfy { $0 == .stunned })
        XCTAssertEqual(runtime.inventoryState.dekuNutCount, 2)
    }

    @MainActor
    func testCButtonItemEditorTogglesWithStartAndBlocksGameplayItemUse() throws {
        let inventory = GameplayInventoryState(
            hasBombBag: true,
            bombCount: 2,
            cButtonLoadout: GameplayCButtonLoadout(down: .bombs)
        )
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: []
        )
        let runtime = makeRuntime(
            saveContext: SaveContext(
                slots: [
                    SaveSlot(
                        id: 0,
                        playerName: "Link",
                        locationName: "Kokiri Forest",
                        hearts: 3,
                        hasSaveData: true,
                        inventoryState: inventory
                    ),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        runtime.inventoryState = inventory

        try runtime.loadScene(id: 0x55)
        runtime.playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0,
            isGrounded: true,
            floorHeight: 0
        )
        runtime.synchronizeHUDStateWithInventory()

        runtime.toggleCButtonItemEditor()

        XCTAssertTrue(runtime.isCButtonItemEditorPresented)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState(cDownPressed: true))
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.bombCount, 2)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()
        runtime.toggleCButtonItemEditor()

        XCTAssertFalse(runtime.isCButtonItemEditorPresented)

        runtime.setControllerInput(ControllerInputState())
        runtime.updateFrame()
        runtime.setControllerInput(ControllerInputState(cDownPressed: true))
        runtime.updateFrame()

        XCTAssertEqual(runtime.inventoryState.bombCount, 1)
        XCTAssertEqual(runtime.saveContext.slots[0].inventoryState.bombCount, 1)
    }

    @MainActor
    func testAssigningCButtonItemUpdatesHUDAndPersistsAcrossContinueGame() async {
        let inventory = GameplayInventoryState(
            hasSlingshot: true,
            slingshotAmmo: 30,
            hasBombBag: true,
            bombCount: 10,
            hasBoomerang: true,
            dekuNutCount: 7,
            dekuStickCount: 4,
            cButtonLoadout: GameplayCButtonLoadout(
                left: .slingshot,
                down: .bombs,
                right: .boomerang
            )
        )
        let runtime = GameRuntime(
            currentState: .gameplay,
            playState: PlayState(
                activeSaveSlot: 0,
                entryMode: .newGame,
                currentSceneName: "Kokiri Forest",
                playerName: "Link"
            ),
            saveContext: SaveContext(
                slots: [
                    SaveSlot(
                        id: 0,
                        playerName: "Link",
                        locationName: "Kokiri Forest",
                        hearts: 3,
                        hasSaveData: true,
                        inventoryState: inventory
                    ),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            inventoryState: inventory,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        runtime.synchronizeHUDStateWithInventory()

        XCTAssertEqual(
            runtime.availableChildCButtonItems,
            [
                GameplayUsableItem.slingshot,
                GameplayUsableItem.bombs,
                GameplayUsableItem.boomerang,
                GameplayUsableItem.dekuStick,
                GameplayUsableItem.dekuNut,
            ]
        )

        runtime.assignItem(GameplayUsableItem.dekuNut, to: GameplayCButton.left)

        XCTAssertEqual(runtime.inventoryState.cButtonLoadout.left, GameplayUsableItem.dekuNut)
        XCTAssertEqual(runtime.hudState.cButtons.left.item, GameplayHUDButtonItem.dekuNut)
        XCTAssertEqual(runtime.hudState.cButtons.left.ammoCount, 7)
        XCTAssertEqual(
            runtime.saveContext.slots[0].inventoryState.cButtonLoadout.left,
            GameplayUsableItem.dekuNut
        )

        runtime.assignItem(GameplayUsableItem.dekuStick, to: GameplayCButton.right)

        XCTAssertEqual(runtime.inventoryState.cButtonLoadout.right, GameplayUsableItem.dekuStick)
        XCTAssertEqual(
            runtime.saveContext.slots[0].inventoryState.cButtonLoadout.right,
            GameplayUsableItem.dekuStick
        )

        let reloadedRuntime = GameRuntime(
            saveContext: runtime.saveContext,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        await reloadedRuntime.start()
        reloadedRuntime.chooseTitleOption(TitleMenuOption.continueGame)
        reloadedRuntime.confirmSelectedSaveSlot()

        XCTAssertEqual(reloadedRuntime.currentState, GameState.gameplay)
        XCTAssertEqual(reloadedRuntime.inventoryState.cButtonLoadout.left, GameplayUsableItem.dekuNut)
        XCTAssertEqual(reloadedRuntime.inventoryState.cButtonLoadout.right, GameplayUsableItem.dekuStick)
        XCTAssertEqual(reloadedRuntime.hudState.cButtons.left.item, GameplayHUDButtonItem.dekuNut)
        XCTAssertEqual(reloadedRuntime.hudState.cButtons.right.item, GameplayHUDButtonItem.dekuStick)
        XCTAssertEqual(reloadedRuntime.hudState.cButtons.right.ammoCount, 4)
    }

    @MainActor
    func testTreasureChestInteractionStartsItemGetFlowAndPersistsTreasureFlagAcrossReload() throws {
        let chestActorID = 10
        let chestParams = makeChestParams(type: 0, getItemID: 0x41, treasureFlag: 3)
        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: chestActorID,
                            name: "ACTOR_EN_BOX",
                            position: Vector3s(x: 0, y: 0, z: -36),
                            params: chestParams
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: chestActorID, name: "ACTOR_EN_BOX", category: .chest),
            ]
        )
        let runtime = makeRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        XCTAssertEqual(runtime.gameplayActionLabel, "Open")

        runtime.handlePrimaryGameplayInput()

        XCTAssertEqual(runtime.itemGetSequence?.reward, .dungeonMap)
        XCTAssertTrue(runtime.inventoryState.hasOpenedTreasure(TreasureFlagKey(
            scene: SceneIdentity(id: 0x55, name: "test_scene"),
            flag: 3
        )))
        XCTAssertEqual((runtime.actors.first as? TreasureChestActor)?.isOpened, true)

        for _ in 0..<24 {
            runtime.updateFrame()
        }

        XCTAssertEqual(
            runtime.inventoryState.dungeonState(for: SceneIdentity(id: 0x55, name: "test_scene")).hasMap,
            true
        )
        XCTAssertEqual(runtime.activeMessagePresentation?.textRuns.first?.text, "Dungeon Map\n")

        runtime.handlePrimaryGameplayInput()
        for _ in 0..<8 {
            runtime.updateFrame()
        }

        XCTAssertNil(runtime.itemGetSequence)

        try runtime.loadScene(id: 0x55)

        XCTAssertNil(runtime.gameplayActionLabel)
        XCTAssertEqual((runtime.actors.first as? TreasureChestActor)?.isOpened, true)
    }

    @MainActor
    func testContinuePreservesChestRewardStateAcrossTitleReturn() async throws {
        let chestActorID = 10
        let chestParams = makeChestParams(type: 0, getItemID: 0x41, treasureFlag: 3)
        let fixture = RuntimeFixture(
            scene: makeScene(
                sceneName: "spot04",
                roomSpawns: [
                    0: [
                        makeSpawn(
                            id: chestActorID,
                            name: "ACTOR_EN_BOX",
                            position: Vector3s(x: 0, y: 0, z: -36),
                            params: chestParams
                        ),
                    ],
                ],
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        roomID: 0,
                        position: Vector3s(x: 0, y: 0, z: 0),
                        rotation: Vector3s(x: 0, y: 0, z: 0)
                    ),
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: chestActorID, name: "ACTOR_EN_BOX", category: .chest),
            ]
        )
        let runtime = makeRuntime(
            saveContext: SaveContext(
                slots: [
                    SaveSlot(
                        id: 0,
                        playerName: "Link",
                        locationName: "spot04",
                        hearts: 3,
                        hasSaveData: true
                    ),
                    .empty(id: 1),
                    .empty(id: 2),
                ]
            ),
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            suspender: { _ in }
        )
        let treasureFlag = TreasureFlagKey(
            scene: SceneIdentity(id: 0x55, name: "spot04"),
            flag: 3
        )

        await runtime.start()
        runtime.chooseTitleOption(.continueGame)
        runtime.confirmSelectedSaveSlot()
        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .continueGame)
        XCTAssertEqual(runtime.gameplayActionLabel, "Open")

        runtime.handlePrimaryGameplayInput()
        for _ in 0..<24 {
            runtime.updateFrame()
        }

        XCTAssertTrue(runtime.inventoryState.hasOpenedTreasure(treasureFlag))
        XCTAssertTrue(runtime.inventoryState.dungeonState(for: treasureFlag.scene).hasMap)
        XCTAssertTrue(runtime.saveContext.slots[0].inventoryState.hasOpenedTreasure(treasureFlag))
        XCTAssertTrue(runtime.saveContext.slots[0].inventoryState.dungeonState(for: treasureFlag.scene).hasMap)

        runtime.handlePrimaryGameplayInput()
        for _ in 0..<8 {
            runtime.updateFrame()
        }

        runtime.returnToTitleScreen()
        XCTAssertEqual(runtime.currentState, .titleScreen)

        runtime.chooseTitleOption(.continueGame)
        runtime.confirmSelectedSaveSlot()
        try runtime.loadScene(id: 0x55)

        XCTAssertEqual(runtime.currentState, .gameplay)
        XCTAssertEqual(runtime.playState?.entryMode, .continueGame)
        XCTAssertEqual(runtime.playState?.currentSceneName, "spot04")
        XCTAssertTrue(runtime.inventoryState.hasOpenedTreasure(treasureFlag))
        XCTAssertTrue(runtime.inventoryState.dungeonState(for: treasureFlag.scene).hasMap)
        XCTAssertTrue(runtime.saveContext.slots[0].inventoryState.hasOpenedTreasure(treasureFlag))
        XCTAssertTrue(runtime.saveContext.slots[0].inventoryState.dungeonState(for: treasureFlag.scene).hasMap)
        XCTAssertNil(runtime.gameplayActionLabel)
        XCTAssertEqual((runtime.actors.first as? TreasureChestActor)?.isOpened, true)
    }

    func testTreasureChestRewardMappingCoversAllM4Items() {
        XCTAssertEqual(TreasureChestReward(getItemID: 0x41), .dungeonMap)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x40), .compass)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x3F), .bossKey)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x05), .slingshot)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x3D), .heartContainer)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x42), .smallKey)
        XCTAssertEqual(TreasureChestReward(getItemID: 0x02), .dekuNuts(5))
        XCTAssertEqual(TreasureChestReward(getItemID: 0x64), .dekuNuts(10))
        XCTAssertEqual(TreasureChestReward(getItemID: 0x07), .dekuSticks(1))
        XCTAssertEqual(TreasureChestReward(getItemID: 0x61), .dekuSticks(5))
        XCTAssertEqual(TreasureChestReward(getItemID: 0x62), .dekuSticks(10))
    }

    func testGameplayInventoryAppliesMajorChestRewardsToHUDRelevantState() {
        var inventory = GameplayInventoryState.starter(hearts: 3)
        let scene = SceneIdentity(id: 0x55, name: "test_scene")

        inventory.apply(.slingshot, in: scene)
        inventory.apply(.smallKey, in: scene)
        inventory.apply(.heartContainer, in: scene)
        inventory.apply(.dekuNuts(5), in: scene)
        inventory.apply(.dekuSticks(10), in: scene)

        XCTAssertTrue(inventory.hasSlingshot)
        XCTAssertEqual(inventory.smallKeyCount(for: scene), 1)
        XCTAssertEqual(inventory.maximumHealthUnits, 8)
        XCTAssertEqual(inventory.currentHealthUnits, 8)
        XCTAssertEqual(inventory.dekuNutCount, 5)
        XCTAssertEqual(inventory.dekuStickCount, 10)
    }

    @MainActor
    func testLoadSceneMarksVisitedSceneAndPersistsToSaveSlot() throws {
        let scene = makeScene(
            sceneID: 0x55,
            sceneName: "spot04",
            roomSpawns: [0: []]
        )
        let saveContext = SaveContext(
            slots: [
                SaveSlot(
                    id: 0,
                    playerName: "Link",
                    locationName: "Kokiri Forest",
                    hearts: 3,
                    hasSaveData: true
                ),
            ]
        )
        let contentLoader = MockContentLoader(
            scenesByID: [0x55: scene],
            actorTable: []
        )
        let sceneLoader = ConfigurableSceneLoader(
            sceneEntries: [
                SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
            ],
            scenesByID: [0x55: scene]
        )
        let runtime = GameRuntime(
            saveContext: saveContext,
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)

        XCTAssertTrue(runtime.inventoryState.visitedSceneIDs.contains(0x55))
        XCTAssertTrue(runtime.saveContext.slots[0].inventoryContext.gameplay.visitedSceneIDs.contains(0x55))
    }

    @MainActor
    func testSceneSelectionAccumulatesVisitedScenesForDebugTeleport() async throws {
        let kokiriScene = makeScene(
            sceneID: 0x55,
            sceneName: "spot04",
            roomSpawns: [0: []]
        )
        let kakarikoScene = makeScene(
            sceneID: 0x01,
            sceneName: "spot01",
            roomSpawns: [0: []]
        )
        let saveContext = SaveContext(
            slots: [
                SaveSlot(
                    id: 0,
                    playerName: "Link",
                    locationName: "Kokiri Forest",
                    hearts: 3,
                    hasSaveData: true
                ),
            ]
        )
        let contentLoader = MockContentLoader(
            scenesByID: [
                0x55: kokiriScene,
                0x01: kakarikoScene,
            ],
            actorTable: []
        )
        let sceneLoader = ConfigurableSceneLoader(
            sceneEntries: [
                SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
                SceneTableEntry(index: 0x01, segmentName: "spot01_scene", enumName: "SCENE_KAKARIKO_VILLAGE"),
            ],
            scenesByID: [
                0x55: kokiriScene,
                0x01: kakarikoScene,
            ]
        )
        let runtime = GameRuntime(
            saveContext: saveContext,
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        await runtime.selectScene(id: 0x01)

        XCTAssertEqual(runtime.playState?.currentSceneID, 0x01)
        XCTAssertEqual(runtime.visitedSceneIDs, Set([0x55, 0x01]))
        XCTAssertEqual(
            runtime.saveContext.slots[0].inventoryContext.gameplay.visitedSceneIDs,
            Set([0x55, 0x01])
        )
    }

    @MainActor
    func testDrawPassesOnlyCallMatchingActors() throws {
        let recorder = EventRecorder()
        var registry = ActorRegistry()
        registry.register(actorID: 10) {
            RecordingActor(
                spawnRecord: $0,
                label: "opaque",
                recorder: recorder,
                drawPasses: [.opaque]
            )
        }
        registry.register(actorID: 20) {
            RecordingActor(
                spawnRecord: $0,
                label: "translucent",
                recorder: recorder,
                drawPasses: [.translucent]
            )
        }

        let fixture = RuntimeFixture(
            scene: makeScene(
                roomSpawns: [
                    0: [
                        makeSpawn(id: 10, name: "ACTOR_OPAQUE_TEST"),
                        makeSpawn(id: 20, name: "ACTOR_TRANSLUCENT_TEST"),
                    ]
                ]
            ),
            actorTable: [
                makeActorTableEntry(id: 10, name: "ACTOR_OPAQUE_TEST", category: .npc),
                makeActorTableEntry(id: 20, name: "ACTOR_TRANSLUCENT_TEST", category: .misc),
            ]
        )
        let runtime = GameRuntime(
            contentLoader: fixture.contentLoader,
            sceneLoader: MockSceneLoader(),
            actorRegistry: registry,
            suspender: { _ in }
        )

        try runtime.loadScene(id: 0x55)
        recorder.reset()

        runtime.drawActors(in: .opaque)
        runtime.drawActors(in: .translucent)

        XCTAssertEqual(
            recorder.events,
            [
                "draw:opaque:opaque",
                "draw:translucent:translucent",
            ]
        )
        XCTAssertNil(runtime.playState?.currentDrawPass)
    }
}

@MainActor
private func makeRuntime(
    saveContext: SaveContext = SaveContext(),
    contentLoader: any ContentLoading = ContentLoader(sceneLoader: MockSceneLoader()),
    sceneLoader: any SceneLoading = MockSceneLoader(),
    telemetryPublisher: any TelemetryPublishing = TelemetryPublisher(),
    actorRegistry: ActorRegistry? = nil,
    suspender: @escaping GameRuntime.RuntimeSuspender = { _ in }
) -> GameRuntime {
    GameRuntime(
        saveContext: saveContext,
        contentLoader: contentLoader,
        sceneLoader: sceneLoader,
        telemetryPublisher: telemetryPublisher,
        actorRegistry: actorRegistry,
        suspender: suspender
    )
}

private func uniqueSaveFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftoot-save-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("save-context.json", isDirectory: false)
}

private struct RuntimeFixture {
    let contentLoader: MockContentLoader

    init(
        scene: LoadedScene,
        actorTable: [ActorTableEntry],
        messageCatalog: MessageCatalog = MessageCatalog(),
        entranceTable: [EntranceTableEntry] = []
    ) {
        contentLoader = MockContentLoader(
            scenesByID: [scene.manifest.id: scene],
            actorTable: actorTable,
            messageCatalog: messageCatalog,
            entranceTable: entranceTable
        )
    }
}

@MainActor
private func performSwordSlash(with runtime: GameRuntime) throws {
    runtime.setControllerInput(ControllerInputState(bPressed: true))
    runtime.updateFrame()
    runtime.setControllerInput(ControllerInputState())
    runtime.updateFrame()
    XCTAssertEqual(runtime.combatState.activeAttack?.kind, .slash)
    for _ in 0..<6 {
        runtime.updateFrame()
    }
}

@MainActor
private func applyPlayerHit(
    to actor: any CombatActor,
    element: DamageElement,
    attackerPosition: Vec3f,
    playState: PlayState
) {
    let proposedHit = CombatHit(
        source: .player,
        element: element,
        direction: Vec3f(actor.position.simd - attackerPosition.simd),
        effect: actor.combatProfile.damageTable.effect(for: element)
    )

    switch actor.combatHitResolution(
        for: proposedHit,
        attackerPosition: attackerPosition,
        playState: playState
    ) {
    case .ignore, .block:
        return
    case .apply(let effect):
        actor.hitPoints = max(0, actor.hitPoints - effect.damage)
        actor.combatDidReceiveHit(
            CombatHit(
                source: .player,
                element: element,
                direction: proposedHit.direction,
                effect: effect
            ),
            playState: playState
        )
    }
}

private struct MockContentLoader: ContentLoading {
    let scenesByID: [Int: LoadedScene]
    let actorTable: [ActorTableEntry]
    let messageCatalog: MessageCatalog
    let entranceTable: [EntranceTableEntry]

    init(
        scenesByID: [Int: LoadedScene],
        actorTable: [ActorTableEntry],
        messageCatalog: MessageCatalog = MessageCatalog(),
        entranceTable: [EntranceTableEntry] = []
    ) {
        self.scenesByID = scenesByID
        self.actorTable = actorTable
        self.messageCatalog = messageCatalog
        self.entranceTable = entranceTable
    }

    func loadInitialContent() async throws {}

    func loadScene(id: Int) throws -> LoadedScene {
        guard let scene = scenesByID[id] else {
            throw ContentLoaderError.sceneLoadingUnavailable
        }
        return scene
    }

    func loadActorTable() throws -> [ActorTableEntry] {
        actorTable
    }

    func loadMessageCatalog() throws -> MessageCatalog {
        messageCatalog
    }

    func loadObjectTable() throws -> [ObjectTableEntry] {
        []
    }

    func loadEntranceTable() throws -> [EntranceTableEntry] {
        entranceTable
    }
}

@MainActor
private final class EventRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }
}

@MainActor
private final class RecordingActor: DamageableBaseActor {
    let label: String
    let recorder: EventRecorder
    let updateAction: (@MainActor (RecordingActor, PlayState) -> Void)?
    let configuredDrawPasses: Set<ActorDrawPass>

    init(
        spawnRecord: ActorSpawnRecord,
        label: String,
        recorder: EventRecorder,
        drawPasses: Set<ActorDrawPass> = [.opaque],
        updateAction: (@MainActor (RecordingActor, PlayState) -> Void)? = nil
    ) {
        self.label = label
        self.recorder = recorder
        self.configuredDrawPasses = drawPasses
        self.updateAction = updateAction
        super.init(spawnRecord: spawnRecord)
    }

    override var drawPasses: Set<ActorDrawPass> {
        configuredDrawPasses
    }

    override func initialize(playState: PlayState) {
        recorder.append("init:\(label)")
    }

    override func update(playState: PlayState) {
        recorder.append("update:\(label)")
        updateAction?(self, playState)
    }

    override func draw(playState: PlayState, pass: ActorDrawPass) {
        recorder.append("draw:\(label):\(pass.rawValue)")
    }

    override func destroy(playState: PlayState) {
        recorder.append("destroy:\(label)")
    }
}

@MainActor
private final class TestTalkActor: DamageableBaseActor, TalkRequestingActor {
    let prompt: String
    let messageID: Int

    var talkPrompt: String {
        prompt
    }

    init(
        spawnRecord: ActorSpawnRecord,
        prompt: String,
        messageID: Int
    ) {
        self.prompt = prompt
        self.messageID = messageID
        super.init(spawnRecord: spawnRecord)
    }

    func talkRequested(playState: PlayState) -> Bool {
        playState.requestMessage(messageID)
        return true
    }
}

@MainActor
private final class TestCombatActor: CombatantBaseActor {
    let label: String
    let recorder: EventRecorder
    let targetable: Bool
    let attackBuilder: (@MainActor (TestCombatActor) -> [CombatAttackDefinition])?

    override var isTargetable: Bool {
        targetable && hitPoints > 0
    }

    init(
        spawnRecord: ActorSpawnRecord,
        label: String,
        recorder: EventRecorder,
        targetable: Bool = true,
        combatProfile: ActorCombatProfile = ActorCombatProfile(
            hurtboxRadius: 18,
            hurtboxHeight: 44,
            targetAnchorHeight: 44,
            targetingRange: 280,
            damageTable: DamageTable(
                defaultEffect: DamageEffect(damage: 1, knockbackDistance: 18),
                overrides: [
                    .swordJump: DamageEffect(damage: 2, knockbackDistance: 24),
                    .swordSpin: DamageEffect(damage: 2, knockbackDistance: 20),
                ]
            )
        ),
        attackBuilder: (@MainActor (TestCombatActor) -> [CombatAttackDefinition])? = nil
    ) {
        self.label = label
        self.recorder = recorder
        self.targetable = targetable
        self.attackBuilder = attackBuilder
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: 3,
            combatProfile: combatProfile
        )
    }

    override var activeAttacks: [CombatAttackDefinition] {
        attackBuilder?(self) ?? []
    }

    override func combatDidReceiveHit(_ hit: CombatHit, playState: PlayState) {
        recorder.append("hit:\(label):\(hit.element.rawValue):\(hit.effect.damage)")
    }

    override func combatDidBlockHit(_ hit: CombatHit, playState: PlayState) {
        recorder.append("block:\(label):\(hit.element.rawValue)")
    }
}

private func makeScene(
    sceneID: Int = 0x55,
    sceneName: String = "test_scene",
    roomSpawns: [Int: [SceneActorSpawn]],
    sceneObjectIDs: [Int] = [],
    roomObjectIDs: [Int: [Int]] = [:],
    entrances: [SceneEntranceDefinition] = [],
    spawns: [SceneSpawnPoint] = [],
    transitionTriggers: [SceneTransitionTrigger] = [],
    cutsceneTriggers: [SceneCutsceneTrigger] = [],
    eventRegionTriggers: [SceneEventRegionTrigger] = [],
    exits: [SceneExitDefinition] = [],
    collision: CollisionMesh? = nil,
    paths: [ScenePathDefinition] = []
) -> LoadedScene {
    let sortedRooms = roomSpawns.keys.sorted()
    let manifestRooms = sortedRooms.map { roomID in
        RoomManifest(
            id: roomID,
            name: "room_\(roomID)",
            directory: "Scenes/test/rooms/room_\(roomID)"
        )
    }
    let loadedRooms = manifestRooms.map { room in
        LoadedSceneRoom(
            manifest: room,
            displayList: [],
            vertexData: Data()
        )
    }
    let actors = SceneActorsFile(
        sceneName: sceneName,
        rooms: manifestRooms.map { room in
            RoomActorSpawns(
                roomName: room.name,
                actors: roomSpawns[room.id, default: []]
            )
        }
    )

    return LoadedScene(
        manifest: SceneManifest(
            id: sceneID,
            name: sceneName,
            rooms: manifestRooms,
            actorsPath: "Manifests/scenes/test_scene/actors.json"
        ),
        collision: collision,
        actors: actors,
        spawns: SceneSpawnsFile(sceneName: sceneName, spawns: spawns),
        paths: ScenePathsFile(sceneName: sceneName, paths: paths),
        exits: SceneExitsFile(sceneName: sceneName, exits: exits),
        sceneHeader: SceneHeaderDefinition(
            sceneName: sceneName,
            sceneObjectIDs: sceneObjectIDs,
            spawns: spawns,
            entrances: entrances,
            rooms: manifestRooms.map { room in
                SceneRoomDefinition(
                    id: room.id,
                    shape: .normal,
                    objectIDs: roomObjectIDs[room.id, default: []]
                )
            },
            transitionTriggers: transitionTriggers,
            cutsceneTriggers: cutsceneTriggers,
            eventRegionTriggers: eventRegionTriggers
        ),
        rooms: loadedRooms
    )
}

private func makeSpawn(
    id: Int,
    name: String,
    position: Vector3s = Vector3s(x: 0, y: 0, z: 0),
    rotation: Vector3s = Vector3s(x: 0, y: 0, z: 0),
    params: Int16 = 0
) -> SceneActorSpawn {
    SceneActorSpawn(
        actorID: id,
        actorName: name,
        position: position,
        rotation: rotation,
        params: params
    )
}

private func makeActorTableEntry(
    id: Int,
    name: String,
    category: ActorCategory,
    objectID: Int = 0
) -> ActorTableEntry {
    ActorTableEntry(
        id: id,
        enumName: name,
        profile: ActorProfile(
            id: id,
            category: category.rawValue,
            flags: 0,
            objectID: objectID
        )
    )
}

private func makeChestParams(
    type: Int,
    getItemID: Int,
    treasureFlag: Int
) -> Int16 {
    Int16(bitPattern: UInt16((type << 12) | (getItemID << 5) | treasureFlag))
}

private struct MockSceneLoader: SceneLoading {
    private let sceneEntries = [
        SceneTableEntry(index: 0x01, segmentName: "spot01_scene", enumName: "SCENE_TEST"),
        SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
    ]

    func loadSceneTableEntries() throws -> [SceneTableEntry] {
        sceneEntries
    }

    func resolveSceneDirectory(for sceneID: Int) throws -> URL {
        URL(fileURLWithPath: "/tmp/scene-\(sceneID)", isDirectory: true)
    }

    func loadScene(id: Int) throws -> LoadedScene {
        let manifest = SceneManifest(
            id: id,
            name: id == 0x55 ? "spot04" : "spot01",
            rooms: [
                RoomManifest(
                    id: 0,
                    name: "room_0",
                    directory: "Scenes/room_0"
                )
            ],
            textureDirectories: ["Textures/spot04_scene"]
        )
        return LoadedScene(
            manifest: manifest,
            rooms: [
                LoadedSceneRoom(
                    manifest: manifest.rooms[0],
                    displayList: [],
                    vertexData: Data(repeating: 0, count: MemoryLayout<N64Vertex>.stride)
                )
            ]
        )
    }

    func loadScene(named name: String) throws -> LoadedScene {
        try loadScene(id: name == "spot04" ? 0x55 : 0x01)
    }

    func loadTextureAssetURLs(for scene: LoadedScene) throws -> [UInt32: URL] {
        [
            OOTAssetID.stableID(for: "gSpot04MainTex"):
                URL(fileURLWithPath: "/tmp/gSpot04MainTex.tex.bin")
        ]
    }

    func loadSceneManifest(id: Int) throws -> SceneManifest {
        try loadScene(id: id).manifest
    }

    func loadSceneManifest(named name: String) throws -> SceneManifest {
        try loadScene(named: name).manifest
    }

    func loadActorTable() throws -> [ActorTableEntry] {
        []
    }

    func loadObjectTable() throws -> [ObjectTableEntry] {
        []
    }

    func loadEntranceTable() throws -> [EntranceTableEntry] {
        []
    }

    func loadObject(named name: String) throws -> LoadedObject {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadCollisionMesh(for manifest: SceneManifest) throws -> CollisionMesh? {
        nil
    }

    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] {
        []
    }

    func loadRoomVertexData(for room: RoomManifest) throws -> Data {
        Data()
    }
}

private struct ConfigurableSceneLoader: SceneLoading {
    let sceneEntries: [SceneTableEntry]
    let scenesByID: [Int: LoadedScene]

    func loadSceneTableEntries() throws -> [SceneTableEntry] {
        sceneEntries
    }

    func resolveSceneDirectory(for sceneID: Int) throws -> URL {
        URL(fileURLWithPath: "/tmp/config-scene-\(sceneID)", isDirectory: true)
    }

    func loadScene(id: Int) throws -> LoadedScene {
        guard let scene = scenesByID[id] else {
            throw ContentLoaderError.sceneLoadingUnavailable
        }
        return scene
    }

    func loadScene(named name: String) throws -> LoadedScene {
        guard let scene = scenesByID.values.first(where: { $0.manifest.name == name }) else {
            throw ContentLoaderError.sceneLoadingUnavailable
        }
        return scene
    }

    func loadTextureAssetURLs(for scene: LoadedScene) throws -> [UInt32: URL] {
        [:]
    }

    func loadSceneManifest(id: Int) throws -> SceneManifest {
        try loadScene(id: id).manifest
    }

    func loadSceneManifest(named name: String) throws -> SceneManifest {
        try loadScene(named: name).manifest
    }

    func loadActorTable() throws -> [ActorTableEntry] {
        []
    }

    func loadObjectTable() throws -> [ObjectTableEntry] {
        []
    }

    func loadObject(named name: String) throws -> LoadedObject {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadEntranceTable() throws -> [EntranceTableEntry] {
        []
    }

    func loadCollisionMesh(for manifest: SceneManifest) throws -> CollisionMesh? {
        nil
    }

    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] {
        []
    }

    func loadRoomVertexData(for room: RoomManifest) throws -> Data {
        Data()
    }
}

private func fixtureCollisionMesh() -> CollisionMesh {
    CollisionMesh(
        minimumBounds: Vector3s(x: 0, y: 0, z: 0),
        maximumBounds: Vector3s(x: 10, y: 8, z: 10),
        vertices: [
            Vector3s(x: 0, y: 0, z: 0),
            Vector3s(x: 10, y: 0, z: 0),
            Vector3s(x: 0, y: 0, z: 10),
            Vector3s(x: 10, y: 0, z: 10),
            Vector3s(x: 0, y: 8, z: 0),
            Vector3s(x: 0, y: 8, z: 10),
            Vector3s(x: 10, y: 8, z: 0),
            Vector3s(x: 10, y: 8, z: 10),
            Vector3s(x: 5, y: 0, z: 0),
            Vector3s(x: 5, y: 0, z: 10),
            Vector3s(x: 5, y: 8, z: 0),
            Vector3s(x: 5, y: 8, z: 10),
        ],
        polygons: [
            CollisionPoly(
                surfaceType: 0,
                vertexA: 0,
                vertexB: 1,
                vertexC: 2,
                normal: Vector3s(x: 0, y: 0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 0,
                vertexA: 1,
                vertexB: 3,
                vertexC: 2,
                normal: Vector3s(x: 0, y: 0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 1,
                vertexA: 4,
                vertexB: 5,
                vertexC: 6,
                normal: Vector3s(x: 0, y: -0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 1,
                vertexA: 6,
                vertexB: 5,
                vertexC: 7,
                normal: Vector3s(x: 0, y: -0x7FFF, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 2,
                vertexA: 8,
                vertexB: 9,
                vertexC: 10,
                normal: Vector3s(x: 0x7FFF, y: 0, z: 0),
                distance: 0
            ),
            CollisionPoly(
                surfaceType: 2,
                vertexA: 10,
                vertexB: 9,
                vertexC: 11,
                normal: Vector3s(x: 0x7FFF, y: 0, z: 0),
                distance: 0
            ),
        ],
        surfaceTypes: [
            CollisionSurfaceType(low: (4 << 13), high: 0),
            CollisionSurfaceType(low: 0, high: (1 << 17)),
            CollisionSurfaceType(low: (7 << 21), high: 0),
        ]
    )
}
