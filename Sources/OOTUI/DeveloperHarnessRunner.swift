import Foundation
import OOTCore
import OOTRender

public enum DeveloperHarnessRunner {
    @MainActor
    public static func run(
        configuration harness: DeveloperHarnessConfiguration,
        runtime: GameRuntime,
        log: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws {
        log("starting developer harness")
        try await runtime.launchDeveloperScene(harness.launchConfiguration)
        log("developer scene launched")

        guard harness.inputScript != nil || harness.captureRequested else {
            return
        }

        while runtime.gameTime.frameCount < harness.captureTriggerFrame {
            runtime.setControllerInput(harness.inputScript?.inputState(for: runtime.gameTime.frameCount) ?? ControllerInputState())
            runtime.updateFrame()
            await Task.yield()
        }
        runtime.setControllerInput(ControllerInputState())
        log("scripted frames completed at frame \(runtime.gameTime.frameCount)")

        guard harness.captureRequested else {
            return
        }

        try captureOutputs(harness: harness, runtime: runtime)
        log("capture outputs written")
    }

    @MainActor
    private static func captureOutputs(
        harness: DeveloperHarnessConfiguration,
        runtime: GameRuntime
    ) throws {
        guard let loadedScene = runtime.loadedScene else {
            throw DeveloperHarnessCaptureError.invalidRuntimeState("No scene is loaded for capture.")
        }

        let renderPayload = try SceneRenderPayloadBuilder.makePayload(
            scene: loadedScene,
            textureAssetURLs: runtime.textureAssetURLs,
            contentLoader: runtime.contentLoader
        )
        let renderScene = SceneRenderPayloadBuilder.renderScene(
            from: renderPayload,
            playerState: runtime.playerState
        )
        let renderer = try OOTRenderer(
            scene: renderScene,
            textureBindings: renderPayload.textureBindings,
            gameplayCameraConfiguration: SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                scene: loadedScene,
                playerState: runtime.playerState
            )
        )
        renderer.setTimeOfDay(runtime.gameTime.timeOfDay)

        let renderCapture = try renderer.captureCurrentScene(size: harness.captureViewport.size)
        let runtimeSnapshot = runtime.developerRuntimeStateSnapshot()

        if let frameURL = harness.captureFrameURL {
            try DeveloperHarnessCaptureWriter.writeFrameCapture(
                renderCapture,
                to: frameURL
            )
        }

        if let stateURL = harness.captureStateURL {
            try DeveloperHarnessCaptureWriter.writeStateCapture(
                runtimeSnapshot: runtimeSnapshot,
                renderCapture: renderCapture,
                to: stateURL
            )
        }
    }
}
