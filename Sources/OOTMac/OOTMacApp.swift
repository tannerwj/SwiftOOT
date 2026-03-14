import SwiftUI
import OOTUI

@main
struct OOTMacApp: App {
    var body: some Scene {
        WindowGroup {
            OOTAppView()
                .frame(minWidth: 960, minHeight: 540)
        }
    }
}
