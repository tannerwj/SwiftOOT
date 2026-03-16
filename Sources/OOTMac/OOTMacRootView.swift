import SwiftUI
import OOTUI

struct OOTMacRootView: View {
    @State
    private var bootstrapModel = OOTContentBootstrapModel()

    var body: some View {
        Group {
            if let runtime = bootstrapModel.runtime {
                OOTAppView(
                    runtime: runtime,
                    developerHarness: bootstrapModel.developerHarnessConfiguration
                )
            } else {
                OOTContentBootstrapView(model: bootstrapModel)
            }
        }
    }
}
