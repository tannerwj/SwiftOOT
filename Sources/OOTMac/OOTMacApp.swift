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
        .commands {
            CommandMenu("Commentary") {
                Button(
                    bootstrapModel.runtime?.isDirectorCommentaryEnabled == true
                        ? "Hide Director's Commentary"
                        : "Show Director's Commentary"
                ) {
                    bootstrapModel.runtime?.toggleDirectorCommentaryEnabled()
                }
                .keyboardShortcut("A", modifiers: [.command, .shift])
                .disabled(bootstrapModel.runtime == nil)

                Toggle(
                    "Show Annotation Dots",
                    isOn: Binding(
                        get: { bootstrapModel.runtime?.directorCommentaryShowsWorldMarkers ?? false },
                        set: { newValue in
                            bootstrapModel.runtime?.directorCommentaryShowsWorldMarkers = newValue
                        }
                    )
                )
                .disabled(bootstrapModel.runtime?.isDirectorCommentaryEnabled != true)
            }
        }
    }
}
