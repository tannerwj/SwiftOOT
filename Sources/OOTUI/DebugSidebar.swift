import SwiftUI

public struct DebugSidebar: View {
    public init() {}

    public var body: some View {
        List {
            Section("Debug") {
                Text("Runtime tools will appear here.")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Debug")
    }
}
