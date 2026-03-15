import Foundation
import Observation
import OOTContent
import OOTDataModel
import OOTTelemetry

public enum GameState: String, Codable, Sendable, Equatable {
    case boot
    case consoleLogo
    case titleScreen
    case fileSelect
    case gameplay
}

public enum TitleMenuOption: String, Codable, CaseIterable, Sendable, Equatable {
    case newGame
    case continueGame

    public var title: String {
        switch self {
        case .newGame:
            return "New Game"
        case .continueGame:
            return "Continue"
        }
    }
}

public enum FileSelectMode: String, Codable, Sendable, Equatable {
    case newGame
    case continueGame

    public var title: String {
        switch self {
        case .newGame:
            return "Choose a File for a New Quest"
        case .continueGame:
            return "Choose a File to Continue"
        }
    }
}

public enum InputAction: String, Codable, Sendable, Equatable {
    case confirm
    case cancel
    case moveSelection
}

public struct GameTime: Codable, Sendable, Equatable {
    public var frameCount: Int
    public var timeOfDay: Double

    public init(
        frameCount: Int = 0,
        timeOfDay: Double = 6
    ) {
        self.frameCount = frameCount
        self.timeOfDay = timeOfDay
    }

    mutating func advance(by frames: Int = 1) {
        frameCount += frames
        timeOfDay = (timeOfDay + (Double(frames) / 60)).truncatingRemainder(dividingBy: 24)
    }
}

public struct InputState: Codable, Sendable, Equatable {
    public var lastAction: InputAction?
    public var selectionIndex: Int

    public init(
        lastAction: InputAction? = nil,
        selectionIndex: Int = 0
    ) {
        self.lastAction = lastAction
        self.selectionIndex = selectionIndex
    }

    mutating func record(
        _ action: InputAction,
        selectionIndex: Int
    ) {
        lastAction = action
        self.selectionIndex = selectionIndex
    }
}

public struct SaveSlot: Identifiable, Codable, Sendable, Equatable {
    public var id: Int
    public var playerName: String
    public var locationName: String
    public var hearts: Int
    public var hasSaveData: Bool

    public init(
        id: Int,
        playerName: String = "Empty Slot",
        locationName: String = "Unused",
        hearts: Int = 3,
        hasSaveData: Bool = false
    ) {
        self.id = id
        self.playerName = playerName
        self.locationName = locationName
        self.hearts = hearts
        self.hasSaveData = hasSaveData
    }

    public static func empty(id: Int) -> Self {
        Self(id: id)
    }

    public static func starter(id: Int) -> Self {
        Self(
            id: id,
            playerName: "Link",
            locationName: "Kokiri Forest",
            hearts: 3,
            hasSaveData: true
        )
    }
}

public struct SaveContext: Codable, Sendable, Equatable {
    public var slots: [SaveSlot]
    public var selectedSlotIndex: Int

    public init(
        slots: [SaveSlot] = Self.defaultSlots(),
        selectedSlotIndex: Int = 0
    ) {
        var normalizedSlots = slots
        while normalizedSlots.count < 3 {
            normalizedSlots.append(.empty(id: normalizedSlots.count))
        }
        normalizedSlots = Array(normalizedSlots.prefix(3))
        normalizedSlots = normalizedSlots.enumerated().map { index, slot in
            var slot = slot
            slot.id = index
            return slot
        }

        self.slots = normalizedSlots
        self.selectedSlotIndex = min(max(0, selectedSlotIndex), normalizedSlots.count - 1)
    }

    public var hasExistingSave: Bool {
        slots.contains(where: \.hasSaveData)
    }

    public var firstEmptySlotIndex: Int? {
        slots.firstIndex(where: { !$0.hasSaveData })
    }

    public var firstOccupiedSlotIndex: Int? {
        slots.firstIndex(where: \.hasSaveData)
    }

    public static func defaultSlots() -> [SaveSlot] {
        (0..<3).map(SaveSlot.empty)
    }
}

public struct PlayState: Codable, Sendable, Equatable {
    public enum EntryMode: String, Codable, Sendable, Equatable {
        case newGame
        case continueGame
    }

    public var activeSaveSlot: Int
    public var entryMode: EntryMode
    public var currentSceneName: String
    public var playerName: String

    public init(
        activeSaveSlot: Int,
        entryMode: EntryMode,
        currentSceneName: String,
        playerName: String
    ) {
        self.activeSaveSlot = activeSaveSlot
        self.entryMode = entryMode
        self.currentSceneName = currentSceneName
        self.playerName = playerName
    }
}

@MainActor
@Observable
public final class GameRuntime {
    public typealias RuntimeSuspender = @Sendable (Duration) async -> Void

    public enum SceneViewerState: Sendable, Equatable {
        case idle
        case loadingContent
        case running
    }

    public var currentState: GameState
    public var playState: PlayState?
    public var gameTime: GameTime
    public var saveContext: SaveContext
    public var inputState: InputState
    public var selectedTitleOption: TitleMenuOption
    public var fileSelectMode: FileSelectMode?
    public var statusMessage: String?
    public var sceneViewerState: SceneViewerState
    public var availableScenes: [SceneTableEntry]
    public var selectedSceneID: Int?
    public var loadedScene: LoadedScene?
    public var textureAssetURLs: [UInt32: URL]
    public var errorMessage: String?

    @ObservationIgnored
    public let contentLoader: any ContentLoading

    @ObservationIgnored
    public let sceneLoader: any SceneLoading

    @ObservationIgnored
    public let telemetryPublisher: any TelemetryPublishing

    @ObservationIgnored
    private let bootDuration: Duration

    @ObservationIgnored
    private let consoleLogoDuration: Duration

    @ObservationIgnored
    private let suspender: RuntimeSuspender

    @ObservationIgnored
    private var hasStarted = false

    public init(
        currentState: GameState = .boot,
        playState: PlayState? = nil,
        gameTime: GameTime = GameTime(),
        saveContext: SaveContext = SaveContext(),
        inputState: InputState = InputState(),
        selectedTitleOption: TitleMenuOption = .newGame,
        fileSelectMode: FileSelectMode? = nil,
        statusMessage: String? = nil,
        sceneViewerState: SceneViewerState = .idle,
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        loadedScene: LoadedScene? = nil,
        textureAssetURLs: [UInt32: URL] = [:],
        errorMessage: String? = nil,
        contentLoader: any ContentLoading = ContentLoader(),
        sceneLoader: any SceneLoading = SceneLoader(),
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher(),
        bootDuration: Duration = .milliseconds(250),
        consoleLogoDuration: Duration = .seconds(1),
        suspender: @escaping RuntimeSuspender = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.currentState = currentState
        self.playState = playState
        self.gameTime = gameTime
        self.saveContext = saveContext
        self.inputState = inputState
        self.selectedTitleOption = selectedTitleOption
        self.fileSelectMode = fileSelectMode
        self.statusMessage = statusMessage
        self.sceneViewerState = sceneViewerState
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.errorMessage = errorMessage
        self.contentLoader = contentLoader
        self.sceneLoader = sceneLoader
        self.telemetryPublisher = telemetryPublisher
        self.bootDuration = bootDuration
        self.consoleLogoDuration = consoleLogoDuration
        self.suspender = suspender
    }

    public var canContinue: Bool {
        saveContext.hasExistingSave
    }

    public func start() async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        currentState = .boot
        telemetryPublisher.publish("gameRuntime.start")

        do {
            try await contentLoader.loadInitialContent()
        } catch {
            statusMessage = "Initial content load failed. Continuing with placeholder content."
            telemetryPublisher.publish("gameRuntime.contentLoadFailed")
        }

        await suspender(bootDuration)
        transition(to: .consoleLogo)
        await suspender(consoleLogoDuration)
        transition(to: .titleScreen)
    }

    public func bootstrapSceneViewer() async {
        guard availableScenes.isEmpty || loadedScene == nil else {
            return
        }

        let previousScene = loadedScene
        sceneViewerState = .loadingContent
        errorMessage = nil

        do {
            let snapshot = try await loadSceneViewerSnapshot(defaultSceneID: nil)
            apply(snapshot)
            sceneViewerState = loadedScene == nil ? .idle : .running

            if loadedScene == nil {
                errorMessage = "No extracted scenes were found under the configured content root."
            } else if playState != nil {
                playState?.currentSceneName = loadedScene?.manifest.name ?? playState?.currentSceneName ?? "Unknown"
            }
        } catch {
            loadedScene = previousScene
            sceneViewerState = previousScene == nil ? .idle : .running
            errorMessage = error.localizedDescription
        }
    }

    public func selectScene(id: Int) async {
        guard selectedSceneID != id || loadedScene?.manifest.id != id else {
            return
        }

        let previousScene = loadedScene
        let previousTextureAssetURLs = textureAssetURLs
        let previousSelectedSceneID = selectedSceneID

        sceneViewerState = .loadingContent
        errorMessage = nil

        do {
            let snapshot = try await loadSceneViewerSnapshot(defaultSceneID: id)
            apply(snapshot)
            sceneViewerState = loadedScene == nil ? .idle : .running

            if playState != nil {
                playState?.currentSceneName = loadedScene?.manifest.name ?? playState?.currentSceneName ?? "Unknown"
            }
        } catch {
            loadedScene = previousScene
            textureAssetURLs = previousTextureAssetURLs
            selectedSceneID = previousSelectedSceneID
            sceneViewerState = previousScene == nil ? .idle : .running
            errorMessage = error.localizedDescription
        }
    }

    public func chooseTitleOption(_ option: TitleMenuOption) {
        selectedTitleOption = option
        inputState.record(.confirm, selectionIndex: option == .newGame ? 0 : 1)

        switch option {
        case .newGame:
            openFileSelect(
                mode: .newGame,
                preferredSlot: saveContext.firstEmptySlotIndex ?? 0
            )
        case .continueGame:
            guard canContinue else {
                statusMessage = "No saved games are available yet."
                telemetryPublisher.publish("gameRuntime.continueUnavailable")
                return
            }

            openFileSelect(
                mode: .continueGame,
                preferredSlot: saveContext.firstOccupiedSlotIndex ?? 0
            )
        }
    }

    public func selectSaveSlot(_ index: Int) {
        let normalizedIndex = normalizedSlotIndex(index)
        saveContext.selectedSlotIndex = normalizedIndex
        inputState.record(.moveSelection, selectionIndex: normalizedIndex)
    }

    public func confirmSelectedSaveSlot() {
        guard currentState == .fileSelect, let fileSelectMode else {
            return
        }

        inputState.record(.confirm, selectionIndex: saveContext.selectedSlotIndex)

        switch fileSelectMode {
        case .newGame:
            startNewGame(in: saveContext.selectedSlotIndex)
        case .continueGame:
            continueGame(from: saveContext.selectedSlotIndex)
        }
    }

    public func returnToTitleScreen() {
        fileSelectMode = nil
        statusMessage = nil
        inputState.record(.cancel, selectionIndex: saveContext.selectedSlotIndex)
        transition(to: .titleScreen)
    }

    private func openFileSelect(
        mode: FileSelectMode,
        preferredSlot: Int
    ) {
        fileSelectMode = mode
        statusMessage = nil
        saveContext.selectedSlotIndex = normalizedSlotIndex(preferredSlot)
        transition(to: .fileSelect)
    }

    private func startNewGame(in index: Int) {
        let normalizedIndex = normalizedSlotIndex(index)
        let slot = SaveSlot.starter(id: normalizedIndex)
        saveContext.slots[normalizedIndex] = slot
        playState = PlayState(
            activeSaveSlot: normalizedIndex,
            entryMode: .newGame,
            currentSceneName: slot.locationName,
            playerName: slot.playerName
        )
        fileSelectMode = nil
        statusMessage = nil
        transition(to: .gameplay)
    }

    private func continueGame(from index: Int) {
        let normalizedIndex = normalizedSlotIndex(index)
        let slot = saveContext.slots[normalizedIndex]

        guard slot.hasSaveData else {
            statusMessage = "Select a populated save slot to continue."
            telemetryPublisher.publish("gameRuntime.continueRejected.emptySlot")
            return
        }

        playState = PlayState(
            activeSaveSlot: normalizedIndex,
            entryMode: .continueGame,
            currentSceneName: slot.locationName,
            playerName: slot.playerName
        )
        fileSelectMode = nil
        statusMessage = nil
        transition(to: .gameplay)
    }

    private func transition(to nextState: GameState) {
        currentState = nextState
        gameTime.advance()
        telemetryPublisher.publish("gameRuntime.state.\(nextState.rawValue)")
    }

    private func normalizedSlotIndex(_ index: Int) -> Int {
        min(max(0, index), saveContext.slots.count - 1)
    }

    private struct SceneViewerSnapshot: Sendable {
        let availableScenes: [SceneTableEntry]
        let selectedSceneID: Int?
        let loadedScene: LoadedScene?
        let textureAssetURLs: [UInt32: URL]
    }

    private func apply(_ snapshot: SceneViewerSnapshot) {
        availableScenes = snapshot.availableScenes
        selectedSceneID = snapshot.selectedSceneID
        loadedScene = snapshot.loadedScene
        textureAssetURLs = snapshot.textureAssetURLs
    }

    private func loadSceneViewerSnapshot(defaultSceneID: Int?) async throws -> SceneViewerSnapshot {
        let sceneLoader = self.sceneLoader
        return try await Task.detached(priority: .userInitiated) {
            let sceneTableEntries = try sceneLoader.loadSceneTableEntries()
            let availableScenes = sceneTableEntries.filter { entry in
                (try? sceneLoader.resolveSceneDirectory(for: entry.index)) != nil
            }

            let selectedSceneID =
                defaultSceneID ??
                availableScenes.first(where: { Self.sceneName(for: $0) == "spot04" })?.index ??
                availableScenes.first?.index

            guard let selectedSceneID else {
                return SceneViewerSnapshot(
                    availableScenes: availableScenes,
                    selectedSceneID: nil,
                    loadedScene: nil,
                    textureAssetURLs: [:]
                )
            }

            let loadedScene = try sceneLoader.loadScene(id: selectedSceneID)
            let textureAssetURLs = try sceneLoader.loadTextureAssetURLs(for: loadedScene)

            return SceneViewerSnapshot(
                availableScenes: availableScenes,
                selectedSceneID: selectedSceneID,
                loadedScene: loadedScene,
                textureAssetURLs: textureAssetURLs
            )
        }.value
    }

    nonisolated static func sceneName(for entry: SceneTableEntry) -> String {
        if entry.segmentName.hasSuffix("_scene") {
            return String(entry.segmentName.dropLast("_scene".count))
        }
        return entry.segmentName
    }
}
