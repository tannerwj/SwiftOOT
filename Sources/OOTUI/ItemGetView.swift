import SwiftUI
import OOTCore

struct ItemGetView: View {
    let state: ItemGetOverlayState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.92, blue: 0.52),
                                    Color(red: 0.90, green: 0.55, blue: 0.18),
                                    Color(red: 0.32, green: 0.15, blue: 0.03),
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 52
                            )
                        )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.28), radius: 16, y: 10)

            VStack(spacing: 4) {
                Text(state.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(state.phase == .displayingText ? "Press A to continue" : state.description)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.46))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
