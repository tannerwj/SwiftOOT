import SwiftUI
import OOTCore
import OOTUI

struct OOTMacRootView: View {
    @State
    private var runtime = GameRuntime()

    var body: some View {
        OOTAppView(
            availableScenes: runtime.availableScenes,
            selectedSceneID: runtime.selectedSceneID,
            isLoading: runtime.state == .loadingContent,
            errorMessage: runtime.errorMessage,
            loadedScene: runtime.loadedScene,
            textureAssetURLs: runtime.textureAssetURLs
        ) { sceneID in
            Task {
                await runtime.selectScene(id: sceneID)
            }
        }
        .task {
            await runtime.bootstrapSceneViewer()
        }
    }
}
