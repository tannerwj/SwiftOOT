import Foundation

public enum PauseMenuSubscreen: String, Codable, Sendable, Equatable, CaseIterable {
    case items
    case equipment
    case questStatus
    case map

    public var title: String {
        switch self {
        case .items:
            return "Items"
        case .equipment:
            return "Equipment"
        case .questStatus:
            return "Quest Status"
        case .map:
            return "Map"
        }
    }
}

public struct PauseMenuCursor: Codable, Sendable, Equatable {
    public var row: Int
    public var column: Int

    public init(
        row: Int = 0,
        column: Int = 0
    ) {
        self.row = max(0, row)
        self.column = max(0, column)
    }
}

public struct PauseMenuState: Codable, Sendable, Equatable {
    public var isPresented: Bool
    public var activeSubscreen: PauseMenuSubscreen
    public var itemCursor: PauseMenuCursor
    public var equipmentCursor: PauseMenuCursor

    public init(
        isPresented: Bool = false,
        activeSubscreen: PauseMenuSubscreen = .items,
        itemCursor: PauseMenuCursor = PauseMenuCursor(),
        equipmentCursor: PauseMenuCursor = PauseMenuCursor()
    ) {
        self.isPresented = isPresented
        self.activeSubscreen = activeSubscreen
        self.itemCursor = itemCursor
        self.equipmentCursor = equipmentCursor
    }
}

public enum PlayerSword: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case masterSword
    case biggoronSword

    public var title: String {
        switch self {
        case .masterSword:
            return "Master Sword"
        case .biggoronSword:
            return "Biggoron Sword"
        }
    }
}

public enum PlayerShield: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case hylianShield
    case mirrorShield

    public var title: String {
        switch self {
        case .hylianShield:
            return "Hylian Shield"
        case .mirrorShield:
            return "Mirror Shield"
        }
    }
}

public enum PlayerTunic: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case kokiri
    case goron
    case zora

    public var title: String {
        switch self {
        case .kokiri:
            return "Kokiri Tunic"
        case .goron:
            return "Goron Tunic"
        case .zora:
            return "Zora Tunic"
        }
    }
}

public enum PlayerBoots: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case kokiri
    case iron
    case hover

    public var title: String {
        switch self {
        case .kokiri:
            return "Kokiri Boots"
        case .iron:
            return "Iron Boots"
        case .hover:
            return "Hover Boots"
        }
    }
}

public struct EquipmentCollection: Codable, Sendable, Equatable {
    public var ownedSwords: Set<PlayerSword>
    public var equippedSword: PlayerSword?
    public var ownedShields: Set<PlayerShield>
    public var equippedShield: PlayerShield?
    public var ownedTunics: Set<PlayerTunic>
    public var equippedTunic: PlayerTunic
    public var ownedBoots: Set<PlayerBoots>
    public var equippedBoots: PlayerBoots

    public init(
        ownedSwords: Set<PlayerSword> = [.masterSword],
        equippedSword: PlayerSword? = .masterSword,
        ownedShields: Set<PlayerShield> = [.hylianShield],
        equippedShield: PlayerShield? = .hylianShield,
        ownedTunics: Set<PlayerTunic> = [.kokiri],
        equippedTunic: PlayerTunic = .kokiri,
        ownedBoots: Set<PlayerBoots> = [.kokiri],
        equippedBoots: PlayerBoots = .kokiri
    ) {
        self.ownedSwords = ownedSwords
        self.equippedSword = equippedSword.flatMap { ownedSwords.contains($0) ? $0 : nil }
        self.ownedShields = ownedShields
        self.equippedShield = equippedShield.flatMap { ownedShields.contains($0) ? $0 : nil }
        self.ownedTunics = ownedTunics.isEmpty ? [.kokiri] : ownedTunics
        self.equippedTunic = self.ownedTunics.contains(equippedTunic) ? equippedTunic : .kokiri
        self.ownedBoots = ownedBoots.isEmpty ? [.kokiri] : ownedBoots
        self.equippedBoots = self.ownedBoots.contains(equippedBoots) ? equippedBoots : .kokiri
    }

    public static let starter = EquipmentCollection()

    public mutating func equip(_ sword: PlayerSword?) {
        guard sword == nil || ownedSwords.contains(sword!) else {
            return
        }
        equippedSword = sword
    }

    public mutating func equip(_ shield: PlayerShield?) {
        guard shield == nil || ownedShields.contains(shield!) else {
            return
        }
        equippedShield = shield
    }

    public mutating func equip(_ tunic: PlayerTunic) {
        guard ownedTunics.contains(tunic) else {
            return
        }
        equippedTunic = tunic
    }

    public mutating func equip(_ boots: PlayerBoots) {
        guard ownedBoots.contains(boots) else {
            return
        }
        equippedBoots = boots
    }
}

public enum QuestMedallion: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case forest
    case fire
    case water
    case spirit
    case shadow
    case light

    public var title: String { rawValue.capitalized }
}

public enum SpiritualStone: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case kokiriEmerald
    case goronRuby
    case zoraSapphire

    public var title: String {
        switch self {
        case .kokiriEmerald:
            return "Kokiri Emerald"
        case .goronRuby:
            return "Goron Ruby"
        case .zoraSapphire:
            return "Zora Sapphire"
        }
    }
}

public enum QuestSong: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case zeldasLullaby
    case eponasSong
    case sariasSong
    case sunsSong
    case songOfTime
    case songOfStorms
    case minuetOfForest
    case boleroOfFire
    case serenadeOfWater
    case requiemOfSpirit
    case nocturneOfShadow
    case preludeOfLight

    public var title: String {
        switch self {
        case .zeldasLullaby:
            return "Zelda's Lullaby"
        case .eponasSong:
            return "Epona's Song"
        case .sariasSong:
            return "Saria's Song"
        case .sunsSong:
            return "Sun's Song"
        case .songOfTime:
            return "Song of Time"
        case .songOfStorms:
            return "Song of Storms"
        case .minuetOfForest:
            return "Minuet of Forest"
        case .boleroOfFire:
            return "Bolero of Fire"
        case .serenadeOfWater:
            return "Serenade of Water"
        case .requiemOfSpirit:
            return "Requiem of Spirit"
        case .nocturneOfShadow:
            return "Nocturne of Shadow"
        case .preludeOfLight:
            return "Prelude of Light"
        }
    }
}

public struct QuestStatus: Codable, Sendable, Equatable {
    public var medallions: Set<QuestMedallion>
    public var stones: Set<SpiritualStone>
    public var songs: Set<QuestSong>
    public var heartPieceCount: Int

    public init(
        medallions: Set<QuestMedallion> = [],
        stones: Set<SpiritualStone> = [],
        songs: Set<QuestSong> = [],
        heartPieceCount: Int = 0
    ) {
        self.medallions = medallions
        self.stones = stones
        self.songs = songs
        self.heartPieceCount = max(0, heartPieceCount)
    }
}

public enum InventoryMenuItem: String, Codable, Sendable, Equatable, CaseIterable {
    case dekuStick
    case dekuNut
    case bombs
    case bow
    case fireArrow
    case dinsFire
    case slingshot
    case ocarina
    case bombchu
    case hookshot
    case iceArrow
    case faroresWind
    case boomerang
    case lensOfTruth
    case magicBeans
    case hammer
    case lightArrow
    case nayrusLove
    case bottle
    case letter
    case tradeChild
    case tradeAdult
    case dungeonMap
    case compass

    public static let gridColumnCount = 6
    public static let gridRowCount = 4

    public var title: String {
        switch self {
        case .dekuStick:
            return "Deku Stick"
        case .dekuNut:
            return "Deku Nut"
        case .bombs:
            return "Bombs"
        case .bow:
            return "Bow"
        case .fireArrow:
            return "Fire Arrow"
        case .dinsFire:
            return "Din's Fire"
        case .slingshot:
            return "Slingshot"
        case .ocarina:
            return "Ocarina"
        case .bombchu:
            return "Bombchu"
        case .hookshot:
            return "Hookshot"
        case .iceArrow:
            return "Ice Arrow"
        case .faroresWind:
            return "Farore's Wind"
        case .boomerang:
            return "Boomerang"
        case .lensOfTruth:
            return "Lens of Truth"
        case .magicBeans:
            return "Magic Beans"
        case .hammer:
            return "Hammer"
        case .lightArrow:
            return "Light Arrow"
        case .nayrusLove:
            return "Nayru's Love"
        case .bottle:
            return "Bottle"
        case .letter:
            return "Letter"
        case .tradeChild:
            return "Child Trade"
        case .tradeAdult:
            return "Adult Trade"
        case .dungeonMap:
            return "Dungeon Map"
        case .compass:
            return "Compass"
        }
    }

    public var iconName: String {
        switch self {
        case .dekuStick:
            return "sparkles"
        case .dekuNut:
            return "leaf.fill"
        case .bombs, .bombchu:
            return "flame.fill"
        case .bow, .slingshot:
            return "target"
        case .fireArrow, .dinsFire:
            return "flame"
        case .ocarina:
            return "music.note"
        case .hookshot:
            return "link"
        case .iceArrow:
            return "snowflake"
        case .faroresWind:
            return "wind"
        case .boomerang:
            return "arrow.counterclockwise"
        case .lensOfTruth:
            return "eye.fill"
        case .magicBeans:
            return "leaf"
        case .hammer:
            return "hammer.fill"
        case .lightArrow:
            return "sparkle"
        case .nayrusLove:
            return "shield.lefthalf.filled"
        case .bottle:
            return "takeoutbag.and.cup.and.straw.fill"
        case .letter:
            return "envelope.fill"
        case .tradeChild, .tradeAdult:
            return "shippingbox.fill"
        case .dungeonMap:
            return "map.fill"
        case .compass:
            return "location.north.line.fill"
        }
    }

    public var assignableItem: GameplayUsableItem? {
        switch self {
        case .dekuStick:
            return .dekuStick
        case .dekuNut:
            return .dekuNut
        case .bombs:
            return .bombs
        case .slingshot:
            return .slingshot
        case .ocarina:
            return .ocarina
        case .boomerang:
            return .boomerang
        case .bottle:
            return .bottle
        case .bow,
             .fireArrow,
             .dinsFire,
             .bombchu,
             .hookshot,
             .iceArrow,
             .faroresWind,
             .lensOfTruth,
             .magicBeans,
             .hammer,
             .lightArrow,
             .nayrusLove,
             .letter,
             .tradeChild,
             .tradeAdult,
             .dungeonMap,
             .compass:
            return nil
        }
    }

    public static func at(
        row: Int,
        column: Int
    ) -> InventoryMenuItem? {
        guard
            row >= 0,
            row < gridRowCount,
            column >= 0,
            column < gridColumnCount
        else {
            return nil
        }

        return allCases[(row * gridColumnCount) + column]
    }
}

public struct InventoryContext: Codable, Sendable, Equatable {
    public var gameplay: GameplayInventoryState
    public var equipment: EquipmentCollection
    public var questStatus: QuestStatus
    public var pauseMenu: PauseMenuState

    public init(
        gameplay: GameplayInventoryState = .starter(hearts: 3),
        equipment: EquipmentCollection = .starter,
        questStatus: QuestStatus = QuestStatus(),
        pauseMenu: PauseMenuState = PauseMenuState()
    ) {
        self.gameplay = gameplay
        self.equipment = equipment
        self.questStatus = questStatus
        self.pauseMenu = pauseMenu
    }

    public static func starter(hearts: Int) -> Self {
        InventoryContext(gameplay: .starter(hearts: hearts))
    }

    public func owns(_ menuItem: InventoryMenuItem) -> Bool {
        if let assignableItem = menuItem.assignableItem {
            return gameplay.owns(assignableItem)
        }

        switch menuItem {
        case .dungeonMap:
            return gameplay.dungeonStateByScene.values.contains(where: \.hasMap)
        case .compass:
            return gameplay.dungeonStateByScene.values.contains(where: \.hasCompass)
        case .bow,
             .fireArrow,
             .dinsFire,
             .bombchu,
             .hookshot,
             .iceArrow,
             .faroresWind,
             .lensOfTruth,
             .magicBeans,
             .hammer,
             .lightArrow,
             .nayrusLove,
             .letter,
             .tradeChild,
             .tradeAdult:
            return false
        case .dekuStick,
             .dekuNut,
             .bombs,
             .slingshot,
             .ocarina,
             .boomerang,
             .bottle:
            return false
        }
    }

    public func itemCountLabel(for menuItem: InventoryMenuItem) -> String? {
        guard let assignableItem = menuItem.assignableItem else {
            return nil
        }

        return gameplay.ammoCount(for: assignableItem).map(String.init)
    }
}
