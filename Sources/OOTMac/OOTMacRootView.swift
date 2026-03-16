import SwiftUI
import OOTUI

struct OOTMacRootView: View {
    let bootstrapModel: OOTContentBootstrapModel

    var body: some View {
        Group {
            if let runtime = bootstrapModel.runtime {
                OOTAppView(
                    runtime: runtime,
                    developerHarness: bootstrapModel.developerHarnessConfiguration,
                    startupManagedExternally: true
                )
            } else {
                OOTContentBootstrapView(model: bootstrapModel)
            }
        }
    }
}
