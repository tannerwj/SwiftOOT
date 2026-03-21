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
    public var inventoryContext: InventoryContext
    public var runtimeState: SaveRuntimeState

    public var inventoryState: GameplayInventoryState {
        get { inventoryContext.gameplay }
        set { inventoryContext.gameplay = newValue }
    }

    public var playTimeFrames: Int {
        runtimeState.playTimeFrames
    }

    public var playTimeDisplay: String {
        let totalSeconds = playTimeFrames / 60
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var questPreviewSummary: String {
        let questStatus = inventoryContext.questStatus
        let components = [
            questStatus.songs.isEmpty ? nil : "\(questStatus.songs.count) Songs",
            questStatus.stones.isEmpty ? nil : "\(questStatus.stones.count) Stones",
            questStatus.medallions.isEmpty ? nil : "\(questStatus.medallions.count) Medallions",
        ].compactMap { $0 }

        return components.isEmpty ? "No quest items" : components.joined(separator: "  •  ")
    }

    public init(
        id: Int,
        playerName: String = "Empty Slot",
        locationName: String = "Unused",
        hearts: Int = 3,
        hasSaveData: Bool = false,
        inventoryState: GameplayInventoryState? = nil,
        inventoryContext: InventoryContext? = nil,
        runtimeState: SaveRuntimeState? = nil
    ) {
        let resolvedInventoryContext = inventoryContext ?? InventoryContext(
            gameplay: inventoryState ?? .starter(hearts: hearts)
        )
        let resolvedRuntimeState = runtimeState ?? SaveRuntimeState(
            spawnLocation: SaveSpawnLocation(sceneName: locationName)
        )
        self.id = id
        self.playerName = playerName
        self.locationName = locationName
        self.hearts = max(1, resolvedInventoryContext.gameplay.maximumHealthUnits / 2)
        self.hasSaveData = hasSaveData
        self.inventoryContext = resolvedInventoryContext
        self.runtimeState = resolvedRuntimeState
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
            hasSaveData: true,
            inventoryContext: .starter(hearts: 3),
            runtimeState: .starter(sceneName: "Kokiri Forest")
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case playerName
        case locationName
        case hearts
        case hasSaveData
        case inventoryContext
        case inventoryState
        case runtimeState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let playerName = try container.decode(String.self, forKey: .playerName)
        let locationName = try container.decode(String.self, forKey: .locationName)
        let hearts = try container.decode(Int.self, forKey: .hearts)
        let hasSaveData = try container.decode(Bool.self, forKey: .hasSaveData)
        let inventoryContext = try container.decodeIfPresent(
            InventoryContext.self,
            forKey: .inventoryContext
        ) ?? InventoryContext(
            gameplay: try container.decodeIfPresent(
            GameplayInventoryState.self,
            forKey: .inventoryState
            ) ?? .starter(hearts: hearts)
        )
        let runtimeState = try container.decodeIfPresent(
            SaveRuntimeState.self,
            forKey: .runtimeState
        ) ?? SaveRuntimeState(
            spawnLocation: SaveSpawnLocation(sceneName: locationName)
        )

        self.init(
            id: id,
            playerName: playerName,
            locationName: locationName,
            hearts: hearts,
            hasSaveData: hasSaveData,
            inventoryContext: inventoryContext,
            runtimeState: runtimeState
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(playerName, forKey: .playerName)
        try container.encode(locationName, forKey: .locationName)
        try container.encode(hearts, forKey: .hearts)
        try container.encode(hasSaveData, forKey: .hasSaveData)
        try container.encode(inventoryContext, forKey: .inventoryContext)
        try container.encode(inventoryState, forKey: .inventoryState)
        try container.encode(runtimeState, forKey: .runtimeState)
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

public enum GameplayHUDButtonItem: String, Codable, Sendable, Equatable {
    case sword
    case shield
    case slingshot
    case bow
    case bomb
    case boomerang
    case dekuStick
    case dekuNut
    case ocarina
    case bottle
    case none

    public var actionLabel: String {
        switch self {
        case .sword:
            return "Attack"
        case .shield:
            return "Guard"
        case .slingshot:
            return "Shoot"
        case .bow:
            return "Fire"
        case .bomb:
            return "Bomb"
        case .boomerang:
            return "Throw"
        case .dekuStick:
            return "Stick"
        case .dekuNut:
            return "Throw"
        case .ocarina:
            return "Play"
        case .bottle:
            return "Use"
        case .none:
            return "Action"
        }
    }
}

public struct GameplayHUDState: Codable, Sendable, Equatable {
    public var currentHealthUnits: Int
    public var maximumHealthUnits: Int
    public var currentMagic: Int
    public var maximumMagic: Int
    public var rupees: Int
    public var smallKeyCount: Int?
    public var bButtonItem: GameplayHUDButtonItem
    public var cButtons: GameplayHUDCButtonState
    public var actionLabelOverride: String?

    public init(
        currentHealthUnits: Int = 6,
        maximumHealthUnits: Int = 6,
        currentMagic: Int = 0,
        maximumMagic: Int = 0,
        rupees: Int = 0,
        smallKeyCount: Int? = nil,
        bButtonItem: GameplayHUDButtonItem = .sword,
        cButtons: GameplayHUDCButtonState = GameplayHUDCButtonState(),
        actionLabelOverride: String? = nil
    ) {
        let normalizedMaximumHealthUnits = max(2, maximumHealthUnits)
        self.currentHealthUnits = min(max(0, currentHealthUnits), normalizedMaximumHealthUnits)
        self.maximumHealthUnits = normalizedMaximumHealthUnits
        let normalizedMaximumMagic = max(0, maximumMagic)
        self.currentMagic = min(max(0, currentMagic), normalizedMaximumMagic)
        self.maximumMagic = normalizedMaximumMagic
        self.rupees = max(0, rupees)
        self.smallKeyCount = smallKeyCount.map { max(0, $0) }
        self.bButtonItem = bButtonItem
        self.cButtons = cButtons
        self.actionLabelOverride = actionLabelOverride
    }

    public static func starter(hearts: Int) -> Self {
        let healthUnits = max(2, hearts * 2)
        return GameplayHUDState(
            currentHealthUnits: healthUnits,
            maximumHealthUnits: healthUnits,
            currentMagic: 48,
            maximumMagic: 96,
            rupees: 0,
            smallKeyCount: nil,
            bButtonItem: .sword,
            cButtons: GameplayHUDCButtonState(),
            actionLabelOverride: nil
        )
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

    @MainActor
    public func requestChestOpen(_ request: TreasureChestOpenRequest) -> Bool {
        actorRuntimeHooks?.requestChestOpen(request) ?? false
    }

    @MainActor
    public func isTreasureOpened(_ key: TreasureFlagKey) -> Bool {
        actorRuntimeHooks?.isTreasureOpened(key) ?? false
    }

    @MainActor
    public func requestSpawn(
        _ actor: any Actor,
        category: ActorCategory,
        roomID: Int
    ) {
        actorRuntimeHooks?.requestSpawn(actor, category: category, roomID: roomID)
    }

    @MainActor
    public func requestReward(_ reward: ActorReward) {
        actorRuntimeHooks?.requestReward(reward)
    }

    @MainActor
    public var currentPlayerState: PlayerState? {
        actorRuntimeHooks?.currentPlayerState()
    }
    @MainActor
    public func currentInventoryState() -> GameplayInventoryState {
        actorRuntimeHooks?.currentInventoryState() ?? .starter(hearts: 3)
    }

    @MainActor
    public func markDungeonEventTriggered(_ key: DungeonEventFlagKey) {
        actorRuntimeHooks?.markDungeonEventTriggered(key)
    }

    @MainActor
    public func isDungeonEventTriggered(_ key: DungeonEventFlagKey) -> Bool {
        actorRuntimeHooks?.isDungeonEventTriggered(key) ?? false
    }
    public var currentSceneIdentity: SceneIdentity? {
        guard currentSceneName.isEmpty == false else {
            return nil
        }

        return SceneIdentity(
            id: currentSceneID,
            name: currentSceneName
        )
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
    public var hudState: GameplayHUDState
    public var inventoryContext: InventoryContext
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
    public var itemGetSequence: ItemGetSequenceState?
    public var combatState: GameplayCombatState
    public var soundEffectVolumeSettings: SoundEffectVolumeSettings
    public var isCButtonItemEditorPresented: Bool
    public var ocarinaSession: OcarinaSessionState?
    public var ocarinaRecognition: OcarinaRecognitionState?
    public var lastResolvedOcarinaEffect: OcarinaWorldEffectResult?
    public var globalEventFlags: Set<Int>
    public var sceneEventFlags: [SceneIdentity: Set<Int>]
    public var deathCount: Int
    public var goldSkulltulaFlags: Set<TreasureFlagKey>
    public var directorCommentaryCatalog: DirectorCommentaryCatalog
    public var isDirectorCommentaryEnabled: Bool
    public var directorCommentaryShowsWorldMarkers: Bool
    public var selectedDirectorCommentaryAnnotationID: String?
    public var activeDirectorCommentaryAnnotationID: String?
    public var audioTrackCatalog: AudioTrackCatalog?
    public var musicPlaybackState: MusicPlaybackState

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
    private let saveRepository: SaveRepository?

    @ObservationIgnored
    private let musicPlaybackController: (any MusicPlaybackControlling)?

    @ObservationIgnored
    private var musicTransitionTask: Task<Void, Never>?

    @ObservationIgnored
    private var requiresMusicResynchronizationAfterPause = false

    @ObservationIgnored
    private var activePlayTimeFrames: Int

    @ObservationIgnored
    var previousControllerInputState = ControllerInputState()

    @ObservationIgnored
    private var movementReferenceYaw: Float?

    @ObservationIgnored
    private var sceneManager: SceneManager?

    @ObservationIgnored
    private var fixedTimeOfDayOverride: Double?

    @ObservationIgnored
    var combatLockOnTargetID: ObjectIdentifier?

    @ObservationIgnored
    var activePlayerAttackState: ActivePlayerAttackState?

    @ObservationIgnored
    var playerInvincibilityFramesRemaining = 0

    @ObservationIgnored
    var bButtonChargeFrames = 0

    @ObservationIgnored
    var activeSlingshotAimState: SlingshotAimState?

    @ObservationIgnored
    var activeDekuStickState: EquippedDekuStickState?

    @ObservationIgnored
    var previousDirectorCommentaryAnnotationIDs: Set<String> = []

    @ObservationIgnored
    var soundEffectsByEvent: [NamedSoundEffect: ResolvedSoundEffect] = [:]

    @ObservationIgnored
    var pendingSoundEffectPlaybackRequests: [SoundEffectPlaybackRequest] = []

    @ObservationIgnored
    var activeSoundEffects: [ActiveSoundEffectState] = []

    @ObservationIgnored
    var nextSoundEffectRequestID = 1

    public var inventoryState: GameplayInventoryState {
        get { inventoryContext.gameplay }
        set { inventoryContext.gameplay = newValue }
    }

    public var pauseMenuState: PauseMenuState {
        get { inventoryContext.pauseMenu }
        set { inventoryContext.pauseMenu = newValue }
    }

    public var visitedSceneIDs: Set<Int> {
        var visitedSceneIDs = inventoryState.visitedSceneIDs
        if let currentSceneID = playState?.currentSceneID ?? loadedScene?.manifest.id ?? selectedSceneID {
            visitedSceneIDs.insert(currentSceneID)
        }
        return visitedSceneIDs
    }

    public init(
        currentState: GameState = .boot,
        playState: PlayState? = nil,
        playerState: PlayerState? = nil,
        gameTime: GameTime = GameTime(),
        saveContext: SaveContext = SaveContext(),
        inputState: InputState = InputState(),
        controllerInputState: ControllerInputState = ControllerInputState(),
        hudState: GameplayHUDState = GameplayHUDState(),
        inventoryState: GameplayInventoryState = .starter(hearts: 3),
        inventoryContext: InventoryContext? = nil,
        selectedTitleOption: TitleMenuOption = .newGame,
        fileSelectMode: FileSelectMode? = nil,
        statusMessage: String? = nil,
        sceneViewerState: SceneViewerState = .idle,
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        loadedScene: LoadedScene? = nil,
        textureAssetURLs: [UInt32: URL] = [:],
        audioTrackCatalog: AudioTrackCatalog? = nil,
        musicPlaybackState: MusicPlaybackState = MusicPlaybackState(),
        errorMessage: String? = nil,
        messageContext: MessageContext = MessageContext(),
        itemGetSequence: ItemGetSequenceState? = nil,
        combatState: GameplayCombatState = GameplayCombatState(),
        soundEffectVolumeSettings: SoundEffectVolumeSettings = SoundEffectVolumeSettings(),
        isCButtonItemEditorPresented: Bool = false,
        ocarinaSession: OcarinaSessionState? = nil,
        ocarinaRecognition: OcarinaRecognitionState? = nil,
        lastResolvedOcarinaEffect: OcarinaWorldEffectResult? = nil,
        globalEventFlags: Set<Int> = [],
        sceneEventFlags: [SceneIdentity: Set<Int>] = [:],
        deathCount: Int = 0,
        goldSkulltulaFlags: Set<TreasureFlagKey> = [],
        directorCommentaryCatalog: DirectorCommentaryCatalog = DirectorCommentaryLibrary.bundledCatalog(),
        isDirectorCommentaryEnabled: Bool = false,
        directorCommentaryShowsWorldMarkers: Bool = false,
        selectedDirectorCommentaryAnnotationID: String? = nil,
        activeDirectorCommentaryAnnotationID: String? = nil,
        activePlayTimeFrames: Int = 0,
        contentLoader: (any ContentLoading)? = nil,
        sceneLoader: (any SceneLoading)? = nil,
        musicPlaybackController: (any MusicPlaybackControlling)? = nil,
        telemetryPublisher: (any TelemetryPublishing)? = nil,
        saveRepository: SaveRepository? = nil,
        timeSystem: TimeSystem = TimeSystem(gameMinutesPerRealSecond: 0.1),
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
        self.hudState = hudState
        self.inventoryContext = inventoryContext ?? InventoryContext(gameplay: inventoryState)
        self.selectedTitleOption = selectedTitleOption
        self.fileSelectMode = fileSelectMode
        self.statusMessage = statusMessage
        self.sceneViewerState = sceneViewerState
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.audioTrackCatalog = audioTrackCatalog
        self.musicPlaybackState = musicPlaybackState
        self.errorMessage = errorMessage
        self.messageContext = messageContext
        self.itemGetSequence = itemGetSequence
        self.combatState = combatState
        self.soundEffectVolumeSettings = soundEffectVolumeSettings
        self.isCButtonItemEditorPresented = isCButtonItemEditorPresented
        self.ocarinaSession = ocarinaSession
        self.ocarinaRecognition = ocarinaRecognition
        self.lastResolvedOcarinaEffect = lastResolvedOcarinaEffect
        self.globalEventFlags = globalEventFlags
        self.sceneEventFlags = sceneEventFlags
        self.deathCount = max(0, deathCount)
        self.goldSkulltulaFlags = goldSkulltulaFlags
        self.directorCommentaryCatalog = directorCommentaryCatalog
        self.isDirectorCommentaryEnabled = isDirectorCommentaryEnabled
        self.directorCommentaryShowsWorldMarkers = directorCommentaryShowsWorldMarkers
        self.selectedDirectorCommentaryAnnotationID = selectedDirectorCommentaryAnnotationID
        self.activeDirectorCommentaryAnnotationID = activeDirectorCommentaryAnnotationID
        self.activePlayTimeFrames = max(0, activePlayTimeFrames)
        let resolvedSceneLoader = sceneLoader ?? SceneLoader()
        self.sceneLoader = resolvedSceneLoader
        self.contentLoader = contentLoader ?? ContentLoader(sceneLoader: resolvedSceneLoader)
        self.musicPlaybackController = musicPlaybackController
        self.telemetryPublisher = telemetryPublisher ?? TelemetryPublisher()
        self.saveRepository = saveRepository
        self.timeSystem = timeSystem
        actorRegistryOverride = actorRegistry
        self.movementConfiguration = movementConfiguration
        self.bootDuration = bootDuration
        self.consoleLogoDuration = consoleLogoDuration
        self.suspender = suspender
    }

    deinit {
        musicTransitionTask?.cancel()
        timeTask?.cancel()
    }

    public var canContinue: Bool {
        saveContext.hasExistingSave
    }

    public var actors: [any Actor] {
        actorContext?.allActors ?? []
    }

    public var activeMessagePresentation: MessagePresentation? {
        itemGetSequence?.phase == .displayingText ? itemGetSequence?.messagePresentation : messageContext.activePresentation
    }

    public var gameplayActionLabel: String? {
        if itemGetSequence?.phase == .displayingText {
            return "Next"
        }
        if itemGetSequence != nil {
            return nil
        }
        if let ocarinaSession {
            switch ocarinaSession.mode {
            case .freePlay, .teachingRepeat:
                return "Note"
            case .teachingPlayback:
                return "Listen"
            }
        }
        if isCButtonItemEditorPresented {
            return nil
        }
        if messageContext.canRequestChoiceSelection {
            return "Choose"
        }
        if messageContext.isPresenting {
            return "Next"
        }
        if let combatActionLabel {
            return combatActionLabel
        }
        return activeTalkActor?.talkPrompt
    }

    public var gameplayHUDActionLabel: String {
        gameplayActionLabel ?? hudState.actionLabelOverride ?? hudState.bButtonItem.actionLabel
    }

    public var activeItemGetOverlay: ItemGetOverlayState? {
        guard let itemGetSequence else {
            return nil
        }

        return ItemGetOverlayState(
            title: itemGetSequence.reward.title,
            description: itemGetSequence.reward.description,
            iconName: itemGetSequence.reward.iconName,
            phase: itemGetSequence.phase
        )
    }

    public var availableAudioTracks: [AudioTrackManifest] {
        audioTrackCatalog?.tracks ?? []
    }

    public func playMusicTrack(
        id trackID: String,
        crossfadeDuration: TimeInterval = 1.0
    ) {
        _ = playMusicTrack(
            id: trackID,
            crossfadeDuration: crossfadeDuration,
            announcesStatus: true
        )
    }

    public func crossfadeMusicTrack(
        to trackID: String,
        duration: TimeInterval = 1.0
    ) {
        playMusicTrack(id: trackID, crossfadeDuration: duration)
    }

    public func pauseMusicTrack() {
        pauseMusicTrack(announcesStatus: true)
    }

    public func resumeMusicTrack() {
        resumeMusicTrack(announcesStatus: true)
    }

    public func stopMusicTrack() {
        stopMusicTrack(announcesStatus: true)
    }

    func pauseMusicTrack(announcesStatus: Bool) {
        guard musicPlaybackState.currentTrack != nil else {
            return
        }

        requiresMusicResynchronizationAfterPause = false
        musicTransitionTask?.cancel()
        musicTransitionTask = nil
        musicPlaybackController?.pause()
        musicPlaybackState.phase = .paused
        musicPlaybackState.pendingTrack = nil
        if announcesStatus {
            statusMessage = "Audio preview paused."
        }
    }

    func resumeMusicTrack(announcesStatus: Bool) {
        guard musicPlaybackState.currentTrack != nil else {
            return
        }

        requiresMusicResynchronizationAfterPause = false
        musicPlaybackController?.resume()
        musicPlaybackState.phase = .playing
        if announcesStatus {
            statusMessage = "Audio preview resumed."
        }
    }

    func stopMusicTrack(announcesStatus: Bool) {
        requiresMusicResynchronizationAfterPause = false
        musicTransitionTask?.cancel()
        musicTransitionTask = nil
        musicPlaybackController?.stop()
        musicPlaybackState = MusicPlaybackState()
        if announcesStatus {
            statusMessage = "Audio preview stopped."
        }
    }

    func pauseMusicForPauseMenu() {
        let requiresResynchronization =
            musicPlaybackState.pendingTrack != nil ||
            musicPlaybackState.currentTrack?.kind != .bgm
        pauseMusicTrack(announcesStatus: false)
        requiresMusicResynchronizationAfterPause = requiresResynchronization
    }

    func resumeMusicForPauseMenu() {
        guard musicPlaybackState.currentTrack != nil else {
            requiresMusicResynchronizationAfterPause = false
            return
        }

        if requiresMusicResynchronizationAfterPause {
            requiresMusicResynchronizationAfterPause = false
            synchronizeMusicForCurrentContext(crossfadeDuration: 0.35)
            return
        }

        resumeMusicTrack(announcesStatus: false)
    }

    public func developerRuntimeStateSnapshot() -> DeveloperRuntimeStateSnapshot {
        let talkTarget = resolveActiveTalkActor()
        let message = activeMessagePresentation.map { presentation in
            DeveloperRuntimeStateSnapshot.MessageSnapshot(
                messageID: presentation.messageID,
                phase: presentation.phase.rawValue,
                variant: presentation.variant.rawValue,
                selectedChoiceIndex: presentation.choiceState?.selectedIndex,
                choiceCount: presentation.choiceState?.options.count ?? 0
            )
        }

        return DeveloperRuntimeStateSnapshot(
            gameState: currentState,
            frameCount: gameTime.frameCount,
            timeOfDay: gameTime.timeOfDay,
            sceneName: playState?.currentSceneName ?? loadedScene?.manifest.title ?? loadedScene?.manifest.name,
            sceneID: playState?.currentSceneID ?? loadedScene?.manifest.id,
            roomID: playState?.currentRoomID,
            entranceIndex: playState?.currentEntranceIndex,
            spawnIndex: playState?.currentSpawnIndex,
            activeRoomIDs: Array(playState?.activeRoomIDs.sorted() ?? []),
            loadedObjectIDs: playState?.loadedObjectIDs ?? [],
            playerName: playState?.playerName,
            player: playerState.map { playerState in
                DeveloperRuntimeStateSnapshot.PlayerSnapshot(
                    position: .init(playerState.position),
                    velocity: .init(playerState.velocity),
                    facingRadians: playerState.facingRadians,
                    isGrounded: playerState.isGrounded,
                    locomotionState: playerState.locomotionState.rawValue,
                    animationClip: playerState.animationState.currentClip.rawValue,
                    animationFrame: playerState.animationState.currentFrame,
                    floorHeight: playerState.floorHeight
                )
            },
            message: message,
            talkTarget: talkTarget.map { target in
                DeveloperRuntimeStateSnapshot.TalkTargetSnapshot(
                    actorID: target.actor.profile.id,
                    actorType: String(describing: type(of: target.actor)),
                    prompt: target.actor.talkPrompt,
                    position: .init(target.actor.position),
                    planarDistance: sqrt(target.distanceSquared),
                    facingAlignment: target.facingAlignment
                )
            },
            actionLabel: gameplayActionLabel,
            statusMessage: statusMessage,
            errorMessage: errorMessage,
            musicPlayback: DeveloperRuntimeStateSnapshot.MusicPlaybackSnapshot(
                phase: musicPlaybackState.phase,
                currentTrack: musicPlaybackState.currentTrack,
                pendingTrack: musicPlaybackState.pendingTrack
            ),
            directorCommentary: DeveloperRuntimeStateSnapshot.DirectorCommentarySnapshot(
                isEnabled: isDirectorCommentaryEnabled,
                showsWorldMarkers: directorCommentaryShowsWorldMarkers,
                selectedAnnotationID: selectedDirectorCommentaryAnnotationID,
                activeAnnotationID: activeDirectorCommentaryAnnotationID,
                activeAnnotationIDs: activeDirectorCommentaryAnnotations.map(\.id),
                visibleWorldMarkerCount: directorCommentaryVisibleWorldMarkers.count
            ),
            inventoryContext: inventoryContext,
            hudState: hudState
        )
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

        loadAudioTrackCatalogIfAvailable()
        loadMessageCatalogIfAvailable()
        loadSoundEffectCatalogIfAvailable()

        await suspender(bootDuration)
        transition(to: .consoleLogo)
        await suspender(consoleLogoDuration)
        transition(to: .titleScreen)
    }

    public func launchDeveloperScene(
        _ configuration: DeveloperSceneLaunchConfiguration
    ) async throws {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        currentState = .boot
        statusMessage = nil
        errorMessage = nil
        fileSelectMode = nil
        isCButtonItemEditorPresented = false
        selectedTitleOption = .newGame
        saveContext.selectedSlotIndex = 0
        if !saveContext.slots.isEmpty {
            saveContext.slots[0] = SaveSlot.starter(id: 0)
        }
        hudState = .starter(hearts: 3)
        fixedTimeOfDayOverride = configuration.fixedTimeOfDay.map(Self.normalizedTimeOfDay)

        do {
            try await contentLoader.loadInitialContent()
        } catch {
            statusMessage = "Initial content load failed. Continuing with placeholder content."
            telemetryPublisher.publish("gameRuntime.contentLoadFailed")
        }

        loadAudioTrackCatalogIfAvailable()
        loadMessageCatalogIfAvailable()
        loadSoundEffectCatalogIfAvailable()

        let availableScenes = try loadAvailableScenes()
        self.availableScenes = availableScenes

        let sceneID = try resolveDeveloperSceneID(
            selection: configuration.scene,
            availableScenes: availableScenes
        )
        let manifest = try sceneLoader.loadSceneManifest(id: sceneID)
        let sceneName = manifest.title ?? manifest.name

        playState = PlayState(
            activeSaveSlot: 0,
            entryMode: .newGame,
            currentSceneName: sceneName,
            currentSceneID: sceneID,
            currentEntranceIndex: configuration.entranceIndex,
            currentSpawnIndex: configuration.spawnIndex,
            playerName: "Link"
        )

        try loadScene(
            id: sceneID,
            entranceIndex: configuration.entranceIndex,
            spawnIndex: configuration.spawnIndex
        )
        if let fixedTimeOfDayOverride {
            gameTime.timeOfDay = fixedTimeOfDayOverride
        }
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
        queueSoundEffect(.uiConfirm)

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
        queueSoundEffect(.uiConfirm)

        switch fileSelectMode {
        case .newGame:
            startNewGame(in: saveContext.selectedSlotIndex)
        case .continueGame:
            continueGame(from: saveContext.selectedSlotIndex)
        }
    }

    public func returnToTitleScreen() {
        persistActiveSaveSlotState()
        fileSelectMode = nil
        statusMessage = nil
        inputState.record(.cancel, selectionIndex: saveContext.selectedSlotIndex)
        queueSoundEffect(.uiCancel)
        transition(to: .titleScreen)
    }

    public func setControllerInput(_ input: ControllerInputState) {
        controllerInputState = input
    }

    public func setMovementReferenceYaw(_ yaw: Float?) {
        movementReferenceYaw = yaw
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
        beginGameplay(using: slot, entryMode: .newGame)
    }

    private func continueGame(from index: Int) {
        let normalizedIndex = normalizedSlotIndex(index)
        let slot = saveContext.slots[normalizedIndex]

        guard slot.hasSaveData else {
            statusMessage = "Select a populated save slot to continue."
            telemetryPublisher.publish("gameRuntime.continueRejected.emptySlot")
            return
        }

        beginGameplay(using: slot, entryMode: .continueGame)
    }

    public func saveCurrentGame() {
        guard currentState == .gameplay, playState != nil else {
            statusMessage = "Start a quest before saving."
            return
        }

        persistActiveSaveSlotState()
        flushSaveContextToDisk(
            telemetryEvent: "gameRuntime.manualSave",
            successMessage: "Saved File \(saveContext.selectedSlotIndex + 1).",
            failurePrefix: "Save failed"
        )
    }

    private func beginGameplay(
        using slot: SaveSlot,
        entryMode: PlayState.EntryMode
    ) {
        inventoryContext = slot.inventoryContext
        inventoryContext.pauseMenu = PauseMenuState()
        activePlayTimeFrames = slot.playTimeFrames
        deathCount = slot.runtimeState.deathCount
        globalEventFlags = slot.runtimeState.globalEventFlags
        sceneEventFlags = slot.runtimeState.sceneEventFlags
        goldSkulltulaFlags = slot.runtimeState.goldSkulltulaFlags

        hudState = GameplayHUDState(
            currentHealthUnits: inventoryContext.gameplay.currentHealthUnits,
            maximumHealthUnits: inventoryContext.gameplay.maximumHealthUnits,
            currentMagic: slot.runtimeState.currentMagic,
            maximumMagic: slot.runtimeState.maximumMagic,
            rupees: slot.runtimeState.rupees,
            bButtonItem: inventoryContext.equipment.equippedSword == nil ? .none : .sword
        )
        synchronizeHUDStateWithInventory()
        itemGetSequence = nil
        resetCombatState()
        isCButtonItemEditorPresented = false

        let spawnLocation = slot.runtimeState.spawnLocation
        let sceneName = spawnLocation.sceneName.isEmpty ? slot.locationName : spawnLocation.sceneName
        playState = PlayState(
            activeSaveSlot: normalizedSlotIndex(slot.id),
            entryMode: entryMode,
            currentSceneName: sceneName,
            currentSceneID: spawnLocation.sceneID,
            currentEntranceIndex: spawnLocation.entranceIndex,
            currentSpawnIndex: spawnLocation.spawnIndex,
            playerName: slot.playerName
        )
        fileSelectMode = nil
        statusMessage = nil
        activateSceneContentIfAvailable()
        persistActiveSaveSlotState()
        transition(to: .gameplay)
    }

    public func loadScene(
        id sceneID: Int,
        entranceIndex: Int? = nil,
        spawnIndex: Int? = nil,
        activeRoomIDs: Set<Int>? = nil
    ) throws {
        let previousSceneID = playState?.currentSceneID ?? loadedScene?.manifest.id
        loadMessageCatalogIfAvailable()
        loadSoundEffectCatalogIfAvailable()
        let loadedScene = try contentLoader.loadScene(id: sceneID)
        let actorTableEntries = try contentLoader.loadActorTable()
        let entranceTableEntries = (try? contentLoader.loadEntranceTable()) ?? []
        let actorTable = Dictionary(uniqueKeysWithValues: actorTableEntries.map { ($0.id, $0) })
        let manager = SceneManager(
            scene: loadedScene,
            actorTable: actorTableEntries,
            entranceTable: entranceTableEntries,
            entranceIndex: entranceIndex,
            spawnIndex: spawnIndex,
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
            spawnHandler: { actor, category, roomID in
                actorContext.enqueueSpawn(actor, category: category, roomID: roomID)
            },
            playerStateProvider: { [weak self] in
                self?.playerState
            },
            messageHandler: { [weak self] messageID in
                self?.enqueueMessage(id: messageID)
            },
            chestOpenHandler: { [weak self] request in
                self?.beginChestOpenSequence(request) ?? false
            },
            treasureQueryHandler: { [weak self] key in
                self?.inventoryState.hasOpenedTreasure(key) ?? false
            },
            rewardHandler: { [weak self] reward in
                self?.grantActorReward(reward)
            },
            inventoryStateHandler: { [weak self] in
                self?.inventoryState ?? .starter(hearts: 3)
            },
            dungeonEventHandler: { [weak self] key in
                self?.markDungeonEventTriggered(key)
            },
            dungeonEventQueryHandler: { [weak self] key in
                self?.inventoryState.hasTriggeredDungeonEvent(key) ?? false
            }
        )
        let basePlayState = playState ?? PlayState(
            activeSaveSlot: 0,
            entryMode: .newGame,
            currentSceneName: loadedScene.manifest.title ?? loadedScene.manifest.name,
            playerName: "Link"
        )
        var playState = basePlayState.withActorRuntime(
            scene: loadedScene,
            actorTable: actorTable,
            activeRoomIDs: selectedRooms,
            actorRuntimeHooks: hooks,
            sceneManagerState: manager.state
        )
        playState.currentSceneName = loadedScene.manifest.title ?? loadedScene.manifest.name

        actorContext.spawnActors(
            for: selectedRooms,
            in: loadedScene,
            actorTable: actorTable,
            playState: playState
        )

        availableScenes = try loadAvailableScenes()
        selectedSceneID = sceneID
        inventoryState.markSceneVisited(loadedScene.manifest.id)
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.playState = playState
        self.playerState = makeInitialPlayerState(
            for: loadedScene,
            actorTable: actorTable,
            preferredSpawnIndex: manager.state.currentSpawnIndex
        )
        resetCombatState()
        self.actorContext = actorContext
        sceneManager = manager
        collisionSystem = CollisionSystem(scene: loadedScene)
        sceneViewerState = .running
        errorMessage = nil
        synchronizeGameTime(with: loadedScene)
        synchronizeHUDStateWithInventory()
        refreshDirectorCommentary(forcePresentation: true)
        persistActiveSaveSlotState(sceneName: playState.currentSceneName)
        if currentState == .gameplay, previousSceneID != sceneID {
            flushSaveContextToDisk(telemetryEvent: "gameRuntime.autoSave.sceneTransition")
        }
        currentState = .gameplay
        queueAmbientSoundIfNeeded(for: loadedScene)
        synchronizeMusicForCurrentContext(
            crossfadeDuration: musicPlaybackState.currentTrack == nil || previousSceneID == sceneID ? 0 : 1.0
        )
        syncXRayTelemetry()
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
        syncXRayTelemetry()
        refreshDirectorCommentary(forcePresentation: true)
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
            syncXRayTelemetry()
            refreshDirectorCommentary()
        case .sceneTransition(let request):
            self.sceneManager = sceneManager
            try loadScene(id: request.sceneID, entranceIndex: request.entranceIndex)
            self.playState?.transitionEffect = request.effect
            refreshDirectorCommentary(forcePresentation: true)
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
            syncXRayTelemetry()
            refreshDirectorCommentary()
        case .sceneTransition(let request):
            self.sceneManager = sceneManager
            try loadScene(id: request.sceneID, entranceIndex: request.entranceIndex)
            self.playState?.transitionEffect = request.effect
            refreshDirectorCommentary(forcePresentation: true)
        }
    }

    public func updateFrame() {
        guard currentState == .gameplay else {
            return
        }

        let currentInput = controllerInputState
        let previousInput = previousControllerInputState
        defer {
            previousControllerInputState = currentInput
            refreshDirectorCommentary()
        }

        if handlePauseMenuInput(currentInput: currentInput, previousInput: previousInput) {
            syncCombatObservationState()
            syncXRayTelemetry()
            return
        }

        gameTime.advance()
        activePlayTimeFrames += 1
        cleanupExpiredSoundEffects()
        if let fixedTimeOfDayOverride {
            gameTime.timeOfDay = fixedTimeOfDayOverride
        }

        if updateOcarinaState(
            currentInput: currentInput,
            previousInput: previousInput
        ) {
            messageContext.tick(playerName: self.playState?.playerName ?? "Link")
            syncCombatObservationState()
            syncXRayTelemetry()
            return
        }

        let playerInput = (isGameplayPresentationActive || isCButtonItemEditorPresented)
            ? ControllerInputState()
            : currentInput
        let movementInput = movementInputState(for: playerInput)

        if let playerState {
            self.playerState = playerState.updating(
                input: movementInput,
                movementReferenceYaw: movementReferenceYaw,
                lockOnTargetPosition: currentLockOnTargetFocusPoint(),
                collisionSystem: collisionSystem,
                configuration: movementConfiguration,
                forcedDisplacement: activePlayerAttackForcedDisplacement()
            )
        }

        updateGameplayItemState(currentInput: playerInput)
        updateCombatStateBeforeActorStep(currentInput: playerInput)
        advanceItemGetSequenceIfNeeded()

        guard let actorContext, let playState else {
            messageContext.tick(playerName: self.playState?.playerName ?? "Link")
            syncCombatObservationState()
            syncXRayTelemetry()
            return
        }

        actorContext.updateAll(playState: playState)
        updateCombatStateAfterActorStep(playState: playState, currentInput: playerInput)
        processSceneTransitionsIfNeeded()
        let allowPrimaryAction = canUsePrimaryGameplayInput(for: playerInput)
        applyGameplayControllerInput(
            currentInput: currentInput,
            previousInput: previousInput,
            allowPrimaryAction: allowPrimaryAction
        )
        messageContext.tick(playerName: playState.playerName)
        syncCombatObservationState()
        syncXRayTelemetry()
    }

    public func advanceGameplayFrame() {
        updateFrame()
    }

    public func handlePrimaryGameplayInput() {
        guard currentState == .gameplay else {
            return
        }

        let playerName = playState?.playerName ?? "Link"

        if handleItemGetPrimaryInput() {
            inputState.record(.confirm, selectionIndex: 0)
            queueSoundEffect(.uiConfirm)
            return
        }

        if messageContext.isPresenting {
            messageContext.advanceOrConfirm(playerName: playerName)
            inputState.record(
                .confirm,
                selectionIndex: messageContext.activePresentation?.choiceState?.selectedIndex ?? 0
            )
            queueSoundEffect(.uiConfirm)
            return
        }

        guard let playState, let talkActor = activeTalkActor else {
            return
        }

        if talkActor.talkRequested(playState: playState) {
            inputState.record(.confirm, selectionIndex: 0)
            messageContext.tick(playerName: playerName)
            if talkActor is TreasureChestActor {
                queueSoundEffect(.chestOpen, sourcePosition: talkActor.position)
            } else {
                queueSoundEffect(.talkConfirm, sourcePosition: talkActor.position)
            }
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
        guard fixedTimeOfDayOverride == nil else {
            if let fixedTimeOfDayOverride {
                gameTime.timeOfDay = fixedTimeOfDayOverride
            }
            return
        }
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
        if nextState != .gameplay {
            isCButtonItemEditorPresented = false
        }
        gameTime.advance()
        if let fixedTimeOfDayOverride {
            gameTime.timeOfDay = fixedTimeOfDayOverride
        }
        if nextState == .gameplay {
            startTimeLoop()
        } else {
            stopTimeLoop()
            clearXRayTelemetry()
        }
        synchronizeMusicForCurrentContext()
        telemetryPublisher.publish("gameRuntime.state.\(nextState.rawValue)")
    }

    private func normalizedSlotIndex(_ index: Int) -> Int {
        min(max(0, index), saveContext.slots.count - 1)
    }

    private func applyGameplayControllerInput(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState,
        allowPrimaryAction: Bool
    ) {
        if isCButtonItemEditorPresented {
            return
        }
        handleGameplayItemButtons(
            currentInput: currentInput,
            previousInput: previousInput
        )

        if allowPrimaryAction, currentInput.aPressed, previousInput.aPressed == false {
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

    var isGameplayPresentationActive: Bool {
        messageContext.isPresenting || itemGetSequence?.isSuspendingGameplay == true
    }

    private func beginChestOpenSequence(_ request: TreasureChestOpenRequest) -> Bool {
        guard currentState == .gameplay else {
            return false
        }
        guard itemGetSequence == nil else {
            return false
        }
        guard inventoryState.hasOpenedTreasure(request.treasureFlag) == false else {
            return false
        }

        inventoryState.markTreasureOpened(request.treasureFlag)
        persistActiveSaveSlotState()
        itemGetSequence = ItemGetSequenceState(
            reward: request.reward,
            chestSize: request.chestSize,
            treasureFlag: request.treasureFlag,
            itemWorldPosition: itemGetWorldPosition()
        )
        playerState?.presentationMode = request.reward.playerPresentationMode
        playTransientMusicTrack(id: "open-treasure-chest")
        return true
    }

    private func grantActorReward(_ reward: ActorReward) {
        guard let scene = playState?.currentSceneIdentity else {
            return
        }

        inventoryState.apply(reward, in: scene)
        persistActiveSaveSlotState()
        synchronizeHUDStateWithInventory()
        if case .chest(.heartContainer) = reward {
            playTransientMusicTrack(id: "heart-get")
        }
    }
    private func markDungeonEventTriggered(_ key: DungeonEventFlagKey) {
        guard inventoryState.hasTriggeredDungeonEvent(key) == false else {
            return
        }

        inventoryState.markDungeonEventTriggered(key)
        persistActiveSaveSlotState()
    }
    private func advanceItemGetSequenceIfNeeded() {
        guard var itemGetSequence else {
            return
        }

        switch itemGetSequence.phase {
        case .raising:
            itemGetSequence.phaseFrameCount += 1
            itemGetSequence.itemWorldPosition = itemGetWorldPosition()
            if itemGetSequence.phaseFrameCount >= 24 {
                if itemGetSequence.rewardApplied == false {
                    inventoryState.apply(
                        itemGetSequence.reward,
                        in: itemGetSequence.treasureFlag.scene
                    )
                    persistActiveSaveSlotState()
                    itemGetSequence.rewardApplied = true
                    synchronizeHUDStateWithInventory()
                }
                itemGetSequence.phase = .displayingText
                itemGetSequence.phaseFrameCount = 0
                queueSoundEffect(.itemGet)
                playTransientMusicTrack(id: musicTrackID(for: itemGetSequence.reward))
            }
        case .displayingText:
            itemGetSequence.itemWorldPosition = itemGetWorldPosition()
        case .closing:
            itemGetSequence.phaseFrameCount += 1
            itemGetSequence.itemWorldPosition = itemGetWorldPosition()
            if itemGetSequence.phaseFrameCount >= 8 {
                self.itemGetSequence = nil
                playerState?.presentationMode = .normal
                return
            }
        }

        self.itemGetSequence = itemGetSequence
        if itemGetSequence.phase != .closing {
            playerState?.presentationMode = itemGetSequence.reward.playerPresentationMode
        }
    }

    private func handleItemGetPrimaryInput() -> Bool {
        guard var itemGetSequence else {
            return false
        }
        guard itemGetSequence.phase == .displayingText else {
            return true
        }

        itemGetSequence.phase = .closing
        itemGetSequence.phaseFrameCount = 0
        self.itemGetSequence = itemGetSequence
        return true
    }

    private func itemGetWorldPosition() -> Vec3f {
        let basePosition = playerState?.position.simd ?? .zero
        return Vec3f(basePosition + SIMD3<Float>(0, 58, 0))
    }

    func synchronizeHUDStateWithInventory() {
        let currentSceneIdentity = playState?.currentSceneIdentity ?? SceneIdentity(id: selectedSceneID, name: playState?.currentSceneName ?? loadedScene?.manifest.name ?? "Unknown")
        hudState.currentHealthUnits = inventoryState.currentHealthUnits
        hudState.maximumHealthUnits = inventoryState.maximumHealthUnits
        hudState.smallKeyCount = inventoryState.smallKeyCount(for: currentSceneIdentity)
        hudState.bButtonItem = inventoryContext.equipment.equippedSword == nil ? .none : .sword

        for button in GameplayCButton.allCases {
            if let item = inventoryState.cButtonLoadout[button] {
                hudState.cButtons[button] = GameplayHUDButtonState(
                    item: item.hudButtonItem,
                    ammoCount: inventoryState.ammoCount(for: item),
                    isEnabled: inventoryState.canUse(item)
                )
            } else {
                hudState.cButtons[button] = .empty
            }
        }
    }

    func persistActiveSaveSlotState(sceneName: String? = nil) {
        guard let playState else {
            return
        }

        let index = normalizedSlotIndex(playState.activeSaveSlot)
        guard saveContext.slots[index].hasSaveData else {
            return
        }

        var persistedInventoryContext = inventoryContext
        persistedInventoryContext.pauseMenu = PauseMenuState()
        persistedInventoryContext.gameplay.goldSkulltulaTokenCount = max(
            persistedInventoryContext.gameplay.goldSkulltulaTokenCount,
            goldSkulltulaFlags.count
        )

        let resolvedSceneName = sceneName ?? playState.currentSceneName
        let resolvedSceneID = playState.currentSceneID ?? loadedScene?.manifest.id ?? sceneID(for: resolvedSceneName)

        saveContext.slots[index] = SaveSlot(
            id: index,
            playerName: playState.playerName,
            locationName: resolvedSceneName,
            hearts: max(1, inventoryState.maximumHealthUnits / 2),
            hasSaveData: true,
            inventoryContext: persistedInventoryContext,
            runtimeState: SaveRuntimeState(
                currentMagic: hudState.currentMagic,
                maximumMagic: hudState.maximumMagic,
                rupees: hudState.rupees,
                globalEventFlags: globalEventFlags,
                sceneEventFlags: sceneEventFlags,
                spawnLocation: SaveSpawnLocation(
                    sceneID: resolvedSceneID,
                    sceneName: resolvedSceneName,
                    entranceIndex: playState.currentEntranceIndex,
                    spawnIndex: playState.currentSpawnIndex
                ),
                playTimeFrames: activePlayTimeFrames,
                deathCount: deathCount,
                goldSkulltulaFlags: goldSkulltulaFlags
            )
        )
    }

    private func flushSaveContextToDisk(
        telemetryEvent: String,
        successMessage: String? = nil,
        failurePrefix: String? = nil
    ) {
        guard let saveRepository else {
            return
        }

        do {
            try saveRepository.save(saveContext)
            if let successMessage {
                statusMessage = successMessage
            }
            telemetryPublisher.publish(telemetryEvent)
        } catch {
            if let failurePrefix {
                statusMessage = "\(failurePrefix): \(error.localizedDescription)"
            }
            telemetryPublisher.publish("\(telemetryEvent).failed")
        }
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
        refreshDirectorCommentary(forcePresentation: true)
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

    private func resolveDeveloperSceneID(
        selection: DeveloperSceneSelection?,
        availableScenes: [SceneTableEntry]
    ) throws -> Int {
        guard !availableScenes.isEmpty else {
            throw DeveloperSceneLaunchError.noAvailableScenes
        }

        switch selection {
        case .id(let id):
            guard availableScenes.contains(where: { $0.index == id }) else {
                throw DeveloperSceneLaunchError.unknownSceneID(id)
            }
            return id
        case .name(let name):
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let matchedScene = availableScenes.first(where: { entry in
                Self.sceneName(for: entry).localizedCaseInsensitiveCompare(normalizedName) == .orderedSame ||
                    entry.enumName.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame ||
                    entry.title?.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
            }) {
                return matchedScene.index
            }

            throw DeveloperSceneLaunchError.unknownSceneName(normalizedName)
        case nil:
            return
                availableScenes.first(where: { Self.sceneName(for: $0) == "spot04" })?.index ??
                availableScenes.first?.index ??
                0
        }
    }

    nonisolated private static func normalizedTimeOfDay(_ timeOfDay: Double) -> Double {
        let normalized = timeOfDay.truncatingRemainder(dividingBy: 24)
        return normalized >= 0 ? normalized : normalized + 24
    }

    private func activateSceneContentIfAvailable() {
        guard let playState else {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            clearXRayTelemetry()
            return
        }

        let resolvedSceneID = playState.currentSceneID ?? sceneID(for: playState.currentSceneName)
        guard let sceneID = resolvedSceneID else {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            clearXRayTelemetry()
            return
        }

        do {
            try loadScene(
                id: sceneID,
                entranceIndex: playState.currentEntranceIndex,
                spawnIndex: playState.currentSpawnIndex
            )
        } catch {
            actorContext = nil
            playerState = nil
            collisionSystem = nil
            statusMessage = "Gameplay scene content failed to load. Continuing with placeholder gameplay."
            clearXRayTelemetry()
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
        actorTable: [Int: ActorTableEntry],
        preferredSpawnIndex: Int?
    ) -> PlayerState {
        let preferredSceneSpawn = preferredSpawnIndex.flatMap { index in
            let spawns = scene.spawns?.spawns ?? scene.sceneHeader?.spawns ?? []
            return spawns.first(where: { $0.index == index })
        }
        let defaultSceneSpawn = resolvedSceneSpawn(
            in: scene,
            preferredSpawnIndex: nil
        )
        let fallbackPosition = defaultPlayerSpawn(
            in: scene,
            preferredSpawnPosition: (preferredSceneSpawn ?? defaultSceneSpawn).map { Vec3f($0.position).simd }
        )
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
        let rawPosition =
            preferredSceneSpawn.map { Vec3f($0.position).simd } ??
            playerSpawn.map { Vec3f($0.position).simd } ??
            defaultSceneSpawn.map { Vec3f($0.position).simd } ??
            fallbackPosition
        let probePosition = rawPosition + SIMD3<Float>(0, movementConfiguration.floorProbeHeight, 0)
        let floorHit = collisionSystem.findFloor(at: probePosition)
        let resolvedPosition = SIMD3<Float>(
            rawPosition.x,
            floorHit?.floorY ?? rawPosition.y,
            rawPosition.z
        )

        let facingRadians: Float
        if let preferredSceneSpawn {
            facingRadians = rawRotationToRadians(Float(preferredSceneSpawn.rotation.y))
        } else if let playerSpawn {
            facingRadians = rawRotationToRadians(Float(playerSpawn.rotation.y))
        } else if let defaultSceneSpawn {
            facingRadians = rawRotationToRadians(Float(defaultSceneSpawn.rotation.y))
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

    private func defaultPlayerSpawn(
        in scene: LoadedScene,
        preferredSpawnPosition: SIMD3<Float>?
    ) -> SIMD3<Float> {
        if let preferredSpawnPosition {
            return preferredSpawnPosition
        }

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

    private func resolvedSceneSpawn(
        in scene: LoadedScene,
        preferredSpawnIndex: Int?
    ) -> SceneSpawnPoint? {
        let spawns = scene.spawns?.spawns ?? scene.sceneHeader?.spawns ?? []
        guard spawns.isEmpty == false else {
            return nil
        }

        if let preferredSpawnIndex,
           let matchingSpawn = spawns.first(where: { $0.index == preferredSpawnIndex }) {
            return matchingSpawn
        }

        return spawns.first
    }

    private func sceneID(for sceneName: String) -> Int? {
        let normalizedName = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            return nil
        }

        let sceneEntries: [SceneTableEntry]
        if availableScenes.isEmpty {
            sceneEntries = (try? sceneLoader.loadSceneTableEntries()) ?? []
        } else {
            sceneEntries = availableScenes
        }

        return sceneEntries.first { entry in
            Self.sceneName(for: entry).localizedCaseInsensitiveCompare(normalizedName) == .orderedSame ||
                entry.enumName.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame ||
                entry.title?.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }?.index
    }

    private var activeTalkActor: (any TalkRequestingActor)? {
        resolveActiveTalkActor()?.actor
    }

    private func processSceneTransitionsIfNeeded() {
        guard
            currentState == .gameplay,
            messageContext.isPresenting == false,
            itemGetSequence == nil,
            let playerPosition = playerState?.position
        else {
            return
        }

        do {
            if let doorTriggerID = automaticDoorTriggerID(near: playerPosition.simd) {
                try activateDoorTransition(id: doorTriggerID)
                return
            }

            try evaluateLoadingZone(
                at: Vector3s(
                    x: Int16(playerPosition.x.rounded()),
                    y: Int16(playerPosition.y.rounded()),
                    z: Int16(playerPosition.z.rounded())
                )
            )
        } catch {
            telemetryPublisher.publish("gameRuntime.sceneTransitionFailed")
        }
    }

    private func automaticDoorTriggerID(near position: SIMD3<Float>) -> Int? {
        guard let sceneManager, let sceneHeader = loadedScene?.sceneHeader else {
            return nil
        }

        let activationDistanceSquared: Float = 90 * 90

        return sceneHeader.transitionTriggers.first { trigger in
            guard trigger.kind == .door, trigger.roomID == sceneManager.state.currentRoomID else {
                return false
            }

            let triggerPosition = SIMD3<Float>(
                Float(trigger.volume.minimum.x),
                Float(trigger.volume.minimum.y),
                Float(trigger.volume.minimum.z)
            )
            return simd_distance_squared(triggerPosition, position) <= activationDistanceSquared
        }?.id
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

    private func loadAudioTrackCatalogIfAvailable() {
        guard audioTrackCatalog == nil else {
            return
        }

        if let audioTrackCatalog = try? contentLoader.loadAudioTrackCatalog() {
            self.audioTrackCatalog = audioTrackCatalog
        }
    }

    private func resolveAudioTrack(id trackID: String) -> AudioTrackManifest? {
        loadAudioTrackCatalogIfAvailable()
        return audioTrackCatalog?.tracks.first(where: { $0.id == trackID })
    }

    private func resolveAudioTrack(preferredIDs: [String]) -> AudioTrackManifest? {
        for trackID in preferredIDs {
            if let track = resolveAudioTrack(id: trackID) {
                return track
            }
        }
        return nil
    }

    @discardableResult
    private func playMusicTrack(
        id trackID: String,
        crossfadeDuration: TimeInterval,
        announcesStatus: Bool
    ) -> TimeInterval? {
        guard let track = resolveAudioTrack(id: trackID) else {
            if announcesStatus {
                statusMessage = "Audio preview \(trackID) is unavailable."
            }
            return nil
        }

        let currentTrack = musicPlaybackState.currentTrack
        let shouldCrossfade = currentTrack != nil && currentTrack?.id != track.id && crossfadeDuration > 0

        let transientDuration: TimeInterval?
        do {
            transientDuration = try musicPlaybackController?.play(
                track: track,
                crossfadeDuration: shouldCrossfade ? crossfadeDuration : 0
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        errorMessage = nil
        if announcesStatus {
            statusMessage = "Previewing sample for \(track.title)."
        }

        if shouldCrossfade, let currentTrack {
            beginCrossfade(
                from: currentTrack,
                to: MusicTrackReference(track: track),
                duration: crossfadeDuration
            )
        } else {
            completeMusicTransition(to: MusicTrackReference(track: track), phase: .playing)
        }

        return transientDuration
    }

    private func synchronizeMusicForCurrentContext(
        crossfadeDuration: TimeInterval = 0
    ) {
        switch currentState {
        case .boot, .consoleLogo:
            if musicPlaybackState.currentTrack != nil {
                stopMusicTrack(announcesStatus: false)
            }
        case .titleScreen:
            if musicPlaybackState.currentTrack != nil {
                stopMusicTrack(announcesStatus: false)
            }
        case .fileSelect:
            if musicPlaybackState.currentTrack != nil {
                stopMusicTrack(announcesStatus: false)
            }
        case .gameplay:
            guard let track = preferredGameplayMusicTrack() else {
                if musicPlaybackState.currentTrack?.kind == .bgm {
                    stopMusicTrack(announcesStatus: false)
                }
                return
            }

            ensurePersistentMusic(
                preferredTrackIDs: [track.id],
                crossfadeDuration: crossfadeDuration
            )
        }
    }

    private func preferredGameplayMusicTrack() -> AudioTrackManifest? {
        loadAudioTrackCatalogIfAvailable()

        let sceneID = loadedScene?.manifest.id ?? playState?.currentSceneID
        let sceneName = loadedScene?.manifest.name ?? playState?.scene?.manifest.name ?? playState?.currentSceneName
        guard let audioTrackCatalog else {
            return nil
        }

        if let sceneID,
           let binding = audioTrackCatalog.sceneBindings.first(where: { $0.sceneID == sceneID }),
           let track = resolveAudioTrack(id: binding.trackID) {
            return track
        }

        if let sceneName {
            let normalizedSceneName = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let binding = audioTrackCatalog.sceneBindings.first(where: {
                $0.sceneName.localizedCaseInsensitiveCompare(normalizedSceneName) == .orderedSame
            }) {
                return resolveAudioTrack(id: binding.trackID)
            }
        }

        return nil
    }

    private func ensurePersistentMusic(
        preferredTrackIDs: [String],
        crossfadeDuration: TimeInterval
    ) {
        guard let track = resolveAudioTrack(preferredIDs: preferredTrackIDs) else {
            return
        }

        if musicPlaybackState.pendingTrack?.id == track.id {
            return
        }

        if musicPlaybackState.currentTrack?.id == track.id {
            if musicPlaybackState.phase == .paused {
                resumeMusicTrack(announcesStatus: false)
            }
            return
        }

        _ = playMusicTrack(
            id: track.id,
            crossfadeDuration: crossfadeDuration,
            announcesStatus: false
        )
    }

    private func playTransientMusicTrack(id trackID: String) {
        let duration = playMusicTrack(
            id: trackID,
            crossfadeDuration: 0,
            announcesStatus: false
        ) ?? fallbackTransientMusicDuration(for: trackID)
        guard let duration else {
            return
        }

        musicTransitionTask?.cancel()
        musicTransitionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.suspender(.seconds(duration))
            guard Task.isCancelled == false else {
                return
            }

            self.synchronizeMusicForCurrentContext(crossfadeDuration: 0.35)
        }
    }

    private func musicTrackID(for reward: TreasureChestReward) -> String {
        switch reward {
        case .heartContainer:
            return "heart-get"
        default:
            return "item-get"
        }
    }

    private func fallbackTransientMusicDuration(for trackID: String) -> TimeInterval? {
        switch trackID {
        case "open-treasure-chest":
            return 1.2
        case "item-get":
            return 2.2
        case "heart-get":
            return 3.0
        default:
            return nil
        }
    }

    private func beginCrossfade(
        from currentTrack: MusicTrackReference,
        to targetTrack: MusicTrackReference,
        duration: TimeInterval
    ) {
        musicTransitionTask?.cancel()
        musicPlaybackState = MusicPlaybackState(
            phase: .crossfading,
            currentTrack: currentTrack,
            pendingTrack: targetTrack
        )

        musicTransitionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.suspender(.seconds(duration))
            guard Task.isCancelled == false else {
                return
            }

            self.completeMusicTransition(to: targetTrack, phase: .playing)
        }
    }

    private func completeMusicTransition(
        to track: MusicTrackReference,
        phase: MusicPlaybackPhase
    ) {
        musicTransitionTask?.cancel()
        musicTransitionTask = nil
        musicPlaybackState = MusicPlaybackState(
            phase: phase,
            currentTrack: track,
            pendingTrack: nil
        )
    }

    private func synchronizeGameTime(with scene: LoadedScene?) {
        if let fixedTimeOfDayOverride {
            gameTime.timeOfDay = fixedTimeOfDayOverride
            return
        }

        guard let timeOfDay = timeSystem.initialTimeOfDay(for: scene?.environment) else {
            return
        }

        gameTime.timeOfDay = timeOfDay
    }

    private func startTimeLoop() {
        guard fixedTimeOfDayOverride == nil else {
            return
        }

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
