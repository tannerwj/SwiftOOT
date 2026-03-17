import SwiftUI
import OOTRender

struct RenderSettingsView: View {
    @Binding
    private var renderSettings: RenderSettings

    init(renderSettings: Binding<RenderSettings>) {
        self._renderSettings = renderSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Presentation", selection: $renderSettings.presentationMode) {
                ForEach(RenderPresentationMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(renderSettings.presentationMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
