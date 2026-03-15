import XCTest
import Metal
import OOTContent
import OOTCore
import OOTDataModel
@testable import OOTRender
@testable import OOTUI

@MainActor
final class OOTUITests: XCTestCase {
    func testAppViewCompiles() async {
        await MainActor.run {
            _ = OOTAppView(runtime: GameRuntime(suspender: { _ in }))
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
        }
    }

    func testRootViewStateMatchesRuntimeState() {
        XCTAssertEqual(OOTAppView.rootViewState(for: .boot), .boot)
        XCTAssertEqual(OOTAppView.rootViewState(for: .consoleLogo), .consoleLogo)
        XCTAssertEqual(OOTAppView.rootViewState(for: .titleScreen), .titleScreen)
        XCTAssertEqual(OOTAppView.rootViewState(for: .fileSelect), .fileSelect)
        XCTAssertEqual(OOTAppView.rootViewState(for: .gameplay), .gameplay)
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
            textureAssetURLs: runtime.textureAssetURLs
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
            textureAssetURLs: runtime.textureAssetURLs
        )
        XCTAssertGreaterThan(alternatePayload.roomCount, 0)
        XCTAssertGreaterThan(alternatePayload.vertexCount, 0)
        XCTAssertFalse(alternatePayload.textureBindings.isEmpty)

        try assertRenderedSceneHasVisibleGeometry(
            payload: alternatePayload,
            expectedSceneName: sceneName(for: alternateScene)
        )
    }
}

private extension OOTUITests {
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
            scene: payload.renderScene,
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
}
