import SwiftUI

@main
struct OOTMacApp: App {
    var body: some Scene {
        WindowGroup("SwiftOOT") {
            OOTMacRootView()
                .frame(minWidth: 960, minHeight: 540)
        }
    }
}
