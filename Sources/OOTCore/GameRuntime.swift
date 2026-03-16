import Foundation
import Observation
import OOTContent
import OOTDataModel
import OOTTelemetry
import simd

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
    public var currentSceneID: Int?
    public var currentRoomID: Int?
    public var currentEntranceIndex: Int?
    public var currentSpawnIndex: Int?
    public var playerName: String

    public var scene: LoadedScene?
    public var actorTable: [Int: ActorTableEntry]
    public var activeRoomIDs: Set<Int>
    public var loadedObjectIDs: [Int]
    public var transitionEffect: SceneTransitionEffect?
    public var objectSlotOverflow: Bool
    public var currentDrawPass: ActorDrawPass?

    @MainActor
    var actorRuntimeHooks: ActorRuntimeHooks?

    public init(
        activeSaveSlot: Int,
        entryMode: EntryMode,
        currentSceneName: String,
        currentSceneID: Int? = nil,
        currentRoomID: Int? = nil,
        currentEntranceIndex: Int? = nil,
        currentSpawnIndex: Int? = nil,
        playerName: String,
        scene: LoadedScene? = nil,
        actorTable: [Int: ActorTableEntry] = [:],
        activeRoomIDs: Set<Int> = [],
        loadedObjectIDs: [Int] = [],
        transitionEffect: SceneTransitionEffect? = nil,
        objectSlotOverflow: Bool = false,
        currentDrawPass: ActorDrawPass? = nil
    ) {
        self.activeSaveSlot = activeSaveSlot
        self.entryMode = entryMode
        self.currentSceneName = currentSceneName
        self.currentSceneID = currentSceneID
        self.currentRoomID = currentRoomID
        self.currentEntranceIndex = currentEntranceIndex
        self.currentSpawnIndex = currentSpawnIndex
        self.playerName = playerName
        self.scene = scene
        self.actorTable = actorTable
        self.activeRoomIDs = activeRoomIDs
        self.loadedObjectIDs = loadedObjectIDs
        self.transitionEffect = transitionEffect
        self.objectSlotOverflow = objectSlotOverflow
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

    @MainActor
    public func requestMessage(_ messageID: Int) {
        actorRuntimeHooks?.requestMessage(messageID)
    }

    func withActorRuntime(
        scene: LoadedScene,
        actorTable: [Int: ActorTableEntry],
        activeRoomIDs: Set<Int>,
        actorRuntimeHooks: ActorRuntimeHooks,
        sceneManagerState: SceneManagerState? = nil
    ) -> PlayState {
        var copy = self
        copy.scene = scene
        copy.actorTable = actorTable
        copy.activeRoomIDs = activeRoomIDs
        if let sceneManagerState {
            copy.currentSceneID = sceneManagerState.currentSceneID
            copy.currentRoomID = sceneManagerState.currentRoomID
            copy.currentEntranceIndex = sceneManagerState.currentEntranceIndex
            copy.currentSpawnIndex = sceneManagerState.currentSpawnIndex
            copy.loadedObjectIDs = sceneManagerState.loadedObjectIDs
            copy.transitionEffect = sceneManagerState.transitionEffect
            copy.objectSlotOverflow = sceneManagerState.objectSlotOverflow
        }
        copy.currentDrawPass = nil
        copy.actorRuntimeHooks = actorRuntimeHooks
        return copy
    }

    func withActiveRooms(
        _ roomIDs: Set<Int>,
        sceneManagerState: SceneManagerState? = nil
    ) -> PlayState {
        var copy = self
        copy.activeRoomIDs = roomIDs
        if let sceneManagerState {
            copy.currentRoomID = sceneManagerState.currentRoomID
            copy.currentEntranceIndex = sceneManagerState.currentEntranceIndex
            copy.currentSpawnIndex = sceneManagerState.currentSpawnIndex
            copy.loadedObjectIDs = sceneManagerState.loadedObjectIDs
            copy.transitionEffect = sceneManagerState.transitionEffect
            copy.objectSlotOverflow = sceneManagerState.objectSlotOverflow
        }
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
            lhs.currentSceneID == rhs.currentSceneID &&
            lhs.currentRoomID == rhs.currentRoomID &&
            lhs.currentEntranceIndex == rhs.currentEntranceIndex &&
            lhs.currentSpawnIndex == rhs.currentSpawnIndex &&
            lhs.playerName == rhs.playerName &&
            lhs.scene == rhs.scene &&
            lhs.actorTable == rhs.actorTable &&
            lhs.activeRoomIDs == rhs.activeRoomIDs &&
            lhs.loadedObjectIDs == rhs.loadedObjectIDs &&
            lhs.transitionEffect == rhs.transitionEffect &&
            lhs.objectSlotOverflow == rhs.objectSlotOverflow &&
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
        currentSceneID = nil
        currentRoomID = nil
        currentEntranceIndex = nil
        currentSpawnIndex = nil
        playerName = try container.decode(String.self, forKey: .playerName)
        scene = nil
        actorTable = [:]
        activeRoomIDs = []
        loadedObjectIDs = []
        transitionEffect = nil
        objectSlotOverflow = false
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

    public enum SceneViewerState: Sendable, Equatable {
        case idle
        case loadingContent
        case running
    }

    public var currentState: GameState
    public var playState: PlayState?
    public var playerState: PlayerState?
    public var gameTime: GameTime
    public var saveContext: SaveContext
    public var inputState: InputState
    public var controllerInputState: ControllerInputState
    public var selectedTitleOption: TitleMenuOption
    public var fileSelectMode: FileSelectMode?
    public var statusMessage: String?
    public var sceneViewerState: SceneViewerState
    public var availableScenes: [SceneTableEntry]
    public var selectedSceneID: Int?
    public var loadedScene: LoadedScene?
    public var textureAssetURLs: [UInt32: URL]
    public var errorMessage: String?
    public var messageContext: MessageContext

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

    @ObservationIgnored
    private let timeSystem: TimeSystem

    @ObservationIgnored
    private var timeTask: Task<Void, Never>?

    @ObservationIgnored
    private let actorRegistryOverride: ActorRegistry?

    @ObservationIgnored
    private var actorContext: ActorContext?

    @ObservationIgnored
    private var collisionSystem: CollisionSystem?

    @ObservationIgnored
    private let movementConfiguration: PlayerMovementConfiguration

    @ObservationIgnored
    private var previousControllerInputState = ControllerInputState()

    @ObservationIgnored
    private var sceneManager: SceneManager?

    public init(
        currentState: GameState = .boot,
        playState: PlayState? = nil,
        playerState: PlayerState? = nil,
        gameTime: GameTime = GameTime(),
        saveContext: SaveContext = SaveContext(),
        inputState: InputState = InputState(),
        controllerInputState: ControllerInputState = ControllerInputState(),
        selectedTitleOption: TitleMenuOption = .newGame,
        fileSelectMode: FileSelectMode? = nil,
        statusMessage: String? = nil,
        sceneViewerState: SceneViewerState = .idle,
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        loadedScene: LoadedScene? = nil,
        textureAssetURLs: [UInt32: URL] = [:],
        errorMessage: String? = nil,
        messageContext: MessageContext = MessageContext(),
        contentLoader: (any ContentLoading)? = nil,
        sceneLoader: (any SceneLoading)? = nil,
        telemetryPublisher: (any TelemetryPublishing)? = nil,
        timeSystem: TimeSystem = TimeSystem(),
        actorRegistry: ActorRegistry? = nil,
        movementConfiguration: PlayerMovementConfiguration = PlayerMovementConfiguration(),
        bootDuration: Duration = .milliseconds(250),
        consoleLogoDuration: Duration = .seconds(1),
        suspender: @escaping RuntimeSuspender = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.currentState = currentState
        self.playState = playState
        self.playerState = playerState
        self.gameTime = gameTime
        self.saveContext = saveContext
        self.inputState = inputState
        self.controllerInputState = controllerInputState
        self.selectedTitleOption = selectedTitleOption
        self.fileSelectMode = fileSelectMode
        self.statusMessage = statusMessage
        self.sceneViewerState = sceneViewerState
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.errorMessage = errorMessage
        self.messageContext = messageContext
        let resolvedSceneLoader = sceneLoader ?? SceneLoader()
        self.sceneLoader = resolvedSceneLoader
        self.contentLoader = contentLoader ?? ContentLoader(sceneLoader: resolvedSceneLoader)
        self.telemetryPublisher = telemetryPublisher ?? TelemetryPublisher()
        self.timeSystem = timeSystem
        actorRegistryOverride = actorRegistry
        self.movementConfiguration = movementConfiguration
        self.bootDuration = bootDuration
        self.consoleLogoDuration = consoleLogoDuration
        self.suspender = suspender
    }

    deinit {
        timeTask?.cancel()
    }

    public var canContinue: Bool {
        saveContext.hasExistingSave
    }

    public var actors: [any Actor] {
        actorContext?.allActors ?? []
    }

    public var activeMessagePresentation: MessagePresentation? {
        messageContext.activePresentation
    }

    public var gameplayActionLabel: String? {
        if messageContext.canRequestChoiceSelection {
            return "Choose"
        }
        if messageContext.isPresenting {
            return "Next"
        }
        return activeTalkActor?.talkPrompt
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

        loadMessageCatalogIfAvailable()

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

        if playState != nil {
            do {
                try loadScene(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
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

    public func setControllerInput(_ input: ControllerInputState) {
        controllerInputState = input
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
        entranceIndex: Int? = nil,
        activeRoomIDs: Set<Int>? = nil
    ) throws {
        loadMessageCatalogIfAvailable()
        let loadedScene = try contentLoader.loadScene(id: sceneID)
        let actorTableEntries = try contentLoader.loadActorTable()
        let entranceTableEntries = (try? contentLoader.loadEntranceTable()) ?? []
        let actorTable = Dictionary(uniqueKeysWithValues: actorTableEntries.map { ($0.id, $0) })
        let manager = SceneManager(
            scene: loadedScene,
            actorTable: actorTableEntries,
            entranceTable: entranceTableEntries,
            entranceIndex: entranceIndex,
            activeRoomIDs: activeRoomIDs
        )
        let selectedRooms = manager.state.activeRoomIDs
        let textureAssetURLs = try sceneLoader.loadTextureAssetURLs(for: loadedScene)
        let registry = actorRegistryOverride ?? ActorRegistry.default(actorTable: actorTableEntries)
        let actorContext = ActorContext(
            registry: registry,
            telemetryPublisher: telemetryPublisher
        )
        let hooks = ActorRuntimeHooks(
            destroyHandler: { actor in
                actorContext.requestDestroy(actor)
            },
            messageHandler: { [weak self] messageID in
                self?.enqueueMessage(id: messageID)
            }
        )
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
            actorRuntimeHooks: hooks,
            sceneManagerState: manager.state
        )

        actorContext.spawnActors(
            for: selectedRooms,
            in: loadedScene,
            actorTable: actorTable,
            playState: playState
        )

        availableScenes = try loadAvailableScenes()
        selectedSceneID = sceneID
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.playState = playState
        self.playerState = makeInitialPlayerState(
            for: loadedScene,
            actorTable: actorTable
        )
        self.actorContext = actorContext
        sceneManager = manager
        collisionSystem = CollisionSystem(scene: loadedScene)
        sceneViewerState = .running
        errorMessage = nil
        synchronizeGameTime(with: loadedScene)
        currentState = .gameplay
        startTimeLoop()
    }

    public func setActiveRooms(_ roomIDs: Set<Int>) {
        guard
            let actorContext,
            var playState,
            let scene = playState.scene
        else {
            return
        }

        sceneManager?.syncActiveRooms(roomIDs)
        playState = playState.withActiveRooms(
            roomIDs,
            sceneManagerState: sceneManager?.state
        )
        actorContext.syncActiveRooms(
            playState.activeRoomIDs,
            in: scene,
            actorTable: playState.actorTable,
            playState: playState
        )
        self.playState = playState
    }

    public func activateDoorTransition(id triggerID: Int) throws {
        guard
            let scene = playState?.scene,
            let actorContext,
            var playState,
            var sceneManager
        else {
            return
        }

        guard let event = sceneManager.activateDoor(id: triggerID) else {
            return
        }

        switch event {
        case .roomTransition(let state):
            playState = playState.withActiveRooms(state.activeRoomIDs, sceneManagerState: state)
            actorContext.syncActiveRooms(
                state.activeRoomIDs,
                in: scene,
                actorTable: playState.actorTable,
                playState: playState
            )
            self.playState = playState
            self.sceneManager = sceneManager
        case .sceneTransition(let request):
            self.sceneManager = sceneManager
            try loadScene(id: request.sceneID, entranceIndex: request.entranceIndex)
            self.playState?.transitionEffect = request.effect
        }
    }

    public func evaluateLoadingZone(at position: Vector3s) throws {
        guard
            let scene = playState?.scene,
            let actorContext,
            var playState,
            var sceneManager
        else {
            return
        }

        guard let event = sceneManager.evaluateLoadingZones(at: position) else {
            return
        }

        switch event {
        case .roomTransition(let state):
            playState = playState.withActiveRooms(state.activeRoomIDs, sceneManagerState: state)
            actorContext.syncActiveRooms(
                state.activeRoomIDs,
                in: scene,
                actorTable: playState.actorTable,
                playState: playState
            )
            self.playState = playState
            self.sceneManager = sceneManager
        case .sceneTransition(let request):
            self.sceneManager = sceneManager
            try loadScene(id: request.sceneID, entranceIndex: request.entranceIndex)
            self.playState?.transitionEffect = request.effect
        }
    }

    public func updateFrame() {
        guard currentState == .gameplay else {
            return
        }

        gameTime.advance()

        let playerInput = messageContext.isPresenting ? ControllerInputState() : controllerInputState

        if let playerState {
            self.playerState = playerState.updating(
                input: playerInput,
                collisionSystem: collisionSystem,
                configuration: movementConfiguration
            )
        }

        applyGameplayControllerInput()

        guard let actorContext, let playState else {
            messageContext.tick(playerName: self.playState?.playerName ?? "Link")
            return
        }

        actorContext.updateAll(playState: playState)
        messageContext.tick(playerName: playState.playerName)
    }

    public func advanceGameplayFrame() {
        updateFrame()
    }

    public func handlePrimaryGameplayInput() {
        guard currentState == .gameplay else {
            return
        }

        let playerName = playState?.playerName ?? "Link"

        if messageContext.isPresenting {
            messageContext.advanceOrConfirm(playerName: playerName)
            inputState.record(
                .confirm,
                selectionIndex: messageContext.activePresentation?.choiceState?.selectedIndex ?? 0
            )
            return
        }

        guard let playState, let talkActor = activeTalkActor else {
            return
        }

        if talkActor.talkRequested(playState: playState) {
            inputState.record(.confirm, selectionIndex: 0)
            messageContext.tick(playerName: playerName)
        }
    }

    public func handleGameplaySelectionInput(delta: Int) {
        guard currentState == .gameplay, messageContext.canRequestChoiceSelection else {
            return
        }

        messageContext.moveSelection(delta: delta)
        inputState.record(
            .moveSelection,
            selectionIndex: messageContext.activePresentation?.choiceState?.selectedIndex ?? 0
        )
    }

    func advanceGameTime(byRealSeconds realSeconds: Double) {
        gameTime = timeSystem.advance(gameTime, byRealSeconds: realSeconds)
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
        if nextState == .gameplay {
            startTimeLoop()
        } else {
            stopTimeLoop()
        }
        telemetryPublisher.publish("gameRuntime.state.\(nextState.rawValue)")
    }

    private func normalizedSlotIndex(_ index: Int) -> Int {
        min(max(0, index), saveContext.slots.count - 1)
    }

    private func applyGameplayControllerInput() {
        let currentInput = controllerInputState
        let previousInput = previousControllerInputState
        defer {
            previousControllerInputState = currentInput
        }

        if currentInput.aPressed, previousInput.aPressed == false {
            handlePrimaryGameplayInput()
        }

        let choiceDelta = choiceSelectionDelta(
            previousStick: previousInput.stick,
            currentStick: currentInput.stick
        )
        if choiceDelta != 0 {
            handleGameplaySelectionInput(delta: choiceDelta)
        }
    }

    private func choiceSelectionDelta(
        previousStick: StickInput,
        currentStick: StickInput
    ) -> Int {
        guard messageContext.canRequestChoiceSelection else {
            return 0
        }

        let threshold: Float = 0.6
        let wasNeutral = previousStick.magnitude < threshold
        let isNeutral = currentStick.magnitude < threshold

        guard wasNeutral, isNeutral == false else {
            return 0
        }

        if abs(currentStick.x) > abs(currentStick.y) {
            return currentStick.x < 0 ? -1 : 1
        }

        return currentStick.y > 0 ? -1 : 1
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
        synchronizeGameTime(with: snapshot.loadedScene)
    }

    private func loadSceneViewerSnapshot(defaultSceneID: Int?) async throws -> SceneViewerSnapshot {
        let sceneLoader = self.sceneLoader
        return try await Task.detached(priority: .userInitiated) {
            let availableScenes = try Self.loadAvailableScenes(using: sceneLoader)

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

    private func activateSceneContentIfAvailable() {
        guard let playState else {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            return
        }

        guard let sceneID = sceneID(for: playState.currentSceneName) else {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            return
        }

        do {
            try loadScene(id: sceneID)
        } catch {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            statusMessage = "Gameplay scene content failed to load. Continuing with placeholder gameplay."
            telemetryPublisher.publish("gameRuntime.sceneLoadFailed")
        }
    }

    private func loadAvailableScenes() throws -> [SceneTableEntry] {
        try Self.loadAvailableScenes(using: sceneLoader)
    }

    nonisolated private static func loadAvailableScenes(using sceneLoader: any SceneLoading) throws -> [SceneTableEntry] {
        let sceneTableEntries = try sceneLoader.loadSceneTableEntries()
        return sceneTableEntries.filter { entry in
            (try? sceneLoader.resolveSceneDirectory(for: entry.index)) != nil
        }
    }

    private func makeInitialPlayerState(
        for scene: LoadedScene,
        actorTable: [Int: ActorTableEntry]
    ) -> PlayerState {
        let fallbackPosition = defaultPlayerSpawn(in: scene)
        let playerSpawn = scene.actors?.rooms
            .flatMap(\.actors)
            .first { spawn in
                guard let entry = actorTable[spawn.actorID] else {
                    return spawn.actorName.localizedCaseInsensitiveContains("player")
                }

                return ActorCategory(rawValue: entry.profile.category) == .player ||
                    spawn.actorName.localizedCaseInsensitiveContains("player")
            }

        let collisionSystem = CollisionSystem(scene: scene)
        let rawPosition = playerSpawn.map { Vec3f($0.position).simd } ?? fallbackPosition
        let probePosition = rawPosition + SIMD3<Float>(0, movementConfiguration.floorProbeHeight, 0)
        let floorHit = collisionSystem.findFloor(at: probePosition)
        let resolvedPosition = SIMD3<Float>(
            rawPosition.x,
            floorHit?.floorY ?? rawPosition.y,
            rawPosition.z
        )

        let facingRadians: Float
        if let playerSpawn {
            facingRadians = rawRotationToRadians(Float(playerSpawn.rotation.y))
        } else {
            facingRadians = 0
        }

        return PlayerState(
            position: Vec3f(resolvedPosition),
            velocity: Vec3f(x: 0, y: 0, z: 0),
            facingRadians: facingRadians,
            isGrounded: floorHit != nil,
            locomotionState: floorHit == nil ? .falling : .idle,
            animationState: PlayerAnimationState(),
            floorHeight: floorHit?.floorY
        )
    }

    private func defaultPlayerSpawn(in scene: LoadedScene) -> SIMD3<Float> {
        guard let collision = scene.collision else {
            return .zero
        }

        return SIMD3<Float>(
            (Float(collision.minimumBounds.x) + Float(collision.maximumBounds.x)) / 2,
            Float(collision.maximumBounds.y),
            (Float(collision.minimumBounds.z) + Float(collision.maximumBounds.z)) / 2
        )
    }

    private func rawRotationToRadians(_ rawValue: Float) -> Float {
        rawValue * (.pi / 32_768)
    }

    private func sceneID(for sceneName: String) -> Int? {
        switch sceneName {
        case "Kokiri Forest":
            return 0x55
        default:
            return nil
        }
    }

    private var activeTalkActor: (any TalkRequestingActor)? {
        resolveActiveTalkActor()?.actor
    }

    private func resolveActiveTalkActor() -> TalkTargetCandidate? {
        guard currentState == .gameplay, let playerState else {
            return nil
        }

        let playerPosition = playerState.position.simd
        let playerForward = SIMD2<Float>(
            sin(playerState.facingRadians),
            -cos(playerState.facingRadians)
        )
        let tieEpsilon: Float = 0.001

        return actors.enumerated()
            .compactMap { index, actor -> TalkTargetCandidate? in
                guard let talkActor = actor as? (any TalkRequestingActor) else {
                    return nil
                }

                let offset = talkActor.position.simd - playerPosition
                let planarOffset = SIMD2<Float>(offset.x, offset.z)
                let planarDistanceSquared = simd_length_squared(planarOffset)
                let maxDistanceSquared = talkActor.talkInteractionRange * talkActor.talkInteractionRange
                guard planarDistanceSquared <= maxDistanceSquared else {
                    return nil
                }

                let facingAlignment: Float
                if planarDistanceSquared > tieEpsilon {
                    facingAlignment = simd_dot(playerForward, simd_normalize(planarOffset))
                } else {
                    facingAlignment = 1
                }

                guard facingAlignment >= talkActor.talkFacingThreshold else {
                    return nil
                }

                return TalkTargetCandidate(
                    actor: talkActor,
                    distanceSquared: planarDistanceSquared,
                    facingAlignment: facingAlignment,
                    actorIndex: index
                )
            }
            .min { lhs, rhs in
                if abs(lhs.distanceSquared - rhs.distanceSquared) > tieEpsilon {
                    return lhs.distanceSquared < rhs.distanceSquared
                }
                if abs(lhs.facingAlignment - rhs.facingAlignment) > tieEpsilon {
                    return lhs.facingAlignment > rhs.facingAlignment
                }
                return lhs.actorIndex < rhs.actorIndex
            }
    }

    private struct TalkTargetCandidate {
        let actor: any TalkRequestingActor
        let distanceSquared: Float
        let facingAlignment: Float
        let actorIndex: Int
    }

    private func enqueueMessage(id messageID: Int) {
        messageContext.enqueue(
            messageID: messageID,
            playerName: playState?.playerName ?? "Link"
        )
    }

    private func loadMessageCatalogIfAvailable() {
        guard messageContext.catalog.messages.isEmpty else {
            return
        }

        if let messageCatalog = try? contentLoader.loadMessageCatalog() {
            messageContext.setCatalog(messageCatalog)
        }
    }

    private func synchronizeGameTime(with scene: LoadedScene?) {
        guard let timeOfDay = timeSystem.initialTimeOfDay(for: scene?.environment) else {
            return
        }

        gameTime.timeOfDay = timeOfDay
    }

    private func startTimeLoop() {
        guard timeTask == nil else {
            return
        }

        timeTask = Task { [weak self] in
            var previousUpdate = ContinuousClock.now

            while Task.isCancelled == false {
                try? await Task.sleep(for: TimeSystem.updateInterval)
                let now = ContinuousClock.now
                let elapsed = previousUpdate.duration(to: now).timeInterval
                previousUpdate = now

                guard let self else {
                    return
                }

                advanceGameTime(byRealSeconds: elapsed)
            }
        }
    }

    private func stopTimeLoop() {
        timeTask?.cancel()
        timeTask = nil
    }
}
