import XCTest
import Metal
import OOTContent
import OOTCore
import OOTDataModel
import simd
@testable import OOTRender
@testable import OOTUI

@MainActor
final class OOTUITests: XCTestCase {
    func testAppViewCompiles() {
        _ = OOTAppView(
            runtime: GameRuntime(
                contentLoader: StubContentLoader(),
                sceneLoader: UITestSceneLoader(),
                suspender: { _ in }
            )
        )
        _ = DebugSidebar()
        _ = MessageView(
            presentation: MessagePresentation(
                messageID: 0x1000,
                variant: .blue,
                phase: .displaying,
                textRuns: [
                    MessageTextRun(text: "Hello ", color: .white),
                    MessageTextRun(text: "Link", color: .yellow),
                ],
                icon: MessageIcon(rawValue: "fairy"),
                choiceState: MessageChoiceState(
                    options: [
                        MessageChoiceOption(title: "Yes"),
                        MessageChoiceOption(title: "No"),
                    ]
                )
            )
        )
        _ = ActionPromptView(label: "Talk")
        _ = ItemGetView(
            state: ItemGetOverlayState(
                title: "Compass",
                description: "Reveals hidden treasure in the dungeon.",
                iconName: "location.north.line.fill",
                phase: .displayingText
            )
        )
        _ = GameplayHUDView(
            runtime: GameRuntime(
                playState: PlayState(
                    activeSaveSlot: 0,
                    entryMode: .newGame,
                    currentSceneName: "Kokiri Forest",
                    currentRoomID: 1,
                    playerName: "Link",
                    scene: makeLoadedScene()
                ),
                playerState: PlayerState(position: Vec3f(x: 12, y: 0, z: -18)),
                hudState: GameplayHUDState(
                    currentHealthUnits: 5,
                    maximumHealthUnits: 8,
                    currentMagic: 24,
                    maximumMagic: 48,
                    rupees: 37,
                    smallKeyCount: 2,
                    bButtonItem: .bomb
                ),
                contentLoader: StubContentLoader(),
                sceneLoader: UITestSceneLoader(),
                suspender: { _ in }
            )
        )
    }

    func testRootViewStateMatchesRuntimeState() {
        XCTAssertEqual(OOTAppView.rootViewState(for: .boot), .boot)
        XCTAssertEqual(OOTAppView.rootViewState(for: .consoleLogo), .consoleLogo)
        XCTAssertEqual(OOTAppView.rootViewState(for: .titleScreen), .titleScreen)
        XCTAssertEqual(OOTAppView.rootViewState(for: .fileSelect), .fileSelect)
        XCTAssertEqual(OOTAppView.rootViewState(for: .gameplay), .gameplay)
    }

    func testInputManagerMapsKeyboardEventsIntoControllerState() throws {
        let runtime = GameRuntime(
            sceneLoader: UITestSceneLoader(),
            suspender: { _ in }
        )
        let inputManager = InputManager(runtime: runtime)

        XCTAssertTrue(inputManager.handleKeyDown(try makeKeyEvent(type: .keyDown, character: "w", keyCode: 13)))
        XCTAssertEqual(runtime.controllerInputState.stick, StickInput(x: 0, y: 1))

        XCTAssertTrue(inputManager.handleKeyDown(try makeKeyEvent(type: .keyDown, character: " ", keyCode: 49)))
        XCTAssertTrue(runtime.controllerInputState.aPressed)

        XCTAssertTrue(inputManager.handleKeyDown(try makeKeyEvent(type: .keyDown, character: "\t", keyCode: 48)))
        XCTAssertTrue(runtime.controllerInputState.zPressed)

        XCTAssertTrue(inputManager.handleKeyDown(try makeKeyEvent(type: .keyDown, character: "", keyCode: 56)))
        XCTAssertTrue(runtime.controllerInputState.bPressed)

        XCTAssertTrue(inputManager.handleKeyUp(try makeKeyEvent(type: .keyUp, character: "w", keyCode: 13)))
        XCTAssertTrue(inputManager.handleKeyUp(try makeKeyEvent(type: .keyUp, character: " ", keyCode: 49)))
        XCTAssertTrue(inputManager.handleKeyUp(try makeKeyEvent(type: .keyUp, character: "\t", keyCode: 48)))
        XCTAssertTrue(inputManager.handleKeyUp(try makeKeyEvent(type: .keyUp, character: "", keyCode: 56)))

        XCTAssertEqual(runtime.controllerInputState.stick, .zero)
        XCTAssertFalse(runtime.controllerInputState.aPressed)
        XCTAssertFalse(runtime.controllerInputState.bPressed)
        XCTAssertFalse(runtime.controllerInputState.zPressed)
    }

    func testDeveloperInputScriptSupportsDurationsAndExplicitFrameRanges() throws {
        let script = try DeveloperInputScript(
            steps: [
                DeveloperInputStep(
                    duration: 3,
                    stick: DeveloperInputVector(x: 0, y: 1)
                ),
                DeveloperInputStep(
                    frameRange: DeveloperInputFrameRange(start: 5, end: 6),
                    aPressed: true,
                    zPressed: true
                ),
            ]
        )

        XCTAssertEqual(script.totalFrameCount, 7)
        XCTAssertEqual(script.inputState(for: 0).stick, StickInput(x: 0, y: 1))
        XCTAssertEqual(script.inputState(for: 2).stick, StickInput(x: 0, y: 1))
        XCTAssertEqual(script.inputState(for: 3), ControllerInputState())
        XCTAssertEqual(
            script.inputState(for: 5),
            ControllerInputState(aPressed: true, zPressed: true)
        )
    }

    func testDeveloperInputScriptCombinesOverlappingMovementAndButtonSteps() throws {
        let script = try DeveloperInputScript(
            steps: [
                DeveloperInputStep(
                    duration: 10,
                    stick: DeveloperInputVector(x: 0, y: 1)
                ),
                DeveloperInputStep(
                    frameRange: DeveloperInputFrameRange(start: 4, end: 6),
                    aPressed: true
                ),
            ]
        )

        XCTAssertEqual(
            script.inputState(for: 5),
            ControllerInputState(
                stick: StickInput(x: 0, y: 1),
                aPressed: true
            )
        )
    }

    func testDeveloperHarnessConfigurationLoadsEnvironmentAndScriptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("script.json")
        let scriptData = try JSONEncoder().encode([
            DeveloperInputStep(duration: 4, bPressed: true),
        ])
        try scriptData.write(to: scriptURL)

        let configuration = try XCTUnwrap(
            DeveloperHarnessConfiguration.load(
                from: [
                    DeveloperHarnessConfiguration.sceneEnvironmentVariable: "0x55",
                    DeveloperHarnessConfiguration.entranceEnvironmentVariable: "3",
                    DeveloperHarnessConfiguration.spawnEnvironmentVariable: "1",
                    DeveloperHarnessConfiguration.timeOfDayEnvironmentVariable: "18.5",
                    DeveloperHarnessConfiguration.inputScriptEnvironmentVariable: "script.json",
                    DeveloperHarnessConfiguration.captureFrameEnvironmentVariable: "captures/frame.png",
                    DeveloperHarnessConfiguration.captureStateEnvironmentVariable: "captures/state.json",
                    DeveloperHarnessConfiguration.captureViewportEnvironmentVariable: "640x360",
                ],
                currentDirectoryURL: directory
            )
        )

        XCTAssertEqual(
            configuration.launchConfiguration,
            DeveloperSceneLaunchConfiguration(
                scene: .id(0x55),
                entranceIndex: 3,
                spawnIndex: 1,
                fixedTimeOfDay: 18.5
            )
        )
        XCTAssertEqual(configuration.inputScript?.totalFrameCount, 4)
        XCTAssertEqual(configuration.captureViewport, DeveloperHarnessViewport(width: 640, height: 360))
        XCTAssertEqual(configuration.captureFrameURL?.path, directory.appendingPathComponent("captures/frame.png").path)
        XCTAssertEqual(configuration.captureStateURL?.path, directory.appendingPathComponent("captures/state.json").path)
    }

    func testGameplayCameraConfigurationUsesPlayerStateAndFallsBackToFirstSpawn() throws {
        let scene = makeLoadedScene()
        let playerState = PlayerState(
            position: Vec3f(x: 12, y: 34, z: 56),
            facingRadians: .pi / 2
        )

        let playerConfiguration = try XCTUnwrap(
            SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: scene,
                playerState: playerState
            )
        )
        XCTAssertEqual(playerConfiguration.playerPosition, SIMD3<Float>(12, 34, 56))
        XCTAssertEqual(playerConfiguration.playerYaw, .pi / 2, accuracy: 0.000_1)
        XCTAssertEqual(playerConfiguration.collision, scene.collision)

        let spawnConfiguration = try XCTUnwrap(
            SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: scene,
                playerState: nil
            )
        )
        XCTAssertEqual(spawnConfiguration.playerPosition, SIMD3<Float>(100, 20, -40))
        XCTAssertEqual(spawnConfiguration.playerYaw, Float(Int16(0x4000)) * (.pi / 32_768.0), accuracy: 0.000_1)
        XCTAssertEqual(spawnConfiguration.collision, scene.collision)
    }

    func testGameplayCameraConfigurationCarriesItemGetPresentationOverride() throws {
        let scene = makeLoadedScene()
        let playerState = PlayerState(
            position: Vec3f(x: 12, y: 34, z: 56),
            facingRadians: .pi / 4
        )
        let sequence = ItemGetSequenceState(
            reward: .bossKey,
            chestSize: .large,
            treasureFlag: TreasureFlagKey(
                scene: SceneIdentity(id: scene.manifest.id, name: scene.manifest.name),
                flag: 2
            ),
            itemWorldPosition: Vec3f(x: 12, y: 92, z: 56)
        )

        let configuration = try XCTUnwrap(
            SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: scene,
                playerState: playerState,
                itemGetSequence: sequence
            )
        )

        XCTAssertEqual(
            configuration.presentationOverride,
            .itemGet(itemPosition: SIMD3<Float>(12, 92, 56), playerYaw: .pi / 4)
        )
    }

    func testGameplayCameraConfigurationCarriesLockOnTargetPosition() throws {
        let scene = makeLoadedScene()
        let playerState = PlayerState(
            position: Vec3f(x: 12, y: 0, z: 56),
            facingRadians: .pi / 4
        )
        let combatState = GameplayCombatState(
            lockOnTarget: CombatTargetSnapshot(
                actorID: 10,
                actorType: "TestCombatActor",
                position: Vec3f(x: 32, y: 0, z: 8),
                anchorHeight: 44,
                distance: 52
            )
        )

        let configuration = try XCTUnwrap(
            SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: scene,
                playerState: playerState,
                combatState: combatState
            )
        )

        XCTAssertEqual(
            configuration.lockOnTargetPosition,
            SIMD3<Float>(32, 44, 8)
        )
    }

    func testLockOnIndicatorProjectorReturnsViewportPointForVisibleTarget() throws {
        let scene = makeLoadedScene()
        let playerState = PlayerState(
            position: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: 0
        )
        let combatState = GameplayCombatState(
            lockOnTarget: CombatTargetSnapshot(
                actorID: 10,
                actorType: "TestCombatActor",
                position: Vec3f(x: 0, y: 0, z: -64),
                anchorHeight: 44,
                distance: 64
            )
        )

        let point = LockOnIndicatorProjector.project(
            target: try XCTUnwrap(combatState.lockOnTarget),
            sceneBounds: SceneBounds(
                minimum: SIMD3<Float>(-100, 0, -100),
                maximum: SIMD3<Float>(100, 80, 100)
            ),
            scene: scene,
            playerState: playerState,
            combatState: combatState,
            itemGetSequence: nil,
            viewportSize: CGSize(width: 800, height: 600)
        )

        let resolvedPoint = try XCTUnwrap(point)
        XCTAssertGreaterThan(resolvedPoint.x, 0)
        XCTAssertLessThan(resolvedPoint.x, 800)
        XCTAssertGreaterThan(resolvedPoint.y, 0)
        XCTAssertLessThan(resolvedPoint.y, 300)
    }

    func testChestItemGetRuntimeWalkthroughUsingFixtureContentRoot() async throws {
        let fixture = try ChestRuntimeContentFixture()
        defer { fixture.cleanup() }

        let sceneLoader = SceneLoader(contentRoot: fixture.contentRoot)
        let contentLoader = ContentLoader(sceneLoader: sceneLoader)
        let runtime = GameRuntime(
            contentLoader: contentLoader,
            sceneLoader: sceneLoader,
            suspender: { _ in }
        )

        await runtime.start()
        XCTAssertEqual(runtime.currentState, .titleScreen)

        runtime.chooseTitleOption(.newGame)
        runtime.confirmSelectedSaveSlot()
        XCTAssertEqual(runtime.currentState, .gameplay)

        try runtime.loadScene(id: fixture.sceneID)

        XCTAssertEqual(runtime.loadedScene?.manifest.name, fixture.sceneName)
        XCTAssertEqual(runtime.gameplayActionLabel, "Open")
        XCTAssertNil(runtime.activeItemGetOverlay)

        let initialPayload = try SceneRenderPayloadBuilder.makePayload(
            scene: try XCTUnwrap(runtime.loadedScene),
            textureAssetURLs: runtime.textureAssetURLs,
            contentLoader: runtime.contentLoader
        )

        XCTAssertNotNil(initialPayload.playerRenderAssets)
        XCTAssertNotNil(initialPayload.chestRenderAssets)
        try assertRenderedSceneHasVisibleGeometry(
            payload: initialPayload,
            expectedSceneName: fixture.sceneName
        )

        runtime.handlePrimaryGameplayInput()

        let sequence = try XCTUnwrap(runtime.itemGetSequence)
        XCTAssertEqual(sequence.reward, .compass)
        XCTAssertEqual(runtime.activeItemGetOverlay?.title, "Compass")
        XCTAssertEqual(runtime.activeItemGetOverlay?.phase, .raising)
        XCTAssertEqual(runtime.playerState?.presentationMode, .itemGetA)

        let activeRenderScene = SceneRenderPayloadBuilder.renderScene(
            from: initialPayload,
            playerState: runtime.playerState,
            actors: runtime.actors
        )
        XCTAssertEqual(activeRenderScene.skeletons.map(\.name).sorted(), ["Chest-0.0--36.0", "Link"])

        let cameraConfiguration = try XCTUnwrap(
            SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: try XCTUnwrap(runtime.loadedScene),
                playerState: runtime.playerState,
                itemGetSequence: runtime.itemGetSequence
            )
        )
        XCTAssertEqual(
            cameraConfiguration.presentationOverride,
            .itemGet(itemPosition: sequence.itemWorldPosition.simd, playerYaw: runtime.playerState?.facingRadians ?? 0)
        )

        for _ in 0..<24 {
            runtime.updateFrame()
        }

        XCTAssertEqual(runtime.activeItemGetOverlay?.phase, .displayingText)
        XCTAssertEqual(runtime.activeMessagePresentation?.textRuns.first?.text, "Compass\n")
        XCTAssertTrue(runtime.inventoryState.dungeonState(for: sequence.treasureFlag.scene).hasCompass)

        runtime.handlePrimaryGameplayInput()
        for _ in 0..<8 {
            runtime.updateFrame()
        }

        XCTAssertNil(runtime.itemGetSequence)
        XCTAssertEqual(runtime.playerState?.presentationMode, .normal)

        try runtime.loadScene(id: fixture.sceneID)

        XCTAssertNil(runtime.gameplayActionLabel)
        XCTAssertEqual((runtime.actors.first as? TreasureChestActor)?.isOpened, true)
    }

    func testRenderSceneIncludesSkeletonRenderableActors() throws {
        let payload = try SceneRenderPayloadBuilder.makePayload(
            scene: makeLoadedScene(),
            textureAssetURLs: [:],
            contentLoader: HUDArtContentLoader(object: makeSkeletonTestObject())
        )

        let actor = TestSkeletonActor(
            renderState: ActorSkeletonRenderState(
                objectName: "object_dekubaba",
                skeletonName: "gDekuBabaSkel",
                animationName: "gDekuBabaFastChompAnim",
                animationFrame: 3,
                animationPlaybackMode: .loop
            )
        )
        let renderScene = SceneRenderPayloadBuilder.renderScene(
            from: payload,
            playerState: nil,
            actors: [actor]
        )

        let enemySkeleton = try XCTUnwrap(
            renderScene.skeletons.first { $0.name.contains("object_dekubaba") }
        )
        XCTAssertEqual(enemySkeleton.animationState.animation?.name, "gDekuBabaFastChompAnim")
    }

    func testGameplayHUDArtLibraryLoadsKnownGameplayKeepTextures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptors = [
            TextureDescriptor(format: .rgba16, width: 1, height: 1, path: "textures/gDropRecoveryHeartTex.tex.bin"),
            TextureDescriptor(format: .rgba16, width: 1, height: 1, path: "textures/gDropMagicSmallTex.tex.bin"),
            TextureDescriptor(format: .rgba16, width: 1, height: 1, path: "textures/gRupeeGreenTex.tex.bin"),
            TextureDescriptor(format: .rgba16, width: 1, height: 1, path: "textures/gUnusedBombIconTex.tex.bin"),
            TextureDescriptor(format: .rgba16, width: 1, height: 1, path: "textures/gUnusedArrowIconTex.tex.bin"),
        ]

        var textureURLs: [UInt32: URL] = [:]
        for descriptor in descriptors {
            let textureName = URL(fileURLWithPath: descriptor.path)
                .deletingPathExtension()
                .deletingPathExtension()
                .lastPathComponent
            let textureURL = directory.appendingPathComponent("\(textureName).tex.bin")
            try Data([255, 64, 32, 255]).write(to: textureURL)
            textureURLs[OOTAssetID.stableID(for: textureName)] = textureURL
        }

        let art = GameplayHUDArtLibrary.load(
            contentLoader: HUDArtContentLoader(
                object: LoadedObject(
                    manifest: ObjectManifest(name: "gameplay_keep", textures: descriptors),
                    textureAssetURLs: textureURLs
                )
            )
        )

        XCTAssertNotNil(art.heart)
        XCTAssertNotNil(art.magic)
        XCTAssertNotNil(art.rupee)
        XCTAssertNotNil(art.image(for: .bomb))
        XCTAssertNotNil(art.image(for: .bow))
    }

    func testGameplayHUDSceneMinimapBuildsOverviewFromCollision() {
        let model = SceneMinimapModel(
            scene: makeLoadedScene(),
            currentRoomID: 1,
            playerState: PlayerState(position: Vec3f(x: 40, y: 0, z: 40))
        )

        XCTAssertEqual(model.sceneTitle, "Kokiri Forest")
        XCTAssertEqual(model.roomLabel, "ROOM 2 / 2")
        XCTAssertEqual(model.overviewPolygons.count, 2)

        for polygon in model.overviewPolygons {
            XCTAssertEqual(polygon.points.count, 3)
            for point in polygon.points {
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, 1)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, 1)
            }
        }

        XCTAssertEqual(model.playerPoint?.x ?? -1, 0.7, accuracy: 0.001)
        XCTAssertEqual(model.playerPoint?.y ?? -1, 0.3, accuracy: 0.001)
    }

    func testAppRuntimeLoadsRealExtractedSceneViewerContentWhenConfigured() async throws {
        guard let contentRootPath = ProcessInfo.processInfo.environment["SWIFTOOT_REAL_CONTENT_ROOT"] else {
            throw XCTSkip("Set SWIFTOOT_REAL_CONTENT_ROOT to run the real-content scene viewer validation.")
        }

        let contentRoot = URL(fileURLWithPath: contentRootPath, isDirectory: true)
        let sceneLoader = SceneLoader(contentRoot: contentRoot)
        let runtime = GameRuntime(
            contentLoader: ContentLoader(contentRoot: contentRoot),
            sceneLoader: sceneLoader,
            suspender: { _ in }
        )

        await runtime.start()
        XCTAssertEqual(runtime.currentState, .titleScreen)

        runtime.chooseTitleOption(.newGame)
        XCTAssertEqual(runtime.currentState, .fileSelect)

        runtime.confirmSelectedSaveSlot()
        XCTAssertEqual(runtime.currentState, .gameplay)

        await runtime.bootstrapSceneViewer()

        XCTAssertEqual(runtime.loadedScene?.manifest.name, "spot04")
        XCTAssertFalse(runtime.textureAssetURLs.isEmpty)

        let initialPayload = try SceneRenderPayloadBuilder.makePayload(
            scene: try XCTUnwrap(runtime.loadedScene),
            textureAssetURLs: runtime.textureAssetURLs,
            contentLoader: runtime.contentLoader
        )
        XCTAssertEqual(initialPayload.roomCount, runtime.loadedScene?.rooms.count)
        XCTAssertGreaterThan(initialPayload.vertexCount, 0)
        XCTAssertFalse(initialPayload.textureBindings.isEmpty)

        try assertRenderedSceneHasVisibleGeometry(
            payload: initialPayload,
            expectedSceneName: "spot04"
        )

        let alternateScene = try XCTUnwrap(
            runtime.availableScenes.first { entry in
                guard sceneName(for: entry) != "spot04" else {
                    return false
                }
                guard
                    let scene = try? sceneLoader.loadScene(id: entry.index),
                    let textureAssetURLs = try? sceneLoader.loadTextureAssetURLs(for: scene)
                else {
                    return false
                }
                return textureAssetURLs.isEmpty == false
            },
            "Expected an additional extracted scene with scene-local textures for scene-switch validation."
        )

        await runtime.selectScene(id: alternateScene.index)

        XCTAssertEqual(runtime.selectedSceneID, alternateScene.index)
        XCTAssertEqual(runtime.loadedScene?.manifest.id, alternateScene.index)
        XCTAssertFalse(runtime.textureAssetURLs.isEmpty)

        let alternatePayload = try SceneRenderPayloadBuilder.makePayload(
            scene: try XCTUnwrap(runtime.loadedScene),
            textureAssetURLs: runtime.textureAssetURLs,
            contentLoader: runtime.contentLoader
        )
        XCTAssertGreaterThan(alternatePayload.roomCount, 0)
        XCTAssertGreaterThan(alternatePayload.vertexCount, 0)
        XCTAssertFalse(alternatePayload.textureBindings.isEmpty)

        try assertRenderedSceneHasVisibleGeometry(
            payload: alternatePayload,
            expectedSceneName: sceneName(for: alternateScene)
        )
    }

    func testDeveloperLaunchesTAN52SceneSetWhenConfigured() async throws {
        guard let contentRootPath = ProcessInfo.processInfo.environment["SWIFTOOT_REAL_CONTENT_ROOT"] else {
            throw XCTSkip("Set SWIFTOOT_REAL_CONTENT_ROOT to run the TAN-52 gameplay launch validation.")
        }

        let contentRoot = URL(fileURLWithPath: contentRootPath, isDirectory: true)

        for sceneName in tan52SceneNames {
            let runtime = GameRuntime(
                contentLoader: ContentLoader(contentRoot: contentRoot),
                sceneLoader: SceneLoader(contentRoot: contentRoot),
                suspender: { _ in }
            )

            try await runtime.launchDeveloperScene(
                DeveloperSceneLaunchConfiguration(
                    scene: .name(sceneName),
                    spawnIndex: 0
                )
            )

            XCTAssertEqual(runtime.currentState, .gameplay, "Expected gameplay state for \(sceneName)")
            XCTAssertEqual(runtime.loadedScene?.manifest.name, sceneName, "Loaded wrong scene for \(sceneName)")
            XCTAssertNil(runtime.errorMessage, "Unexpected runtime error for \(sceneName)")
            XCTAssertEqual(
                runtime.playState?.currentSceneID,
                runtime.loadedScene?.manifest.id,
                "Scene ID mismatch for \(sceneName)"
            )

            let initialSnapshot = runtime.developerRuntimeStateSnapshot()
            XCTAssertEqual(initialSnapshot.sceneID, runtime.loadedScene?.manifest.id, "Snapshot scene ID mismatch for \(sceneName)")
            XCTAssertFalse(initialSnapshot.activeRoomIDs.isEmpty, "Expected active rooms for \(sceneName)")
            XCTAssertFalse(initialSnapshot.loadedObjectIDs.isEmpty, "Expected loaded objects for \(sceneName)")
            XCTAssertNotNil(initialSnapshot.player, "Expected spawned player state for \(sceneName)")
            XCTAssertNil(initialSnapshot.errorMessage, "Unexpected snapshot error for \(sceneName)")

            runtime.updateFrame()

            let advancedSnapshot = runtime.developerRuntimeStateSnapshot()
            XCTAssertEqual(advancedSnapshot.sceneID, initialSnapshot.sceneID, "Scene changed unexpectedly for \(sceneName)")
            XCTAssertNil(advancedSnapshot.errorMessage, "Frame advance produced an error for \(sceneName)")
        }
    }

    func testDeveloperHarnessProducesRealContentCaptureWhenConfigured() async throws {
        guard let contentRootPath = ProcessInfo.processInfo.environment["SWIFTOOT_REAL_CONTENT_ROOT"] else {
            throw XCTSkip("Set SWIFTOOT_REAL_CONTENT_ROOT to run the real-content harness validation.")
        }

        let repoRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("docs/developer-harness-script.example.json")
        let outputDirectory = repoRoot.appendingPathComponent("tmp/harness-test", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let configuration = try XCTUnwrap(
            DeveloperHarnessConfiguration.load(
                from: [
                    DeveloperHarnessConfiguration.sceneEnvironmentVariable: "spot04",
                    DeveloperHarnessConfiguration.spawnEnvironmentVariable: "0",
                    DeveloperHarnessConfiguration.timeOfDayEnvironmentVariable: "18.5",
                    DeveloperHarnessConfiguration.inputScriptEnvironmentVariable: scriptURL.path,
                    DeveloperHarnessConfiguration.captureFrameEnvironmentVariable: "tmp/harness-test/frame.png",
                    DeveloperHarnessConfiguration.captureStateEnvironmentVariable: "tmp/harness-test/state.json",
                    DeveloperHarnessConfiguration.captureViewportEnvironmentVariable: "960x540",
                ],
                currentDirectoryURL: repoRoot
            )
        )

        let contentRoot = URL(fileURLWithPath: contentRootPath, isDirectory: true)
        let runtime = GameRuntime(
            contentLoader: ContentLoader(contentRoot: contentRoot),
            sceneLoader: SceneLoader(contentRoot: contentRoot),
            suspender: { _ in }
        )

        try await DeveloperHarnessRunner.run(configuration: configuration, runtime: runtime)

        let frameURL = try XCTUnwrap(configuration.captureFrameURL)
        let stateURL = try XCTUnwrap(configuration.captureStateURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: frameURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))

        let capturedState = try JSONDecoder().decode(
            DeveloperHarnessStateCapture.self,
            from: Data(contentsOf: stateURL)
        )
        XCTAssertEqual(capturedState.runtime.sceneID, runtime.playState?.currentSceneID)
        XCTAssertGreaterThan(capturedState.render.drawCallCount, 0)
    }

    func testRealExtractedSpot02RendersTexturedSkyboxWhenConfigured() throws {
        guard let contentRootPath = ProcessInfo.processInfo.environment["SWIFTOOT_REAL_CONTENT_ROOT"] else {
            throw XCTSkip("Set SWIFTOOT_REAL_CONTENT_ROOT to run the real-content skybox validation.")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let contentRoot = URL(fileURLWithPath: contentRootPath, isDirectory: true)
        let sceneLoader = SceneLoader(contentRoot: contentRoot)
        let contentLoader = ContentLoader(contentRoot: contentRoot)
        let scene = try sceneLoader.loadScene(named: "spot02")
        let textureAssetURLs = try sceneLoader.loadTextureAssetURLs(for: scene)

        XCTAssertEqual(scene.environment?.skybox.skyboxID, 1)
        XCTAssertEqual(scene.environment?.skybox.skyboxConfig, 1)
        XCTAssertEqual(scene.environment?.skybox.environmentLightingMode, "LIGHT_MODE_TIME")
        XCTAssertEqual(
            scene.environment?.resolvedSkybox?.states.first(where: { $0.id == "day-overcast" })?.faces.first?.assetName,
            "gDayOvercastSkybox1Tex"
        )
        XCTAssertNotNil(textureAssetURLs[OOTAssetID.stableID(for: "gDayOvercastSkybox1Tex")])

        let payload = try SceneRenderPayloadBuilder.makePayload(
            scene: scene,
            textureAssetURLs: textureAssetURLs,
            contentLoader: contentLoader
        )

        var renderScene = SceneRenderPayloadBuilder.renderScene(from: payload, playerState: nil)
        let renderer = try OOTRenderer(
            scene: renderScene,
            textureBindings: payload.textureBindings,
            gameplayCameraConfiguration: payload.gameplayCameraConfiguration
        )
        let renderTarget = try makeRenderTargetTexture(device: renderer.device)
        let viewportSize = CGSize(width: renderTarget.width, height: renderTarget.height)
        let frameUniforms: FrameUniforms
        let skyboxViewProjection: simd_float4x4
        if let gameplayCameraController = renderer.gameplayCameraController {
            gameplayCameraController.updateViewportSize(viewportSize)
            frameUniforms = gameplayCameraController.frameUniforms()
            skyboxViewProjection = renderer.skyboxViewProjection(
                from: gameplayCameraController.cameraMatrices()
            )
        } else {
            renderer.orbitCameraController.updateViewportSize(viewportSize)
            frameUniforms = renderer.orbitCameraController.frameUniforms()
            skyboxViewProjection = renderer.skyboxViewProjection(
                from: renderer.orbitCameraController.cameraMatrices()
            )
        }
        renderer.setTimeOfDay(12.0)

        try renderer.renderCurrentSceneToTexture(
            renderTarget,
            frameUniforms: frameUniforms,
            skyboxViewProjection: skyboxViewProjection
        )

        renderScene.environment?.resolvedSkybox = nil
        let noSkyboxRenderer = try OOTRenderer(
            scene: renderScene,
            textureBindings: payload.textureBindings,
            gameplayCameraConfiguration: payload.gameplayCameraConfiguration
        )
        let noSkyboxRenderTarget = try makeRenderTargetTexture(device: noSkyboxRenderer.device)
        let noSkyboxViewportSize = CGSize(width: noSkyboxRenderTarget.width, height: noSkyboxRenderTarget.height)
        let noSkyboxFrameUniforms: FrameUniforms
        let noSkyboxViewProjection: simd_float4x4
        if let gameplayCameraController = noSkyboxRenderer.gameplayCameraController {
            gameplayCameraController.updateViewportSize(noSkyboxViewportSize)
            noSkyboxFrameUniforms = gameplayCameraController.frameUniforms()
            noSkyboxViewProjection = noSkyboxRenderer.skyboxViewProjection(
                from: gameplayCameraController.cameraMatrices()
            )
        } else {
            noSkyboxRenderer.orbitCameraController.updateViewportSize(noSkyboxViewportSize)
            noSkyboxFrameUniforms = noSkyboxRenderer.orbitCameraController.frameUniforms()
            noSkyboxViewProjection = noSkyboxRenderer.skyboxViewProjection(
                from: noSkyboxRenderer.orbitCameraController.cameraMatrices()
            )
        }
        noSkyboxRenderer.setTimeOfDay(12.0)

        try noSkyboxRenderer.renderCurrentSceneToTexture(
            noSkyboxRenderTarget,
            frameUniforms: noSkyboxFrameUniforms,
            skyboxViewProjection: noSkyboxViewProjection
        )

        let differingUpperBandSamples = countDifferingPixels(
            lhs: renderTarget,
            rhs: noSkyboxRenderTarget,
            widthStride: 16,
            heightStride: 8,
            maxY: renderTarget.height / 3
        )

        XCTAssertTrue(
            differingUpperBandSamples > 0,
            "Expected the real spot02 render to change upper-frame pixels when resolved skybox textures are enabled."
        )
    }
}

private extension OOTUITests {
    func makeLoadedScene() -> LoadedScene {
        LoadedScene(
            manifest: SceneManifest(
                id: 4,
                name: "spot04",
                title: "Kokiri Forest",
                rooms: [
                    RoomManifest(id: 0, name: "spot04_room_0", directory: "spot04"),
                    RoomManifest(id: 1, name: "spot04_room_1", directory: "spot04"),
                ]
            ),
            collision: CollisionMesh(
                vertices: [
                    Vector3s(x: -100, y: 0, z: -100),
                    Vector3s(x: 100, y: 0, z: -100),
                    Vector3s(x: -100, y: 0, z: 100),
                    Vector3s(x: 100, y: 0, z: 100),
                    Vector3s(x: -100, y: 80, z: -100),
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
                        surfaceType: 0,
                        vertexA: 0,
                        vertexB: 4,
                        vertexC: 1,
                        normal: Vector3s(x: 0x7FFF, y: 0, z: 0),
                        distance: 0
                    ),
                ],
                surfaceTypes: [CollisionSurfaceType(low: 0, high: 0)]
            ),
            spawns: SceneSpawnsFile(
                sceneName: "spot04",
                spawns: [
                    SceneSpawnPoint(
                        index: 0,
                        position: Vector3s(x: 100, y: 20, z: -40),
                        rotation: Vector3s(x: 0, y: 0x4000, z: 0),
                        params: 0
                    ),
                ]
            ),
            rooms: [
                LoadedSceneRoom(
                    manifest: RoomManifest(id: 0, name: "spot04_room_0", directory: "spot04"),
                    displayList: [],
                    vertexData: Data()
                ),
            ]
        )
    }

    func sceneName(for entry: SceneTableEntry) -> String {
        if entry.segmentName.hasSuffix("_scene") {
            return String(entry.segmentName.dropLast("_scene".count))
        }
        return entry.segmentName
    }

    var tan52SceneNames: [String] {
        [
            "spot00", "spot01", "spot02", "spot03", "spot04", "spot05", "spot06", "spot07", "spot08", "spot09",
            "spot10", "spot11", "spot15", "spot16", "spot17", "spot18", "spot20",
            "entra", "entra_n", "market_day", "market_night", "market_alley", "market_alley_n",
            "shrine", "shrine_n", "hairal_niwa", "hairal_niwa_n", "nakaniwa", "miharigoya",
            "link_home", "kokiri_home", "kokiri_home3", "kokiri_home4", "kokiri_home5",
            "kakariko", "kakariko3", "impa", "labo", "hylia_labo", "hut", "souko", "malon_stable", "tent",
            "shop1", "kokiri_shop", "golon", "zoora", "drag", "alley_shop", "night_shop", "face_shop",
            "daiyousei_izumi", "yousei_izumi_tate", "yousei_izumi_yoko", "mahouya",
        ]
    }

    func assertRenderedSceneHasVisibleGeometry(
        payload: SceneRenderPayload,
        expectedSceneName: String
    ) throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        var reportedStats = SceneFrameStats()
        let renderer = try OOTRenderer(
            scene: SceneRenderPayloadBuilder.renderScene(from: payload, playerState: nil),
            textureBindings: payload.textureBindings
        ) { stats in
            reportedStats = stats
        }
        let renderTarget = try makeRenderTargetTexture(device: renderer.device)
        renderer.orbitCameraController.updateViewportSize(
            CGSize(width: renderTarget.width, height: renderTarget.height)
        )

        try renderer.renderCurrentSceneToTexture(
            renderTarget,
            frameUniforms: renderer.orbitCameraController.frameUniforms()
        )

        XCTAssertEqual(reportedStats.roomCount, payload.roomCount, "Unexpected room count for \(expectedSceneName)")
        XCTAssertGreaterThan(reportedStats.vertexCount, 0, "Expected rendered vertices for \(expectedSceneName)")
        XCTAssertGreaterThan(reportedStats.drawCallCount, 0, "Expected draw calls for \(expectedSceneName)")
        XCTAssertTrue(
            textureContainsNonClearPixel(renderTarget),
            "Expected \(expectedSceneName) to render geometry beyond the clear color."
        )
    }

    func makeRenderTargetTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 512,
            height: 512,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared

        return try XCTUnwrap(
            device.makeTexture(descriptor: descriptor),
            "Failed to allocate offscreen render target."
        )
    }

    func textureContainsNonClearPixel(_ texture: MTLTexture) -> Bool {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )

        let clearPixel: [UInt8] = [52, 155, 45, 255]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            if Array(bytes[offset..<(offset + 4)]) != clearPixel {
                return true
            }
        }

        return false
    }

    func pixel(in texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return bytes
    }

    func bgraBytes(_ color: MTLClearColor) -> [UInt8] {
        [
            UInt8((color.blue * 255.0).rounded()),
            UInt8((color.green * 255.0).rounded()),
            UInt8((color.red * 255.0).rounded()),
            UInt8((color.alpha * 255.0).rounded()),
        ]
    }

    func countDifferingPixels(
        lhs: MTLTexture,
        rhs: MTLTexture,
        widthStride: Int,
        heightStride: Int,
        maxY: Int
    ) -> Int {
        var count = 0
        for y in stride(from: 0, to: maxY, by: heightStride) {
            for x in stride(from: 0, to: lhs.width, by: widthStride) {
                if pixel(in: lhs, x: x, y: y) != pixel(in: rhs, x: x, y: y) {
                    count += 1
                }
            }
        }
        return count
    }

    func makeKeyEvent(type: NSEvent.EventType, character: String, keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

private struct UITestSceneLoader: SceneLoading {
    func loadSceneTableEntries() throws -> [SceneTableEntry] { [] }
    func resolveSceneDirectory(for sceneID: Int) throws -> URL { URL(fileURLWithPath: "/tmp", isDirectory: true) }
    func loadScene(id: Int) throws -> LoadedScene { throw ContentLoaderError.sceneLoadingUnavailable }
    func loadScene(named name: String) throws -> LoadedScene { throw ContentLoaderError.sceneLoadingUnavailable }
    func loadTextureAssetURLs(for scene: LoadedScene) throws -> [UInt32 : URL] { [:] }
    func loadSceneManifest(id: Int) throws -> SceneManifest { throw ContentLoaderError.sceneLoadingUnavailable }
    func loadSceneManifest(named name: String) throws -> SceneManifest { throw ContentLoaderError.sceneLoadingUnavailable }
    func loadActorTable() throws -> [ActorTableEntry] { [] }
    func loadObjectTable() throws -> [ObjectTableEntry] { [] }
    func loadObject(named name: String) throws -> LoadedObject { throw ContentLoaderError.sceneLoadingUnavailable }
    func loadEntranceTable() throws -> [EntranceTableEntry] { [] }
    func loadCollisionMesh(for manifest: SceneManifest) throws -> CollisionMesh? { nil }
    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] { [] }
    func loadRoomVertexData(for room: RoomManifest) throws -> Data { Data() }
}

private struct StubContentLoader: ContentLoading {
    func loadInitialContent() async throws {}
}

private struct HUDArtContentLoader: ContentLoading {
    let object: LoadedObject

    func loadInitialContent() async throws {}

    func loadObject(named name: String) throws -> LoadedObject {
        object
    }
}

@MainActor
private final class TestSkeletonActor: BaseActor, SkeletonRenderableActor {
    let renderState: ActorSkeletonRenderState

    init(renderState: ActorSkeletonRenderState) {
        self.renderState = renderState
        super.init(
            profile: ActorProfile(id: 1, category: ActorCategory.enemy.rawValue, flags: 0, objectID: 0),
            category: .enemy,
            position: Vec3f(x: 0, y: 0, z: 0)
        )
    }

    var skeletonRenderState: ActorSkeletonRenderState? {
        renderState
    }
}

private func makeSkeletonTestObject() -> LoadedObject {
    LoadedObject(
        manifest: ObjectManifest(name: "test_object"),
        skeletonsByName: [
            "gDekuBabaSkel": SkeletonData(
                type: .normal,
                limbs: [
                    LimbData(translation: Vector3s(x: 0, y: 0, z: 0)),
                ]
            ),
        ],
        animationsByName: [
            "gDekuBabaFastChompAnim": ObjectAnimationData(
                name: "gDekuBabaFastChompAnim",
                kind: .standard,
                frameCount: 4,
                values: [0, 0, 0],
                limbCount: 1
            ),
        ]
    )
}
