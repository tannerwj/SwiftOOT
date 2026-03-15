import SwiftUI
import OOTCore
import OOTUI

struct OOTMacRootView: View {
    @State
    private var runtime = GameRuntime()

    var body: some View {
        OOTAppView(runtime: runtime)
    }
}
