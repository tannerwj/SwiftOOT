import SwiftUI
import OOTRender

public struct OOTAppView: View {
    public init() {}

    public var body: some View {
        NavigationSplitView {
            DebugSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                MetalView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
