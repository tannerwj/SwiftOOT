import SwiftUI
import OOTCore
import OOTDataModel

struct MessageView: View {
    let presentation: MessagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let icon = presentation.icon {
                HStack(spacing: 10) {
                    iconBadge(for: icon)
                    Text(icon.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Text(attributedText)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(5)

            if let choiceState, choiceState.options.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(choiceState.options.enumerated()), id: \.offset) { index, option in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(index == choiceState.selectedIndex ? Color.white : Color.white.opacity(0.2))
                                .frame(width: 8, height: 8)
                            Text(option.title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(index == choiceState.selectedIndex ? Color.white : Color.white.opacity(0.72))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(index == choiceState.selectedIndex ? Color.white.opacity(0.14) : Color.clear)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 720, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(woodGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(panelGradient)
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        }
    }
}

private extension MessageView {
    var attributedText: AttributedString {
        presentation.textRuns.reduce(into: AttributedString()) { partial, run in
            var fragment = AttributedString(run.text)
            fragment.foregroundColor = color(for: run.color)
            partial.append(fragment)
        }
    }

    var choiceState: MessageChoiceState? {
        presentation.choiceState
    }

    var woodGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.42, green: 0.24, blue: 0.11),
                Color(red: 0.26, green: 0.15, blue: 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var panelGradient: LinearGradient {
        let colors: [Color]
        switch presentation.variant {
        case .blue:
            colors = [Color(red: 0.09, green: 0.18, blue: 0.42), Color(red: 0.03, green: 0.09, blue: 0.23)]
        case .red:
            colors = [Color(red: 0.42, green: 0.11, blue: 0.09), Color(red: 0.24, green: 0.03, blue: 0.05)]
        case .white:
            colors = [Color(red: 0.80, green: 0.82, blue: 0.86), Color(red: 0.58, green: 0.61, blue: 0.68)]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func color(for color: MessageTextColor) -> Color {
        switch color {
        case .white:
            return presentation.variant == .white ? Color.black.opacity(0.9) : .white
        case .red:
            return Color(red: 0.98, green: 0.48, blue: 0.43)
        case .green:
            return Color(red: 0.52, green: 0.94, blue: 0.46)
        case .blue:
            return Color(red: 0.57, green: 0.81, blue: 0.98)
        case .yellow:
            return Color(red: 0.99, green: 0.88, blue: 0.41)
        case .cyan:
            return Color(red: 0.53, green: 0.95, blue: 0.96)
        case .purple:
            return Color(red: 0.88, green: 0.66, blue: 0.98)
        }
    }

    @ViewBuilder
    func iconBadge(for icon: MessageIcon) -> some View {
        let symbolName = switch icon.rawValue.lowercased() {
        case "fairy":
            "sparkles"
        case "note", "song":
            "music.note"
        case "heart":
            "heart.fill"
        case "warning":
            "exclamationmark.triangle.fill"
        default:
            "diamond.fill"
        }

        Image(systemName: symbolName)
            .font(.headline.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.12), in: Circle())
    }
}

struct ActionPromptView: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Text("A")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(red: 0.18, green: 0.56, blue: 0.93), in: Circle())

            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.46), in: Capsule())
    }
}
