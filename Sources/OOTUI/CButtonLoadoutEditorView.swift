import OOTCore
import SwiftUI

struct CButtonLoadoutEditorShortcut: View {
    let runtime: GameRuntime

    var body: some View {
        Button {
            runtime.toggleCButtonItemEditor()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: runtime.isCButtonItemEditorPresented ? "pause.circle.fill" : "square.grid.3x1.folder.fill.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                Text(runtime.isCButtonItemEditorPresented ? "Resume" : "C-Items")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Text("Return")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.28), in: Capsule(style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.19, green: 0.28, blue: 0.2), Color(red: 0.1, green: 0.16, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct CButtonLoadoutEditorOverlay: View {
    let runtime: GameRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("C-Button Loadout")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Choose any owned child item for C-Left, C-Down, or C-Right. The HUD and save slot update immediately.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Resume") {
                    runtime.setCButtonItemEditorPresented(false)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.31, green: 0.65, blue: 0.34))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(GameplayCButton.allCases, id: \.rawValue) { button in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(button.label.uppercased())
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Color(red: 0.98, green: 0.88, blue: 0.4))

                        Menu {
                            ForEach(runtime.availableChildCButtonItems, id: \.rawValue) { item in
                                Button(item.displayName) {
                                    runtime.assignItem(item, to: button)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(currentItem(for: button)?.displayName ?? "Empty")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Owned Child Items")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color(red: 0.77, green: 0.92, blue: 0.82))

                Text(runtime.availableChildCButtonItems.map(\.displayName).joined(separator: "  •  "))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                if runtime.availableChildCButtonItems.count > GameplayCButton.allCases.count {
                    Text("More than three items are owned, so use this menu to rotate any extra item back onto a C-button.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Press Return again or click Resume to close.")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.98, green: 0.88, blue: 0.4))
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color(red: 0.12, green: 0.18, blue: 0.16).opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 22, y: 12)
    }

    private func currentItem(for button: GameplayCButton) -> GameplayUsableItem? {
        runtime.inventoryState.cButtonLoadout[button]
    }
}
