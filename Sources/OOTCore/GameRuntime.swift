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

public struct PlayState: Codable, Equatable, @unchecked Sendable {
    public enum EntryMode: String, Codable, Sendable, Equatable {
        case newGame
        case continueGame
    }

    public var activeSaveSlot: Int
    public var entryMode: EntryMode
    public var currentSceneName: String
    public var playerName: String

    public var scene: LoadedScene?
    public var actorTable: [Int: ActorTableEntry]
    public var activeRoomIDs: Set<Int>
    public var currentDrawPass: ActorDrawPass?

    @MainActor
    var actorRuntimeHooks: ActorRuntimeHooks?

    public init(
        activeSaveSlot: Int,
        entryMode: EntryMode,
        currentSceneName: String,
        playerName: String,
        scene: LoadedScene? = nil,
        actorTable: [Int: ActorTableEntry] = [:],
        activeRoomIDs: Set<Int> = [],
        currentDrawPass: ActorDrawPass? = nil
    ) {
        self.activeSaveSlot = activeSaveSlot
        self.entryMode = entryMode
        self.currentSceneName = currentSceneName
        self.playerName = playerName
        self.scene = scene
        self.actorTable = actorTable
        self.activeRoomIDs = activeRoomIDs
        self.currentDrawPass = currentDrawPass
        actorRuntimeHooks = nil
    }

    public var activeRooms: [LoadedSceneRoom] {
        scene?.rooms.filter { activeRoomIDs.contains($0.manifest.id) } ?? []
    }

    @MainActor
    public func requestDestroy(_ actor: any Actor) {
        actorRuntimeHooks?.requestDestroy(actor)
    }

    func withActorRuntime(
        scene: LoadedScene,
        actorTable: [Int: ActorTableEntry],
        activeRoomIDs: Set<Int>,
        actorRuntimeHooks: ActorRuntimeHooks
    ) -> PlayState {
        var copy = self
        copy.scene = scene
        copy.actorTable = actorTable
        copy.activeRoomIDs = activeRoomIDs
        copy.currentDrawPass = nil
        copy.actorRuntimeHooks = actorRuntimeHooks
        return copy
    }

    func withActiveRooms(_ roomIDs: Set<Int>) -> PlayState {
        var copy = self
        copy.activeRoomIDs = roomIDs
        return copy
    }

    func withCurrentDrawPass(_ drawPass: ActorDrawPass?) -> PlayState {
        var copy = self
        copy.currentDrawPass = drawPass
        return copy
    }

    public static func == (lhs: PlayState, rhs: PlayState) -> Bool {
        lhs.activeSaveSlot == rhs.activeSaveSlot &&
            lhs.entryMode == rhs.entryMode &&
            lhs.currentSceneName == rhs.currentSceneName &&
            lhs.playerName == rhs.playerName &&
            lhs.scene == rhs.scene &&
            lhs.actorTable == rhs.actorTable &&
            lhs.activeRoomIDs == rhs.activeRoomIDs &&
            lhs.currentDrawPass == rhs.currentDrawPass
    }

    private enum CodingKeys: String, CodingKey {
        case activeSaveSlot
        case entryMode
        case currentSceneName
        case playerName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSaveSlot = try container.decode(Int.self, forKey: .activeSaveSlot)
        entryMode = try container.decode(EntryMode.self, forKey: .entryMode)
        currentSceneName = try container.decode(String.self, forKey: .currentSceneName)
        playerName = try container.decode(String.self, forKey: .playerName)
        scene = nil
        actorTable = [:]
        activeRoomIDs = []
        currentDrawPass = nil
        actorRuntimeHooks = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeSaveSlot, forKey: .activeSaveSlot)
        try container.encode(entryMode, forKey: .entryMode)
        try container.encode(currentSceneName, forKey: .currentSceneName)
        try container.encode(playerName, forKey: .playerName)
    }
}

@MainActor
@Observable
public final class GameRuntime {
    public typealias RuntimeSuspender = @Sendable (Duration) async -> Void

    public var currentState: GameState
    public var playState: PlayState?
    public var gameTime: GameTime
    public var saveContext: SaveContext
    public var inputState: InputState
    public var selectedTitleOption: TitleMenuOption
    public var fileSelectMode: FileSelectMode?
    public var statusMessage: String?

    @ObservationIgnored
    public let contentLoader: any ContentLoading

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

    @ObservationIgnored
    private let actorRegistryOverride: ActorRegistry?

    @ObservationIgnored
    private var actorContext: ActorContext?

    public init(
        currentState: GameState = .boot,
        playState: PlayState? = nil,
        gameTime: GameTime = GameTime(),
        saveContext: SaveContext = SaveContext(),
        inputState: InputState = InputState(),
        selectedTitleOption: TitleMenuOption = .newGame,
        fileSelectMode: FileSelectMode? = nil,
        statusMessage: String? = nil,
        contentLoader: any ContentLoading = ContentLoader(),
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher(),
        actorRegistry: ActorRegistry? = nil,
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
        self.contentLoader = contentLoader
        self.telemetryPublisher = telemetryPublisher
        actorRegistryOverride = actorRegistry
        self.bootDuration = bootDuration
        self.consoleLogoDuration = consoleLogoDuration
        self.suspender = suspender
    }

    public var canContinue: Bool {
        saveContext.hasExistingSave
    }

    public var actors: [any Actor] {
        actorContext?.allActors ?? []
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
        activateSceneContentIfAvailable()
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
        activateSceneContentIfAvailable()
        transition(to: .gameplay)
    }

    public func loadScene(
        id sceneID: Int,
        activeRoomIDs: Set<Int>? = nil
    ) throws {
        let loadedScene = try contentLoader.loadScene(id: sceneID)
        let actorTableEntries = try contentLoader.loadActorTable()
        let actorTable = Dictionary(uniqueKeysWithValues: actorTableEntries.map { ($0.id, $0) })
        let selectedRooms = activeRoomIDs ?? Set(loadedScene.manifest.rooms.prefix(1).map(\.id))
        let registry = actorRegistryOverride ?? ActorRegistry.default(actorTable: actorTableEntries)
        let actorContext = ActorContext(
            registry: registry,
            telemetryPublisher: telemetryPublisher
        )
        let hooks = ActorRuntimeHooks { actor in
            actorContext.requestDestroy(actor)
        }
        let basePlayState = playState ?? PlayState(
            activeSaveSlot: 0,
            entryMode: .newGame,
            currentSceneName: loadedScene.manifest.title ?? loadedScene.manifest.name,
            playerName: "Link"
        )
        let playState = basePlayState.withActorRuntime(
            scene: loadedScene,
            actorTable: actorTable,
            activeRoomIDs: selectedRooms,
            actorRuntimeHooks: hooks
        )

        actorContext.spawnActors(
            for: selectedRooms,
            in: loadedScene,
            actorTable: actorTable,
            playState: playState
        )

        self.playState = playState
        self.actorContext = actorContext
        currentState = .gameplay
    }

    public func setActiveRooms(_ roomIDs: Set<Int>) {
        guard
            let actorContext,
            var playState,
            let scene = playState.scene
        else {
            return
        }

        playState = playState.withActiveRooms(roomIDs)
        actorContext.syncActiveRooms(
            roomIDs,
            in: scene,
            actorTable: playState.actorTable,
            playState: playState
        )
        self.playState = playState
    }

    public func updateFrame() {
        guard let actorContext, let playState else {
            return
        }

        actorContext.updateAll(playState: playState)
    }

    public func drawActors(in pass: ActorDrawPass) {
        guard let actorContext, let playState else {
            return
        }

        actorContext.drawActors(in: pass, playState: playState)
    }

    private func transition(to nextState: GameState) {
        currentState = nextState
        gameTime.advance()
        telemetryPublisher.publish("gameRuntime.state.\(nextState.rawValue)")
    }

    private func normalizedSlotIndex(_ index: Int) -> Int {
        min(max(0, index), saveContext.slots.count - 1)
    }

    private func activateSceneContentIfAvailable() {
        guard let playState else {
            actorContext = nil
            return
        }

        guard let sceneID = sceneID(for: playState.currentSceneName) else {
            actorContext = nil
            return
        }

        do {
            try loadScene(id: sceneID)
        } catch {
            actorContext = nil
            statusMessage = "Gameplay scene content failed to load. Continuing with placeholder gameplay."
            telemetryPublisher.publish("gameRuntime.sceneLoadFailed")
        }
    }

    private func sceneID(for sceneName: String) -> Int? {
        switch sceneName {
        case "Kokiri Forest":
            return 0x55
        default:
            return nil
        }
    }
}
