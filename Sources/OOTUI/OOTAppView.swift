import SwiftUI
import OOTCore
import OOTRender

enum OOTRootViewState: Equatable {
    case boot
    case consoleLogo
    case titleScreen
    case fileSelect
    case gameplay
}

public struct OOTAppView: View {
    let runtime: GameRuntime

    public init(runtime: GameRuntime) {
        self.runtime = runtime
    }

    static func rootViewState(for state: GameState) -> OOTRootViewState {
        switch state {
        case .boot:
            return .boot
        case .consoleLogo:
            return .consoleLogo
        case .titleScreen:
            return .titleScreen
        case .fileSelect:
            return .fileSelect
        case .gameplay:
            return .gameplay
        }
    }

    public var body: some View {
        Group {
            switch Self.rootViewState(for: runtime.currentState) {
            case .boot:
                RuntimeSplashView(
                    title: "SwiftOOT",
                    subtitle: "Booting the engine..."
                )
            case .consoleLogo:
                RuntimeSplashView(
                    title: "N64",
                    subtitle: "Console logo sequence"
                )
            case .titleScreen:
                TitleScreenView(runtime: runtime)
            case .fileSelect:
                FileSelectView(runtime: runtime)
            case .gameplay:
                GameplayShellView(runtime: runtime)
            }
        }
        .task {
            await runtime.start()
        }
    }
}

private struct RuntimeSplashView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.08, green: 0.12, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct TitleScreenView: View {
    let runtime: GameRuntime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.19, blue: 0.14), Color(red: 0.33, green: 0.15, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("The Legend of SwiftOOT")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("A simplified title flow with Link and Epona standing in for the final cinematic.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: 540)
                }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        VStack(spacing: 10) {
                            Text("Link + Epona")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Animated hero presentation placeholder")
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .frame(width: 420, height: 220)

                VStack(spacing: 14) {
                    Button(TitleMenuOption.newGame.title) {
                        runtime.chooseTitleOption(.newGame)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(TitleMenuOption.continueGame.title) {
                        runtime.chooseTitleOption(.continueGame)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!runtime.canContinue)
                }

                if let statusMessage = runtime.statusMessage {
                    Text(statusMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.98, green: 0.87, blue: 0.44))
                }

                Spacer()
            }
            .padding(32)
        }
    }
}

private struct FileSelectView: View {
    let runtime: GameRuntime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.14, green: 0.25, blue: 0.31)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(runtime.fileSelectMode?.title ?? "Choose a File")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    ForEach(Array(runtime.saveContext.slots.enumerated()), id: \.element.id) { index, slot in
                        Button {
                            runtime.selectSaveSlot(index)
                            runtime.confirmSelectedSaveSlot()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("File \(index + 1)")
                                        .font(.headline)
                                    Text(slot.playerName)
                                        .font(.title3.weight(.semibold))
                                    Text(slot.hasSaveData ? slot.locationName : "Empty slot")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(slot.hasSaveData ? "\(slot.hearts) Hearts" : "New")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(index == runtime.saveContext.selectedSlotIndex ? .white.opacity(0.24) : .white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(runtime.fileSelectMode == .continueGame && !slot.hasSaveData)
                    }
                }
                .frame(maxWidth: 520)

                HStack(spacing: 16) {
                    Button("Back") {
                        runtime.returnToTitleScreen()
                    }
                    .buttonStyle(.bordered)

                    if let statusMessage = runtime.statusMessage {
                        Text(statusMessage)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color(red: 0.98, green: 0.87, blue: 0.44))
                    }
                }
            }
            .padding(32)
        }
    }
}

private struct GameplayShellView: View {
    let runtime: GameRuntime

    var body: some View {
        NavigationSplitView {
            DebugSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                MetalView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let playState = runtime.playState {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gameplay Placeholder")
                            .font(.headline.weight(.bold))
                        Text("\(playState.playerName) in \(playState.currentSceneName)")
                        Text("Save Slot \(playState.activeSaveSlot + 1)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
                }
            }
        }
    }
}
