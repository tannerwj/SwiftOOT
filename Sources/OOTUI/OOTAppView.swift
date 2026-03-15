import SwiftUI
import OOTCore
import OOTRender

enum OOTRootViewState: Equatable {
    case boot
    case consoleLogo
    case titleScreen
    case fileSelect
    case gameplay
}

public struct OOTAppView: View {
    let runtime: GameRuntime

    public init(runtime: GameRuntime) {
        self.runtime = runtime
    }

    nonisolated static func rootViewState(for state: GameState) -> OOTRootViewState {
        switch state {
        case .boot:
            return .boot
        case .consoleLogo:
            return .consoleLogo
        case .titleScreen:
            return .titleScreen
        case .fileSelect:
            return .fileSelect
        case .gameplay:
            return .gameplay
        }
    }

    public var body: some View {
        Group {
            switch Self.rootViewState(for: runtime.currentState) {
            case .boot:
                RuntimeSplashView(
                    title: "SwiftOOT",
                    subtitle: "Booting the engine..."
                )
            case .consoleLogo:
                RuntimeSplashView(
                    title: "N64",
                    subtitle: "Console logo sequence"
                )
            case .titleScreen:
                TitleScreenView(runtime: runtime)
            case .fileSelect:
                FileSelectView(runtime: runtime)
            case .gameplay:
                GameplayShellView(runtime: runtime)
            }
        }
        .task {
            await runtime.start()
        }
    }
}

private struct RuntimeSplashView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.08, green: 0.12, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct TitleScreenView: View {
    let runtime: GameRuntime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.19, blue: 0.14), Color(red: 0.33, green: 0.15, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("The Legend of SwiftOOT")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("A simplified title flow with Link and Epona standing in for the final cinematic.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: 540)
                }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        VStack(spacing: 10) {
                            Text("Link + Epona")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Animated hero presentation placeholder")
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .frame(width: 420, height: 220)

                VStack(spacing: 14) {
                    Button(TitleMenuOption.newGame.title) {
                        runtime.chooseTitleOption(.newGame)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(TitleMenuOption.continueGame.title) {
                        runtime.chooseTitleOption(.continueGame)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!runtime.canContinue)
                }

                if let statusMessage = runtime.statusMessage {
                    Text(statusMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.98, green: 0.87, blue: 0.44))
                }

                Spacer()
            }
            .padding(32)
        }
    }
}

private struct FileSelectView: View {
    let runtime: GameRuntime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.14, green: 0.25, blue: 0.31)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(runtime.fileSelectMode?.title ?? "Choose a File")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    ForEach(Array(runtime.saveContext.slots.enumerated()), id: \.element.id) { index, slot in
                        Button {
                            runtime.selectSaveSlot(index)
                            runtime.confirmSelectedSaveSlot()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("File \(index + 1)")
                                        .font(.headline)
                                    Text(slot.playerName)
                                        .font(.title3.weight(.semibold))
                                    Text(slot.hasSaveData ? slot.locationName : "Empty slot")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(slot.hasSaveData ? "\(slot.hearts) Hearts" : "New")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(index == runtime.saveContext.selectedSlotIndex ? .white.opacity(0.24) : .white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(runtime.fileSelectMode == .continueGame && !slot.hasSaveData)
                    }
                }
                .frame(maxWidth: 520)

                HStack(spacing: 16) {
                    Button("Back") {
                        runtime.returnToTitleScreen()
                    }
                    .buttonStyle(.bordered)

                    if let statusMessage = runtime.statusMessage {
                        Text(statusMessage)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color(red: 0.98, green: 0.87, blue: 0.44))
                    }
                }
            }
            .padding(32)
        }
    }
}

private struct GameplayShellView: View {
    let runtime: GameRuntime

    @State
    private var renderPayload: SceneRenderPayload?

    @State
    private var frameStats = SceneFrameStats()

    @State
    private var renderErrorMessage: String?

    @State
    private var inputManager: InputManager?

    var body: some View {
        NavigationSplitView {
            DebugSidebar(
                availableScenes: runtime.availableScenes,
                selectedSceneID: runtime.selectedSceneID,
                loadedScene: runtime.loadedScene,
                isLoading: runtime.sceneViewerState == .loadingContent,
                errorMessage: activeErrorMessage,
                drawCallCount: frameStats.drawCallCount,
                onSelectScene: { sceneID in
                    Task {
                        await runtime.selectScene(id: sceneID)
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                if let renderPayload {
                    MetalView(
                        sceneIdentity: renderPayload.sceneID,
                        scene: SceneRenderPayloadBuilder.renderScene(
                            from: renderPayload,
                            playerState: runtime.playerState
                        ),
                        textureBindings: renderPayload.textureBindings,
                        inputHandler: inputManager
                    ) { stats in
                        frameStats = stats
                    }
                    .id(renderPayload.sceneID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Text("Scene Viewer")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(detailPlaceholderText)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(24)
                }

                if let playState = runtime.playState {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gameplay Runtime")
                            .font(.headline.weight(.bold))
                        Text("\(playState.playerName) in \(playState.currentSceneName)")
                        Text("Save Slot \(playState.activeSaveSlot + 1)")
                            .foregroundStyle(.secondary)
                        if let playerState = runtime.playerState {
                            Text("Locomotion: \(playerState.locomotionState.rawValue)")
                            Text(
                                String(
                                    format: "Position: %.1f %.1f %.1f",
                                    playerState.position.x,
                                    playerState.position.y,
                                    playerState.position.z
                                )
                            )
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
                }

                VStack(spacing: 16) {
                    Spacer()

                    if let presentation = runtime.activeMessagePresentation {
                        MessageView(presentation: presentation)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let actionLabel = runtime.gameplayActionLabel {
                        ActionPromptView(label: actionLabel)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .task {
            await runtime.bootstrapSceneViewer()
        }
        .task {
            if inputManager == nil {
                inputManager = InputManager(runtime: runtime)
            }

            while !Task.isCancelled && runtime.currentState == .gameplay {
                inputManager?.sync()
                runtime.updateFrame()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .task(id: renderTaskID) {
            await refreshRenderPayload()
        }
    }
}

private extension GameplayShellView {
    var activeErrorMessage: String? {
        renderErrorMessage ?? runtime.errorMessage
    }

    var detailPlaceholderText: String {
        if let errorMessage = activeErrorMessage, errorMessage.isEmpty == false {
            return errorMessage
        }
        if runtime.sceneViewerState == .loadingContent {
            return "Loading Kokiri Forest..."
        }
        return "Select an extracted scene to begin rendering."
    }

    var renderTaskID: String {
        let sceneID = runtime.loadedScene?.manifest.id ?? -1
        let playerStateMarker = runtime.playerState == nil ? "no-player" : "player"
        return "\(sceneID)-\(runtime.textureAssetURLs.count)-\(playerStateMarker)"
    }

    @MainActor
    func refreshRenderPayload() async {
        guard let loadedScene = runtime.loadedScene else {
            renderPayload = nil
            frameStats = SceneFrameStats()
            renderErrorMessage = nil
            return
        }

        do {
            let payload = try SceneRenderPayloadBuilder.makePayload(
                scene: loadedScene,
                textureAssetURLs: runtime.textureAssetURLs,
                contentLoader: runtime.contentLoader
            )
            renderPayload = payload
            frameStats = SceneFrameStats(
                roomCount: payload.roomCount,
                vertexCount: payload.vertexCount
            )
            renderErrorMessage = nil
        } catch {
            renderPayload = nil
            frameStats = SceneFrameStats()
            renderErrorMessage = error.localizedDescription
        }
    }

}
