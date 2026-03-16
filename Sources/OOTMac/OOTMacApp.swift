import SwiftUI

@main
struct OOTMacApp: App {
    @State
    private var bootstrapModel = OOTContentBootstrapModel()

    var body: some Scene {
        WindowGroup("SwiftOOT") {
            OOTMacRootView(bootstrapModel: bootstrapModel)
                .frame(minWidth: 960, minHeight: 540)
        }
    }
}
