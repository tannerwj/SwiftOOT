import Foundation
import OOTDataModel

public struct SceneIdentity: Sendable, Codable, Hashable, Equatable {
    public var id: Int?
    public var name: String

    public init(
        id: Int?,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

public struct TreasureFlagKey: Sendable, Codable, Hashable, Equatable {
    public var scene: SceneIdentity
    public var flag: Int

    public init(
        scene: SceneIdentity,
        flag: Int
    ) {
        self.scene = scene
        self.flag = flag
    }
}

public enum DungeonEventKind: String, Sendable, Codable, Hashable, Equatable {
    case switchPressed
    case enemyDefeated
    case webBurned
    case torchLit
    case blockMoved
    case doorOpened
}

public struct DungeonEventFlagKey: Sendable, Codable, Hashable, Equatable {
    public var scene: SceneIdentity
    public var kind: DungeonEventKind
    public var roomID: Int
    public var actorID: Int
    public var params: Int
    public var positionX: Int
    public var positionY: Int
    public var positionZ: Int

    public init(
        scene: SceneIdentity,
        kind: DungeonEventKind,
        roomID: Int,
        actorID: Int,
        params: Int,
        positionX: Int,
        positionY: Int,
        positionZ: Int
    ) {
        self.scene = scene
        self.kind = kind
        self.roomID = roomID
        self.actorID = actorID
        self.params = params
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
    }
}

public enum TreasureChestSize: String, Sendable, Codable, Equatable {
    case small
    case large
}

public enum PlayerPresentationMode: String, Sendable, Codable, Equatable {
    case normal
    case itemGetA
    case itemGetB
}

public struct DungeonInventoryState: Sendable, Codable, Equatable {
    public var hasMap: Bool
    public var hasCompass: Bool
    public var hasBossKey: Bool
    public var smallKeyCount: Int

    public init(
        hasMap: Bool = false,
        hasCompass: Bool = false,
        hasBossKey: Bool = false,
        smallKeyCount: Int = 0
    ) {
        self.hasMap = hasMap
        self.hasCompass = hasCompass
        self.hasBossKey = hasBossKey
        self.smallKeyCount = max(0, smallKeyCount)
    }
}

public enum TreasureChestReward: Sendable, Codable, Equatable {
    case dungeonMap
    case compass
    case bossKey
    case slingshot
    case heartContainer
    case smallKey
    case dekuNuts(Int)
    case dekuSticks(Int)

    public init?(getItemID: Int) {
        switch getItemID {
        case 0x05:
            self = .slingshot
        case 0x02, 0x63:
            self = .dekuNuts(5)
        case 0x64:
            self = .dekuNuts(10)
        case 0x07:
            self = .dekuSticks(1)
        case 0x61:
            self = .dekuSticks(5)
        case 0x62:
            self = .dekuSticks(10)
        case 0x3D, 0x4F:
            self = .heartContainer
        case 0x3F:
            self = .bossKey
        case 0x40:
            self = .compass
        case 0x41:
            self = .dungeonMap
        case 0x42:
            self = .smallKey
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .dungeonMap:
            return "Dungeon Map"
        case .compass:
            return "Compass"
        case .bossKey:
            return "Boss Key"
        case .slingshot:
            return "Fairy Slingshot"
        case .heartContainer:
            return "Heart Container"
        case .smallKey:
            return "Small Key"
        case .dekuNuts(let amount):
            return "Deku Nuts x\(amount)"
        case .dekuSticks(let amount):
            return "Deku Sticks x\(amount)"
        }
    }

    public var description: String {
        switch self {
        case .dungeonMap:
            return "This map reveals the layout of the current dungeon."
        case .compass:
            return "This compass reveals treasure chests and the boss location."
        case .bossKey:
            return "This key opens the boss door in the current dungeon."
        case .slingshot:
            return "You can fire Deku Seeds with this child-sized ranged weapon."
        case .heartContainer:
            return "Your life energy increases by one heart container."
        case .smallKey:
            return "A small key for the current dungeon."
        case .dekuNuts(let amount):
            return "A bundle of \(amount) Deku Nuts for stunning nearby enemies."
        case .dekuSticks(let amount):
            return "A bundle of \(amount) Deku Sticks for torches and melee attacks."
        }
    }

    public var iconName: String {
        switch self {
        case .dungeonMap:
            return "map.fill"
        case .compass:
            return "location.north.line.fill"
        case .bossKey:
            return "key.fill"
        case .slingshot:
            return "target"
        case .heartContainer:
            return "heart.fill"
        case .smallKey:
            return "key.horizontal.fill"
        case .dekuNuts:
            return "leaf.fill"
        case .dekuSticks:
            return "sparkles"
        }
    }

    public var messageVariant: MessageBoxVariant {
        switch self {
        case .slingshot, .bossKey, .heartContainer:
            return .blue
        case .dungeonMap, .compass, .smallKey:
            return .white
        case .dekuNuts, .dekuSticks:
            return .red
        }
    }

    public var messageIcon: MessageIcon {
        switch self {
        case .heartContainer:
            return MessageIcon(rawValue: "heart")
        case .dungeonMap, .compass:
            return MessageIcon(rawValue: "fairy")
        case .bossKey, .smallKey:
            return MessageIcon(rawValue: "warning")
        case .slingshot, .dekuNuts, .dekuSticks:
            return MessageIcon(rawValue: "note")
        }
    }

    public var playerPresentationMode: PlayerPresentationMode {
        switch self {
        case .slingshot, .heartContainer, .bossKey:
            return .itemGetB
        case .dungeonMap, .compass, .smallKey, .dekuNuts, .dekuSticks:
            return .itemGetA
        }
    }
}

public enum ActorReward: Sendable, Codable, Equatable {
    case chest(TreasureChestReward)
    case goldSkulltulaToken
}

public struct TreasureChestParams: Sendable, Equatable {
    public var type: Int
    public var getItemID: Int
    public var treasureFlag: Int

    public init(rawValue: UInt16) {
        type = Int((rawValue >> 12) & 0xF)
        getItemID = Int((rawValue >> 5) & 0x7F)
        treasureFlag = Int(rawValue & 0x1F)
    }

    public var chestSize: TreasureChestSize {
        switch type {
        case 5, 6, 7, 8:
            return .small
        default:
            return .large
        }
    }
}

public struct GameplayInventoryState: Sendable, Codable, Equatable {
    public var dungeonStateByScene: [SceneIdentity: DungeonInventoryState]
    public var openedTreasureFlags: Set<TreasureFlagKey>
    public var triggeredDungeonEventFlags: Set<DungeonEventFlagKey>
    public var visitedSceneIDs: Set<Int>
    public var hasSlingshot: Bool
    public var slingshotAmmo: Int
    public var slingshotCapacity: Int
    public var hasBombBag: Bool
    public var bombCount: Int
    public var bombCapacity: Int
    public var hasBoomerang: Bool
    public var goldSkulltulaTokenCount: Int
    public var dekuNutCount: Int
    public var dekuNutCapacity: Int
    public var dekuStickCount: Int
    public var dekuStickCapacity: Int
    public var cButtonLoadout: GameplayCButtonLoadout
    public var currentHealthUnits: Int
    public var maximumHealthUnits: Int

    public init(
        dungeonStateByScene: [SceneIdentity: DungeonInventoryState] = [:],
        openedTreasureFlags: Set<TreasureFlagKey> = [],
        triggeredDungeonEventFlags: Set<DungeonEventFlagKey> = [],
        visitedSceneIDs: Set<Int> = [],
        hasSlingshot: Bool = false,
        slingshotAmmo: Int = 0,
        slingshotCapacity: Int = 30,
        hasBombBag: Bool = false,
        bombCount: Int = 0,
        bombCapacity: Int = 20,
        hasBoomerang: Bool = false,
        goldSkulltulaTokenCount: Int = 0,
        dekuNutCount: Int = 0,
        dekuNutCapacity: Int = 20,
        dekuStickCount: Int = 0,
        dekuStickCapacity: Int = 10,
        cButtonLoadout: GameplayCButtonLoadout = GameplayCButtonLoadout(),
        currentHealthUnits: Int = 6,
        maximumHealthUnits: Int = 6
    ) {
        self.dungeonStateByScene = dungeonStateByScene
        self.openedTreasureFlags = openedTreasureFlags
        self.triggeredDungeonEventFlags = triggeredDungeonEventFlags
        self.visitedSceneIDs = visitedSceneIDs
        self.hasSlingshot = hasSlingshot
        self.slingshotAmmo = max(0, slingshotAmmo)
        self.slingshotCapacity = max(0, slingshotCapacity)
        self.hasBombBag = hasBombBag
        self.bombCount = max(0, bombCount)
        self.bombCapacity = max(0, bombCapacity)
        self.hasBoomerang = hasBoomerang
        self.goldSkulltulaTokenCount = max(0, goldSkulltulaTokenCount)
        self.dekuNutCount = max(0, dekuNutCount)
        self.dekuNutCapacity = max(0, dekuNutCapacity)
        self.dekuStickCount = max(0, dekuStickCount)
        self.dekuStickCapacity = max(0, dekuStickCapacity)
        self.cButtonLoadout = cButtonLoadout
        self.currentHealthUnits = max(0, currentHealthUnits)
        self.maximumHealthUnits = max(2, maximumHealthUnits)
        normalizeItemState()
    }

    public static func starter(hearts: Int) -> Self {
        let healthUnits = max(2, hearts * 2)
        return GameplayInventoryState(
            currentHealthUnits: healthUnits,
            maximumHealthUnits: healthUnits
        )
    }

    public func hasOpenedTreasure(_ key: TreasureFlagKey) -> Bool {
        openedTreasureFlags.contains(key)
    }

    public func hasTriggeredDungeonEvent(_ key: DungeonEventFlagKey) -> Bool {
        triggeredDungeonEventFlags.contains(key)
    }

    public func hasVisitedScene(_ sceneID: Int?) -> Bool {
        guard let sceneID else {
            return false
        }
        return visitedSceneIDs.contains(sceneID)
    }

    public func dungeonState(for scene: SceneIdentity) -> DungeonInventoryState {
        dungeonStateByScene[scene, default: DungeonInventoryState()]
    }

    public func smallKeyCount(for scene: SceneIdentity) -> Int {
        dungeonState(for: scene).smallKeyCount
    }

    public mutating func markTreasureOpened(_ key: TreasureFlagKey) {
        openedTreasureFlags.insert(key)
    }

    public mutating func markDungeonEventTriggered(_ key: DungeonEventFlagKey) {
        triggeredDungeonEventFlags.insert(key)
    }

    public mutating func markSceneVisited(_ sceneID: Int?) {
        guard let sceneID else {
            return
        }
        visitedSceneIDs.insert(sceneID)
    }

    public mutating func apply(
        _ reward: TreasureChestReward,
        in scene: SceneIdentity
    ) {
        var dungeonState = dungeonStateByScene[scene, default: DungeonInventoryState()]

        switch reward {
        case .dungeonMap:
            dungeonState.hasMap = true
        case .compass:
            dungeonState.hasCompass = true
        case .bossKey:
            dungeonState.hasBossKey = true
        case .slingshot:
            hasSlingshot = true
            slingshotAmmo = max(slingshotAmmo, 30)
        case .heartContainer:
            maximumHealthUnits += 2
            currentHealthUnits = maximumHealthUnits
        case .smallKey:
            dungeonState.smallKeyCount += 1
        case .dekuNuts(let amount):
            dekuNutCount = min(dekuNutCapacity, dekuNutCount + amount)
        case .dekuSticks(let amount):
            dekuStickCount = min(dekuStickCapacity, dekuStickCount + amount)
        }

        dungeonStateByScene[scene] = dungeonState
        normalizeItemState()
    }
    public mutating func apply(
        _ reward: ActorReward,
        in scene: SceneIdentity
    ) {
        switch reward {
        case .chest(let chestReward):
            apply(chestReward, in: scene)
        case .goldSkulltulaToken:
            goldSkulltulaTokenCount += 1
        }
        normalizeItemState()
    }

    public func owns(_ item: GameplayUsableItem) -> Bool {
        switch item {
        case .slingshot:
            return hasSlingshot
        case .bombs:
            return hasBombBag
        case .boomerang:
            return hasBoomerang
        case .dekuStick:
            return dekuStickCount > 0
        case .dekuNut:
            return dekuNutCount > 0
        case .ocarina, .bottle:
            return false
        }
    }

    public func canUse(_ item: GameplayUsableItem) -> Bool {
        switch item {
        case .slingshot:
            return hasSlingshot && slingshotAmmo > 0
        case .bombs:
            return hasBombBag && bombCount > 0
        case .boomerang:
            return hasBoomerang
        case .dekuStick:
            return dekuStickCount > 0
        case .dekuNut:
            return dekuNutCount > 0
        case .ocarina, .bottle:
            return false
        }
    }

    public func ammoCount(for item: GameplayUsableItem) -> Int? {
        switch item {
        case .slingshot:
            return slingshotAmmo
        case .bombs:
            return bombCount
        case .boomerang:
            return nil
        case .dekuStick:
            return dekuStickCount
        case .dekuNut:
            return dekuNutCount
        case .ocarina, .bottle:
            return nil
        }
    }

    public var ownedChildAssignableItems: [GameplayUsableItem] {
        GameplayUsableItem.childAssignableItems.filter(owns)
    }

    public mutating func assign(_ item: GameplayUsableItem?, to button: GameplayCButton) {
        if let item {
            guard owns(item) else {
                normalizeItemState()
                return
            }

            for otherButton in GameplayCButton.allCases
            where otherButton != button && cButtonLoadout[otherButton] == item {
                cButtonLoadout[otherButton] = nil
            }
        }

        cButtonLoadout[button] = item
        normalizeItemState()
    }

    @discardableResult
    public mutating func consume(_ item: GameplayUsableItem, amount: Int = 1) -> Bool {
        let resolvedAmount = max(1, amount)
        guard canUse(item) else {
            return false
        }

        switch item {
        case .slingshot:
            slingshotAmmo = max(0, slingshotAmmo - resolvedAmount)
        case .bombs:
            bombCount = max(0, bombCount - resolvedAmount)
        case .boomerang:
            break
        case .dekuStick:
            dekuStickCount = max(0, dekuStickCount - resolvedAmount)
        case .dekuNut:
            dekuNutCount = max(0, dekuNutCount - resolvedAmount)
        case .ocarina, .bottle:
            return false
        }

        normalizeItemState()
        return true
    }

    public mutating func normalizeItemState() {
        slingshotAmmo = min(max(0, slingshotAmmo), slingshotCapacity)
        bombCount = min(max(0, bombCount), bombCapacity)
        dekuNutCount = min(max(0, dekuNutCount), dekuNutCapacity)
        dekuStickCount = min(max(0, dekuStickCount), dekuStickCapacity)

        for button in GameplayCButton.allCases {
            if let item = cButtonLoadout[button], owns(item) == false {
                cButtonLoadout[button] = nil
            }
        }

        var assignedItems = Set(GameplayCButton.allCases.compactMap { cButtonLoadout[$0] })
        for button in GameplayCButton.allCases where cButtonLoadout[button] == nil {
            guard let nextItem = ownedChildAssignableItems.first(where: { assignedItems.contains($0) == false }) else {
                continue
            }

            cButtonLoadout[button] = nextItem
            assignedItems.insert(nextItem)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case dungeonStateByScene
        case openedTreasureFlags
        case triggeredDungeonEventFlags
        case visitedSceneIDs
        case hasSlingshot
        case slingshotAmmo
        case slingshotCapacity
        case hasBombBag
        case bombCount
        case bombCapacity
        case hasBoomerang
        case goldSkulltulaTokenCount
        case dekuNutCount
        case dekuNutCapacity
        case dekuStickCount
        case dekuStickCapacity
        case cButtonLoadout
        case currentHealthUnits
        case maximumHealthUnits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dungeonStateByScene = try container.decodeIfPresent(
            [SceneIdentity: DungeonInventoryState].self,
            forKey: .dungeonStateByScene
        ) ?? [:]
        openedTreasureFlags = try container.decodeIfPresent(
            Set<TreasureFlagKey>.self,
            forKey: .openedTreasureFlags
        ) ?? []
        triggeredDungeonEventFlags = try container.decodeIfPresent(
            Set<DungeonEventFlagKey>.self,
            forKey: .triggeredDungeonEventFlags
        ) ?? []
        visitedSceneIDs = try container.decodeIfPresent(
            Set<Int>.self,
            forKey: .visitedSceneIDs
        ) ?? []
        hasSlingshot = try container.decodeIfPresent(Bool.self, forKey: .hasSlingshot) ?? false
        slingshotAmmo = max(0, try container.decodeIfPresent(Int.self, forKey: .slingshotAmmo) ?? 0)
        slingshotCapacity = max(0, try container.decodeIfPresent(Int.self, forKey: .slingshotCapacity) ?? 30)
        hasBombBag = try container.decodeIfPresent(Bool.self, forKey: .hasBombBag) ?? false
        bombCount = max(0, try container.decodeIfPresent(Int.self, forKey: .bombCount) ?? 0)
        bombCapacity = max(0, try container.decodeIfPresent(Int.self, forKey: .bombCapacity) ?? 20)
        hasBoomerang = try container.decodeIfPresent(Bool.self, forKey: .hasBoomerang) ?? false
        goldSkulltulaTokenCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .goldSkulltulaTokenCount) ?? 0
        )
        dekuNutCount = max(0, try container.decodeIfPresent(Int.self, forKey: .dekuNutCount) ?? 0)
        dekuNutCapacity = max(0, try container.decodeIfPresent(Int.self, forKey: .dekuNutCapacity) ?? 20)
        dekuStickCount = max(0, try container.decodeIfPresent(Int.self, forKey: .dekuStickCount) ?? 0)
        dekuStickCapacity = max(0, try container.decodeIfPresent(Int.self, forKey: .dekuStickCapacity) ?? 10)
        cButtonLoadout = try container.decodeIfPresent(GameplayCButtonLoadout.self, forKey: .cButtonLoadout) ?? GameplayCButtonLoadout()
        currentHealthUnits = max(0, try container.decodeIfPresent(Int.self, forKey: .currentHealthUnits) ?? 6)
        maximumHealthUnits = max(2, try container.decodeIfPresent(Int.self, forKey: .maximumHealthUnits) ?? 6)
        normalizeItemState()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dungeonStateByScene, forKey: .dungeonStateByScene)
        try container.encode(openedTreasureFlags, forKey: .openedTreasureFlags)
        try container.encode(triggeredDungeonEventFlags, forKey: .triggeredDungeonEventFlags)
        try container.encode(visitedSceneIDs, forKey: .visitedSceneIDs)
        try container.encode(hasSlingshot, forKey: .hasSlingshot)
        try container.encode(slingshotAmmo, forKey: .slingshotAmmo)
        try container.encode(slingshotCapacity, forKey: .slingshotCapacity)
        try container.encode(hasBombBag, forKey: .hasBombBag)
        try container.encode(bombCount, forKey: .bombCount)
        try container.encode(bombCapacity, forKey: .bombCapacity)
        try container.encode(hasBoomerang, forKey: .hasBoomerang)
        try container.encode(goldSkulltulaTokenCount, forKey: .goldSkulltulaTokenCount)
        try container.encode(dekuNutCount, forKey: .dekuNutCount)
        try container.encode(dekuNutCapacity, forKey: .dekuNutCapacity)
        try container.encode(dekuStickCount, forKey: .dekuStickCount)
        try container.encode(dekuStickCapacity, forKey: .dekuStickCapacity)
        try container.encode(cButtonLoadout, forKey: .cButtonLoadout)
        try container.encode(currentHealthUnits, forKey: .currentHealthUnits)
        try container.encode(maximumHealthUnits, forKey: .maximumHealthUnits)
    }
}

public struct TreasureChestOpenRequest: Sendable, Equatable {
    public var chestSize: TreasureChestSize
    public var reward: TreasureChestReward
    public var treasureFlag: TreasureFlagKey

    public init(
        chestSize: TreasureChestSize,
        reward: TreasureChestReward,
        treasureFlag: TreasureFlagKey
    ) {
        self.chestSize = chestSize
        self.reward = reward
        self.treasureFlag = treasureFlag
    }
}

public enum ItemGetSequencePhase: String, Sendable, Equatable {
    case raising
    case displayingText
    case closing
}

public struct ItemGetSequenceState: Sendable, Equatable {
    public var reward: TreasureChestReward
    public var chestSize: TreasureChestSize
    public var treasureFlag: TreasureFlagKey
    public var phase: ItemGetSequencePhase
    public var phaseFrameCount: Int
    public var rewardApplied: Bool
    public var itemWorldPosition: Vec3f

    public init(
        reward: TreasureChestReward,
        chestSize: TreasureChestSize,
        treasureFlag: TreasureFlagKey,
        phase: ItemGetSequencePhase = .raising,
        phaseFrameCount: Int = 0,
        rewardApplied: Bool = false,
        itemWorldPosition: Vec3f
    ) {
        self.reward = reward
        self.chestSize = chestSize
        self.treasureFlag = treasureFlag
        self.phase = phase
        self.phaseFrameCount = phaseFrameCount
        self.rewardApplied = rewardApplied
        self.itemWorldPosition = itemWorldPosition
    }

    public var isSuspendingGameplay: Bool {
        true
    }

    public var messagePresentation: MessagePresentation {
        MessagePresentation(
            messageID: -treasureFlag.flag - 1,
            variant: reward.messageVariant,
            phase: .waitingForAdvance,
            textRuns: [
                MessageTextRun(text: "\(reward.title)\n", color: .yellow),
                MessageTextRun(text: reward.description, color: .white),
            ],
            icon: reward.messageIcon
        )
    }
}

public struct ItemGetOverlayState: Sendable, Equatable {
    public var title: String
    public var description: String
    public var iconName: String
    public var phase: ItemGetSequencePhase

    public init(
        title: String,
        description: String,
        iconName: String,
        phase: ItemGetSequencePhase
    ) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.phase = phase
    }
}
