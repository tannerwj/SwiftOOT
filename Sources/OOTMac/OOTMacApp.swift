import SwiftUI
import OOTCore
import OOTUI

@main
struct OOTMacApp: App {
    @State private var runtime = GameRuntime()

    var body: some Scene {
        WindowGroup("SwiftOOT") {
            OOTAppView(runtime: runtime)
                .frame(minWidth: 960, minHeight: 540)
        }
    }
}
