import SwiftUI
import OOTContent
import OOTDataModel
import OOTRender

public struct OOTAppView: View {
    private let availableScenes: [SceneTableEntry]
    private let selectedSceneID: Int?
    private let isLoading: Bool
    private let errorMessage: String?
    private let loadedScene: LoadedScene?
    private let textureAssetURLs: [UInt32: URL]
    private let onSelectScene: @Sendable (Int) -> Void

    @State
    private var renderPayload: SceneRenderPayload?

    @State
    private var frameStats = SceneFrameStats()

    @State
    private var renderErrorMessage: String?

    public init(
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        loadedScene: LoadedScene? = nil,
        textureAssetURLs: [UInt32: URL] = [:],
        onSelectScene: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.onSelectScene = onSelectScene
    }

    public var body: some View {
        NavigationSplitView {
            DebugSidebar(
                availableScenes: availableScenes,
                selectedSceneID: selectedSceneID,
                loadedScene: loadedScene,
                isLoading: isLoading,
                errorMessage: activeErrorMessage,
                drawCallCount: frameStats.drawCallCount,
                onSelectScene: onSelectScene
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                if let renderPayload {
                    MetalView(
                        sceneIdentity: renderPayload.sceneID,
                        scene: renderPayload.renderScene,
                        textureBindings: renderPayload.textureBindings
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
            }
        }
        .task(id: renderTaskID) {
            await refreshRenderPayload()
        }
    }
}

private extension OOTAppView {
    var activeErrorMessage: String? {
        renderErrorMessage ?? errorMessage
    }

    var detailPlaceholderText: String {
        if let errorMessage = activeErrorMessage, errorMessage.isEmpty == false {
            return errorMessage
        }
        if isLoading {
            return "Loading Kokiri Forest..."
        }
        return "Select an extracted scene to begin rendering."
    }

    var renderTaskID: String {
        let sceneID = loadedScene?.manifest.id ?? -1
        return "\(sceneID)-\(textureAssetURLs.count)"
    }

    @MainActor
    func refreshRenderPayload() async {
        guard let loadedScene else {
            renderPayload = nil
            frameStats = SceneFrameStats()
            renderErrorMessage = nil
            return
        }

        do {
            let payload = try SceneRenderPayloadBuilder.makePayload(
                scene: loadedScene,
                textureAssetURLs: textureAssetURLs
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
