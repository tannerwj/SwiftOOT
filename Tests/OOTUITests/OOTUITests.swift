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
        let runtime = GameRuntime(
            contentLoader: ContentLoader(contentRoot: contentRoot),
            sceneLoader: SceneLoader(contentRoot: contentRoot),
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
            runtime.availableScenes.first(where: { sceneName(for: $0) != "spot04" }),
            "Expected at least one additional extracted scene for scene-switch validation."
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
