import SwiftUI
import OOTRender

@main
struct OOTMacApp: App {
    var body: some Scene {
        WindowGroup {
            MetalView()
                .frame(minWidth: 960, minHeight: 540)
        }
    }
}
