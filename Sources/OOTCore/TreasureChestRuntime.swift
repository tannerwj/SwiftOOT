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
    public var hasSlingshot: Bool
    public var goldSkulltulaTokenCount: Int
    public var dekuNutCount: Int
    public var dekuNutCapacity: Int
    public var dekuStickCount: Int
    public var dekuStickCapacity: Int
    public var currentHealthUnits: Int
    public var maximumHealthUnits: Int

    public init(
        dungeonStateByScene: [SceneIdentity: DungeonInventoryState] = [:],
        openedTreasureFlags: Set<TreasureFlagKey> = [],
        hasSlingshot: Bool = false,
        goldSkulltulaTokenCount: Int = 0,
        dekuNutCount: Int = 0,
        dekuNutCapacity: Int = 20,
        dekuStickCount: Int = 0,
        dekuStickCapacity: Int = 10,
        currentHealthUnits: Int = 6,
        maximumHealthUnits: Int = 6
    ) {
        self.dungeonStateByScene = dungeonStateByScene
        self.openedTreasureFlags = openedTreasureFlags
        self.hasSlingshot = hasSlingshot
        self.goldSkulltulaTokenCount = max(0, goldSkulltulaTokenCount)
        self.dekuNutCount = max(0, dekuNutCount)
        self.dekuNutCapacity = max(0, dekuNutCapacity)
        self.dekuStickCount = max(0, dekuStickCount)
        self.dekuStickCapacity = max(0, dekuStickCapacity)
        self.currentHealthUnits = max(0, currentHealthUnits)
        self.maximumHealthUnits = max(2, maximumHealthUnits)
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

    public func dungeonState(for scene: SceneIdentity) -> DungeonInventoryState {
        dungeonStateByScene[scene, default: DungeonInventoryState()]
    }

    public func smallKeyCount(for scene: SceneIdentity) -> Int {
        dungeonState(for: scene).smallKeyCount
    }

    public mutating func markTreasureOpened(_ key: TreasureFlagKey) {
        openedTreasureFlags.insert(key)
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
