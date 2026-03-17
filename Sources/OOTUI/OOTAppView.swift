import AppKit
import Foundation
import SwiftUI
import OOTCore
import OOTDataModel
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
    let developerHarness: DeveloperHarnessConfiguration?
    let startupManagedExternally: Bool

    public init(
        runtime: GameRuntime,
        developerHarness: DeveloperHarnessConfiguration? = nil,
        startupManagedExternally: Bool = false
    ) {
        self.runtime = runtime
        self.developerHarness = developerHarness
        self.startupManagedExternally = startupManagedExternally
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
            guard !startupManagedExternally else {
                return
            }

            do {
                if let developerHarness, developerHarness.isEnabled {
                    try await DeveloperHarnessRunner.run(
                        configuration: developerHarness,
                        runtime: runtime,
                        log: writeHarnessNoteToStderr
                    )
                    if developerHarness.captureRequested {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    await runtime.start()
                }
            } catch {
                runtime.errorMessage = error.localizedDescription
                writeHarnessFailureToStderr(error.localizedDescription)
                if developerHarness?.captureRequested == true {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

private extension OOTAppView {
    func writeHarnessFailureToStderr(_ message: String) {
        let line = "SwiftOOT harness failed: \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
        appendHarnessTrace(line)
    }

    func writeHarnessNoteToStderr(_ message: String) {
        let line = "SwiftOOT harness: \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
        appendHarnessTrace(line)
    }

    func appendHarnessTrace(_ line: String) {
        guard
            let directory = (developerHarness?.captureStateURL ?? developerHarness?.captureFrameURL)?
                .deletingLastPathComponent()
        else {
            return
        }

        let fileManager = FileManager.default
        let logURL = directory.appendingPathComponent("harness.log")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
            return
        }

        try? Data(line.utf8).write(to: logURL, options: .atomic)
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

    @State
    private var updateFrameTimeMilliseconds = 0.0

    @State
    private var framesPerSecond = 0.0

    @State
    private var lastRenderedFrameTimestamp: TimeInterval?

    @State
    private var objectTableByID: [Int: ObjectTableEntry] = [:]

    @State
    private var selectedActorID: ObjectIdentifier?

    @State
    private var xrayOverlaySettings = XRayOverlaySettings()

    @State
    private var renderSettings = RenderSettings()

    @State
    private var selectedDebuggerTab: DebugSidebarTab = .actorInspector

    var body: some View {
        NavigationSplitView {
            DebugSidebar(
                runtime: runtime,
                frameStats: frameStats,
                updateFrameTimeMilliseconds: updateFrameTimeMilliseconds,
                framesPerSecond: framesPerSecond,
                errorMessage: activeErrorMessage,
                objectTableByID: objectTableByID,
                selectedActorID: $selectedActorID,
                xrayOverlaySettings: $xrayOverlaySettings,
                renderSettings: $renderSettings,
                selectedTab: $selectedDebuggerTab,
                onSelectScene: { sceneID in
                    Task {
                        await runtime.selectScene(id: sceneID)
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .topLeading) {
                if selectedDebuggerTab == .map {
                    HyruleWorldMapScreen(
                        runtime: runtime,
                        onSelectScene: { sceneID in
                            Task {
                                await runtime.selectScene(id: sceneID)
                            }
                        }
                    )
                } else {
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.9)
                            .ignoresSafeArea()

                        if let renderPayload {
                            MetalView(
                                sceneIdentity: renderPayload.sceneID,
                                scene: SceneRenderPayloadBuilder.renderScene(
                                    from: renderPayload,
                                    playerState: runtime.playerState,
                                    inventoryContext: runtime.inventoryContext,
                                    actors: runtime.actors,
                                    xrayTelemetrySnapshot: runtime.xrayTelemetrySnapshot,
                                    xrayOverlaySettings: xrayOverlaySettings
                                ),
                                timeOfDay: runtime.gameTime.timeOfDay,
                                textureBindings: renderPayload.textureBindings,
                                renderSettings: renderSettings,
                                inputHandler: inputManager,
                                toggleAllXRayLayers: {
                                    xrayOverlaySettings.toggleAll()
                                },
                                gameplayCameraConfiguration: runtime.loadedScene.flatMap {
                                    SceneRenderPayloadBuilder.makeGameplayCameraConfiguration(
                                        scene: $0,
                                        playerState: runtime.playerState,
                                        combatState: runtime.combatState,
                                        itemGetSequence: runtime.itemGetSequence,
                                        itemAimYaw: runtime.itemAimYaw,
                                        itemAimPitch: runtime.itemAimPitch
                                    )
                                }
                            ) { stats in
                                let now = ProcessInfo.processInfo.systemUptime
                                Task { @MainActor in
                                    frameStats = stats
                                    framesPerSecond = smoothedMetric(
                                        current: framesPerSecond,
                                        newValue: instantaneousFramesPerSecond(at: now)
                                    )
                                    lastRenderedFrameTimestamp = now
                                    syncSelectedActorSelection()
                                }
                            }
                            .id(renderPayload.sceneID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay {
                                ActorViewportSelectionOverlay(
                                    actors: runtime.actors,
                                    sceneBounds: renderPayload.baseScene.sceneBounds,
                                    cameraConfiguration: renderPayload.gameplayCameraConfiguration,
                                    selectedActorID: $selectedActorID
                                )
                            }
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

                        if runtime.playState != nil, runtime.isPauseMenuPresented == false {
                            GameplayHUDView(runtime: runtime, renderPayload: renderPayload)
                                .transition(.opacity)
                        }

                        if runtime.isPauseMenuPresented {
                            PauseMenuView(runtime: runtime)
                                .transition(.opacity)
                        }

                        if runtime.playState != nil, runtime.availableChildCButtonItems.isEmpty == false {
                            VStack(alignment: .trailing, spacing: 12) {
                                CButtonLoadoutEditorShortcut(runtime: runtime)

                                if runtime.isCButtonItemEditorPresented {
                                    CButtonLoadoutEditorOverlay(runtime: runtime)
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                            .padding(.top, 24)
                            .padding(.trailing, 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }

                        if let itemGetOverlay = runtime.activeItemGetOverlay, runtime.isPauseMenuPresented == false {
                            ItemGetView(state: itemGetOverlay)
                                .padding(.top, 28)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        VStack(spacing: 16) {
                            Spacer()

                            if runtime.isPauseMenuPresented {
                                EmptyView()
                            } else if let presentation = runtime.activeMessagePresentation {
                                MessageView(presentation: presentation)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else if runtime.isCButtonItemEditorPresented == false, let actionLabel = runtime.gameplayActionLabel {
                                ActionPromptView(label: actionLabel)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .task {
            await runtime.bootstrapSceneViewer()
        }
        .task {
            await loadObjectTableIfAvailable()
        }
        .task {
            if inputManager == nil {
                inputManager = InputManager(runtime: runtime)
            }

            while !Task.isCancelled && runtime.currentState == .gameplay {
                let updateStart = DispatchTime.now().uptimeNanoseconds
                inputManager?.sync(frame: runtime.gameTime.frameCount)
                runtime.updateFrame()
                let updateDuration = Double(DispatchTime.now().uptimeNanoseconds - updateStart) / 1_000_000
                updateFrameTimeMilliseconds = smoothedMetric(
                    current: updateFrameTimeMilliseconds,
                    newValue: updateDuration
                )
                syncSelectedActorSelection()
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
            syncSelectedActorSelection()
        } catch {
            renderPayload = nil
            frameStats = SceneFrameStats()
            renderErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadObjectTableIfAvailable() async {
        guard objectTableByID.isEmpty else {
            return
        }

        guard let table = try? runtime.contentLoader.loadObjectTable() else {
            return
        }

        objectTableByID = Dictionary(uniqueKeysWithValues: table.map { ($0.id, $0) })
    }

    func instantaneousFramesPerSecond(at now: TimeInterval) -> Double {
        guard let lastRenderedFrameTimestamp else {
            return framesPerSecond
        }

        let delta = now - lastRenderedFrameTimestamp
        guard delta > 0.000_1 else {
            return framesPerSecond
        }

        return 1.0 / delta
    }

    func smoothedMetric(
        current: Double,
        newValue: Double
    ) -> Double {
        guard newValue.isFinite, newValue > 0 else {
            return current
        }

        if current == 0 {
            return newValue
        }

        return (current * 0.82) + (newValue * 0.18)
    }

    func syncSelectedActorSelection() {
        let actors = runtime.actors
        let actorIDs = Set(actors.map { ObjectIdentifier($0 as AnyObject) })

        guard actorIDs.isEmpty == false else {
            selectedActorID = nil
            return
        }

        if let selectedActorID, actorIDs.contains(selectedActorID) {
            return
        }

        selectedActorID = actors.first.map { ObjectIdentifier($0 as AnyObject) }
    }
}
