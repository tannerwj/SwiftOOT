import Foundation
import OOTContent
import OOTDataModel
import OOTTelemetry

public struct Vec3f: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ vector: Vector3s) {
        self.init(
            x: Float(vector.x),
            y: Float(vector.y),
            z: Float(vector.z)
        )
    }
}

public typealias Vec3s = Vector3s

public enum ActorCategory: UInt16, CaseIterable, Sendable {
    case switchActor = 0
    case bg = 1
    case player = 2
    case bomb = 3
    case npc = 4
    case enemy = 5
    case prop = 6
    case item = 7
    case misc = 8
    case boss = 9
    case door = 10
    case chest = 11

    public static var updatePriorityOrder: [ActorCategory] {
        allCases.sorted { $0.rawValue < $1.rawValue }
    }
}

public enum ActorDrawPass: String, CaseIterable, Codable, Sendable, Equatable {
    case opaque
    case translucent
}

@MainActor
public protocol Actor: AnyObject {
    var profile: ActorProfile { get }
    var position: Vec3f { get set }
    var rotation: Vec3s { get set }
    var params: UInt16 { get }
    var drawPasses: Set<ActorDrawPass> { get }

    func initialize(playState: PlayState)
    func update(playState: PlayState)
    func draw(playState: PlayState, pass: ActorDrawPass)
    func destroy(playState: PlayState)
}

@MainActor
public protocol TalkRequestingActor: Actor {
    var talkPrompt: String { get }
    var talkInteractionRange: Float { get }
    var talkFacingThreshold: Float { get }
    func talkRequested(playState: PlayState) -> Bool
}

public extension Actor {
    var drawPasses: Set<ActorDrawPass> { [.opaque] }

    func initialize(playState: PlayState) {}

    func update(playState: PlayState) {}

    func draw(playState: PlayState, pass: ActorDrawPass) {}

    func destroy(playState: PlayState) {}
}

public extension TalkRequestingActor {
    var talkPrompt: String { "Talk" }
    var talkInteractionRange: Float { 120 }
    var talkFacingThreshold: Float { 0.25 }
}

@MainActor
public protocol SkeletonRenderableActor: Actor {
    var skeletonRenderState: ActorSkeletonRenderState? { get }
}

@MainActor
public protocol DamageableActor: Actor {
    var hitPoints: Int { get set }
}

public struct ActorSpawnRecord: Sendable, Equatable {
    public var roomID: Int
    public var roomName: String
    public var spawn: SceneActorSpawn
    public var tableEntry: ActorTableEntry
    public var category: ActorCategory

    public init(
        roomID: Int,
        roomName: String,
        spawn: SceneActorSpawn,
        tableEntry: ActorTableEntry,
        category: ActorCategory
    ) {
        self.roomID = roomID
        self.roomName = roomName
        self.spawn = spawn
        self.tableEntry = tableEntry
        self.category = category
    }
}

@MainActor
open class BaseActor: Actor {
    public let profile: ActorProfile
    public let category: ActorCategory
    public let roomID: Int
    public let roomName: String
    public let spawnActorName: String
    public let spawnPosition: Vector3s
    public var position: Vec3f
    public var rotation: Vec3s
    public let params: UInt16

    open var drawPasses: Set<ActorDrawPass> {
        [.opaque]
    }

    public init(spawnRecord: ActorSpawnRecord) {
        profile = spawnRecord.tableEntry.profile
        category = spawnRecord.category
        roomID = spawnRecord.roomID
        roomName = spawnRecord.roomName
        spawnActorName = spawnRecord.spawn.actorName
        spawnPosition = spawnRecord.spawn.position
        position = Vec3f(spawnRecord.spawn.position)
        rotation = spawnRecord.spawn.rotation
        params = UInt16(bitPattern: spawnRecord.spawn.params)
    }

    public init(
        profile: ActorProfile,
        category: ActorCategory,
        position: Vec3f,
        rotation: Vec3s = Vector3s(x: 0, y: 0, z: 0),
        params: UInt16 = 0,
        roomID: Int = 0,
        roomName: String = "",
        spawnActorName: String = "",
        spawnPosition: Vector3s? = nil
    ) {
        self.profile = profile
        self.category = category
        self.roomID = roomID
        self.roomName = roomName
        self.spawnActorName = spawnActorName
        self.spawnPosition = spawnPosition ?? Vector3s(
            x: Int16(position.x.rounded()),
            y: Int16(position.y.rounded()),
            z: Int16(position.z.rounded())
        )
        self.position = position
        self.rotation = rotation
        self.params = params
    }

    open func initialize(playState: PlayState) {}

    open func update(playState: PlayState) {}

    open func draw(playState: PlayState, pass: ActorDrawPass) {}

    open func destroy(playState: PlayState) {}
}

@MainActor
open class DamageableBaseActor: BaseActor, DamageableActor {
    public var hitPoints: Int

    public init(spawnRecord: ActorSpawnRecord, hitPoints: Int = 1) {
        self.hitPoints = hitPoints
        super.init(spawnRecord: spawnRecord)
    }

    public init(
        profile: ActorProfile,
        category: ActorCategory,
        position: Vec3f,
        rotation: Vec3s = Vector3s(x: 0, y: 0, z: 0),
        params: UInt16 = 0,
        hitPoints: Int = 1,
        roomID: Int = 0,
        roomName: String = "",
        spawnActorName: String = "",
        spawnPosition: Vector3s? = nil
    ) {
        self.hitPoints = hitPoints
        super.init(
            profile: profile,
            category: category,
            position: position,
            rotation: rotation,
            params: params,
            roomID: roomID,
            roomName: roomName,
            spawnActorName: spawnActorName,
            spawnPosition: spawnPosition
        )
    }
}

@MainActor
open class CombatantBaseActor: DamageableBaseActor, CombatActor {
    public var combatProfile: ActorCombatProfile
    public var combatState: ActorCombatState

    public init(
        spawnRecord: ActorSpawnRecord,
        hitPoints: Int = 1,
        combatProfile: ActorCombatProfile = ActorCombatProfile()
    ) {
        self.combatProfile = combatProfile
        self.combatState = ActorCombatState()
        super.init(spawnRecord: spawnRecord, hitPoints: hitPoints)
    }

    public init(
        profile: ActorProfile,
        category: ActorCategory,
        position: Vec3f,
        rotation: Vec3s = Vector3s(x: 0, y: 0, z: 0),
        params: UInt16 = 0,
        hitPoints: Int = 1,
        combatProfile: ActorCombatProfile = ActorCombatProfile(),
        roomID: Int = 0,
        roomName: String = "",
        spawnActorName: String = "",
        spawnPosition: Vector3s? = nil
    ) {
        self.combatProfile = combatProfile
        self.combatState = ActorCombatState()
        super.init(
            profile: profile,
            category: category,
            position: position,
            rotation: rotation,
            params: params,
            hitPoints: hitPoints,
            roomID: roomID,
            roomName: roomName,
            spawnActorName: spawnActorName,
            spawnPosition: spawnPosition
        )
    }

    open var targetingRange: Float {
        combatProfile.targetingRange
    }

    open var targetAnchorHeight: Float {
        combatProfile.targetAnchorHeight
    }

    open var isTargetable: Bool {
        hitPoints > 0
    }

    open var activeAttacks: [CombatAttackDefinition] {
        []
    }

    open func combatDidReceiveHit(_ hit: CombatHit, playState: PlayState) {}

    open func combatDidBlockHit(_ hit: CombatHit, playState: PlayState) {}
}

@MainActor
public final class KokiriChildActor: DamageableBaseActor, TalkRequestingActor {
    public func talkRequested(playState: PlayState) -> Bool {
        let messageID = params == 0 ? 0x1000 : Int(params)
        playState.requestMessage(messageID)
        return true
    }
}

@MainActor
public final class DoorActor: BaseActor {}

@MainActor
public final class SignActor: DamageableBaseActor, TalkRequestingActor {
    public var talkInteractionRange: Float { 160 }

    public func talkRequested(playState: PlayState) -> Bool {
        let messageID = params == 0 ? 0x1001 : Int(params)
        playState.requestMessage(messageID)
        return true
    }
}

@MainActor
public final class GenericPropActor: DamageableBaseActor {}

@MainActor
public final class PlaceholderActor: DamageableBaseActor {}

@MainActor
public final class PlaceholderCombatActor: CombatantBaseActor {
    public init(spawnRecord: ActorSpawnRecord) {
        let hitPoints = spawnRecord.category == .boss ? 6 : 3
        super.init(
            spawnRecord: spawnRecord,
            hitPoints: hitPoints,
            combatProfile: ActorCombatProfile(
                hurtboxRadius: 20,
                hurtboxHeight: 52,
                targetAnchorHeight: 52,
                targetingRange: 320,
                damageTable: DamageTable(
                    defaultEffect: DamageEffect(damage: 1, knockbackDistance: 18),
                    overrides: [
                        .swordJump: DamageEffect(damage: 2, knockbackDistance: 26),
                        .swordSpin: DamageEffect(damage: 2, knockbackDistance: 22),
                    ]
                )
            )
        )
    }
}

@MainActor
public final class ActorRuntimeHooks: @unchecked Sendable {
    private let destroyHandler: @MainActor (any Actor) -> Void
    private let spawnHandler: @MainActor (any Actor, ActorCategory, Int) -> Void
    private let playerStateProvider: @MainActor () -> PlayerState?
    private let messageHandler: @MainActor (Int) -> Void
    private let chestOpenHandler: @MainActor (TreasureChestOpenRequest) -> Bool
    private let treasureQueryHandler: @MainActor (TreasureFlagKey) -> Bool
    private let rewardHandler: @MainActor (ActorReward) -> Void
    private let inventoryStateHandler: @MainActor () -> GameplayInventoryState
    private let dungeonEventHandler: @MainActor (DungeonEventFlagKey) -> Void
    private let dungeonEventQueryHandler: @MainActor (DungeonEventFlagKey) -> Bool

    public init(
        destroyHandler: @escaping @MainActor (any Actor) -> Void,
        spawnHandler: @escaping @MainActor (any Actor, ActorCategory, Int) -> Void,
        playerStateProvider: @escaping @MainActor () -> PlayerState?,
        messageHandler: @escaping @MainActor (Int) -> Void,
        chestOpenHandler: @escaping @MainActor (TreasureChestOpenRequest) -> Bool,
        treasureQueryHandler: @escaping @MainActor (TreasureFlagKey) -> Bool,
        rewardHandler: @escaping @MainActor (ActorReward) -> Void,
        inventoryStateHandler: @escaping @MainActor () -> GameplayInventoryState,
        dungeonEventHandler: @escaping @MainActor (DungeonEventFlagKey) -> Void,
        dungeonEventQueryHandler: @escaping @MainActor (DungeonEventFlagKey) -> Bool
    ) {
        self.destroyHandler = destroyHandler
        self.spawnHandler = spawnHandler
        self.playerStateProvider = playerStateProvider
        self.messageHandler = messageHandler
        self.chestOpenHandler = chestOpenHandler
        self.treasureQueryHandler = treasureQueryHandler
        self.rewardHandler = rewardHandler
        self.inventoryStateHandler = inventoryStateHandler
        self.dungeonEventHandler = dungeonEventHandler
        self.dungeonEventQueryHandler = dungeonEventQueryHandler
    }

    public func requestDestroy(_ actor: any Actor) {
        destroyHandler(actor)
    }

    public func requestSpawn(
        _ actor: any Actor,
        category: ActorCategory,
        roomID: Int
    ) {
        spawnHandler(actor, category, roomID)
    }

    public func requestMessage(_ messageID: Int) {
        messageHandler(messageID)
    }

    public func requestChestOpen(_ request: TreasureChestOpenRequest) -> Bool {
        chestOpenHandler(request)
    }

    public func isTreasureOpened(_ key: TreasureFlagKey) -> Bool {
        treasureQueryHandler(key)
    }

    public func requestReward(_ reward: ActorReward) {
        rewardHandler(reward)
    }

    public func currentPlayerState() -> PlayerState? {
        playerStateProvider()
    }

    public func currentInventoryState() -> GameplayInventoryState {
        inventoryStateHandler()
    }

    public func markDungeonEventTriggered(_ key: DungeonEventFlagKey) {
        dungeonEventHandler(key)
    }

    public func isDungeonEventTriggered(_ key: DungeonEventFlagKey) -> Bool {
        dungeonEventQueryHandler(key)
    }
}

@MainActor
public struct ActorRegistry {
    public typealias Factory = @MainActor (ActorSpawnRecord) -> any Actor

    private var factoriesByActorID: [Int: Factory]
    private let fallbackFactory: Factory

    public init(
        factoriesByActorID: [Int: Factory] = [:],
        fallbackFactory: @escaping Factory = { PlaceholderActor(spawnRecord: $0) }
    ) {
        self.factoriesByActorID = factoriesByActorID
        self.fallbackFactory = fallbackFactory
    }

    public mutating func register(actorID: Int, factory: @escaping Factory) {
        factoriesByActorID[actorID] = factory
    }

    public mutating func register<S: Sequence>(actorIDs: S, factory: @escaping Factory) where S.Element == Int {
        for actorID in actorIDs {
            register(actorID: actorID, factory: factory)
        }
    }

    public func makeActor(from spawnRecord: ActorSpawnRecord) -> any Actor {
        factoriesByActorID[spawnRecord.spawn.actorID]?(spawnRecord) ?? fallbackFactory(spawnRecord)
    }

    public static func `default`(actorTable: [ActorTableEntry]) -> ActorRegistry {
        var registry = ActorRegistry()

        registry.register(
            actorIDs: actorTable
                .filter { ActorCategory(rawValue: $0.profile.category) == .door }
                .map(\.id)
        ) { DoorActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { ActorCategory(rawValue: $0.profile.category) == .prop }
                .map(\.id)
        ) { GenericPropActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_KANBAN" }
                .map(\.id)
        ) { SignActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_KO" }
                .map(\.id)
        ) { KokiriChildActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_BOX" }
                .map(\.id)
        ) { TreasureChestActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_DEKUBABA" }
                .map(\.id)
        ) { DekuBabaActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_SW" }
                .map(\.id)
        ) { SkulltulaActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_BOSS_GOMA" }
                .map(\.id)
        ) { QueenGohmaActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_GOMA" }
                .map(\.id)
        ) { GohmaLarvaActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_BG_YDAN_SP" }
                .map(\.id)
        ) { BurnableWebActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_OBJ_SYOKUDAI" }
                .map(\.id)
        ) { TorchActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_OBJ_SWITCH" }
                .map(\.id)
        ) { DungeonSwitchActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter {
                    $0.enumName == "ACTOR_OBJ_OSHIHIKI" ||
                        $0.enumName == "ACTOR_OBJ_MAKEOSHIHIKI"
                }
                .map(\.id)
        ) { PushableBlockActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter {
                    let category = ActorCategory(rawValue: $0.profile.category)
                    guard category == .enemy || category == .boss else {
                        return false
                    }

                    return [
                        "ACTOR_EN_DEKUBABA",
                        "ACTOR_BOSS_GOMA",
                        "ACTOR_EN_GOMA",
                    ].contains($0.enumName) == false
                }
                .map(\.id)
        ) { PlaceholderCombatActor(spawnRecord: $0) }

        registry.register(
            actorIDs: actorTable
                .filter { $0.enumName == "ACTOR_EN_HINTNUTS" || $0.enumName == "ACTOR_EN_DEKUNUTS" }
                .map(\.id)
        ) { DekuScrubActor(spawnRecord: $0) }

        return registry
    }
}

@MainActor
public final class ActorContext {
    private struct SpawnKey: Hashable, Sendable {
        var roomID: Int
        var actorID: Int
        var position: Vector3s
        var rotation: Vector3s
        var params: Int16

        static func == (lhs: SpawnKey, rhs: SpawnKey) -> Bool {
            lhs.roomID == rhs.roomID &&
                lhs.actorID == rhs.actorID &&
                lhs.position == rhs.position &&
                lhs.rotation == rhs.rotation &&
                lhs.params == rhs.params
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(roomID)
            hasher.combine(actorID)
            hasher.combine(position.x)
            hasher.combine(position.y)
            hasher.combine(position.z)
            hasher.combine(rotation.x)
            hasher.combine(rotation.y)
            hasher.combine(rotation.z)
            hasher.combine(params)
        }
    }

    private struct ActorEntry {
        var spawnKey: SpawnKey?
        var roomID: Int
        var category: ActorCategory
        var actor: any Actor
    }

    private struct PendingSpawn {
        var roomID: Int
        var category: ActorCategory
        var actor: any Actor
    }

    private var actorsByCategory: [ActorCategory: [ActorEntry]]
    private var activeSpawnKeys: Set<SpawnKey>
    private var pendingDestroy: Set<ObjectIdentifier>
    private var pendingSpawns: [PendingSpawn]

    public var registry: ActorRegistry

    private let telemetryPublisher: any TelemetryPublishing

    public init(
        registry: ActorRegistry,
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher()
    ) {
        self.registry = registry
        self.telemetryPublisher = telemetryPublisher
        self.activeSpawnKeys = []
        self.pendingDestroy = []
        self.pendingSpawns = []
        self.actorsByCategory = Dictionary(
            uniqueKeysWithValues: ActorCategory.updatePriorityOrder.map { ($0, []) }
        )
    }

    public var actorCount: Int {
        actorsByCategory.values.reduce(0) { $0 + $1.count }
    }

    public var allActors: [any Actor] {
        ActorCategory.updatePriorityOrder.flatMap { category in
            actorsByCategory[category, default: []].map(\.actor)
        }
    }

    public func activeActors(in category: ActorCategory) -> [any Actor] {
        actorsByCategory[category, default: []].map(\.actor)
    }

    public func spawnActors(
        for roomIDs: Set<Int>,
        in scene: LoadedScene,
        actorTable: [Int: ActorTableEntry],
        playState: PlayState
    ) {
        for spawnRecord in makeSpawnRecords(for: roomIDs, in: scene, actorTable: actorTable) {
            spawn(spawnRecord, playState: playState)
        }
    }

    public func syncActiveRooms(
        _ roomIDs: Set<Int>,
        in scene: LoadedScene,
        actorTable: [Int: ActorTableEntry],
        playState: PlayState
    ) {
        destroyActorsOutsideRooms(roomIDs, playState: playState)
        spawnActors(for: roomIDs, in: scene, actorTable: actorTable, playState: playState)
    }

    public func requestDestroy(_ actor: any Actor) {
        pendingDestroy.insert(ObjectIdentifier(actor))
    }

    public func enqueueSpawn(
        _ actor: any Actor,
        category: ActorCategory,
        roomID: Int
    ) {
        pendingSpawns.append(
            PendingSpawn(
                roomID: roomID,
                category: category,
                actor: actor
            )
        )
    }

    public func updateAll(playState: PlayState) {
        flushPendingSpawns(playState: playState)

        for category in ActorCategory.updatePriorityOrder {
            let snapshot = actorsByCategory[category, default: []]

            for entry in snapshot where contains(entry.actor, in: category) {
                entry.actor.update(playState: playState)
                cleanupActorIfNeeded(entry.actor, in: category, playState: playState)
            }
        }

        flushPendingSpawns(playState: playState)
    }

    public func drawActors(in pass: ActorDrawPass, playState: PlayState) {
        let drawState = playState.withCurrentDrawPass(pass)

        for category in ActorCategory.updatePriorityOrder {
            let actors = actorsByCategory[category, default: []].map(\.actor)

            for actor in actors where actor.drawPasses.contains(pass) {
                actor.draw(playState: drawState, pass: pass)
            }
        }
    }

    private func spawn(_ spawnRecord: ActorSpawnRecord, playState: PlayState) {
        let spawnKey = SpawnKey(
            roomID: spawnRecord.roomID,
            actorID: spawnRecord.spawn.actorID,
            position: spawnRecord.spawn.position,
            rotation: spawnRecord.spawn.rotation,
            params: spawnRecord.spawn.params
        )

        guard activeSpawnKeys.contains(spawnKey) == false else {
            return
        }

        let actor = registry.makeActor(from: spawnRecord)
        let category = spawnRecord.category
        let actorEntry = ActorEntry(
            spawnKey: spawnKey,
            roomID: spawnRecord.roomID,
            category: category,
            actor: actor
        )

        actorsByCategory[category, default: []].append(actorEntry)
        activeSpawnKeys.insert(spawnKey)

        actor.initialize(playState: playState)
        cleanupActorIfNeeded(actor, in: category, playState: playState)
    }

    private func cleanupActorIfNeeded(
        _ actor: any Actor,
        in category: ActorCategory,
        playState: PlayState
    ) {
        let identifier = ObjectIdentifier(actor)
        let hitPoints = (actor as? any DamageableActor)?.hitPoints
        let shouldDestroy = pendingDestroy.contains(identifier) || (hitPoints.map { $0 <= 0 } ?? false)

        guard shouldDestroy else {
            return
        }

        removeActor(identifier, from: category, playState: playState)
    }

    private func destroyActorsOutsideRooms(_ roomIDs: Set<Int>, playState: PlayState) {
        for category in ActorCategory.updatePriorityOrder {
            let actorsToDestroy = actorsByCategory[category, default: []]
                .filter { roomIDs.contains($0.roomID) == false }
                .map { ObjectIdentifier($0.actor) }

            for actorID in actorsToDestroy {
                removeActor(actorID, from: category, playState: playState)
            }
        }
    }

    private func removeActor(
        _ actorID: ObjectIdentifier,
        from category: ActorCategory,
        playState: PlayState
    ) {
        guard let actorIndex = actorsByCategory[category, default: []]
            .firstIndex(where: { ObjectIdentifier($0.actor) == actorID })
        else {
            pendingDestroy.remove(actorID)
            return
        }

        let actorEntry = actorsByCategory[category, default: []].remove(at: actorIndex)
        if let spawnKey = actorEntry.spawnKey {
            activeSpawnKeys.remove(spawnKey)
        }
        pendingDestroy.remove(actorID)
        actorEntry.actor.destroy(playState: playState)
    }

    private func contains(_ actor: any Actor, in category: ActorCategory) -> Bool {
        actorsByCategory[category, default: []]
            .contains { ObjectIdentifier($0.actor) == ObjectIdentifier(actor) }
    }

    private func flushPendingSpawns(playState: PlayState) {
        guard pendingSpawns.isEmpty == false else {
            return
        }

        let queuedSpawns = pendingSpawns
        pendingSpawns.removeAll(keepingCapacity: true)

        for pendingSpawn in queuedSpawns {
            let actorEntry = ActorEntry(
                spawnKey: nil,
                roomID: pendingSpawn.roomID,
                category: pendingSpawn.category,
                actor: pendingSpawn.actor
            )
            actorsByCategory[pendingSpawn.category, default: []].append(actorEntry)
            pendingSpawn.actor.initialize(playState: playState)
            cleanupActorIfNeeded(
                pendingSpawn.actor,
                in: pendingSpawn.category,
                playState: playState
            )
        }
    }

    private func makeSpawnRecords(
        for roomIDs: Set<Int>,
        in scene: LoadedScene,
        actorTable: [Int: ActorTableEntry]
    ) -> [ActorSpawnRecord] {
        let actorsByRoomName = Dictionary(
            uniqueKeysWithValues: scene.actors?.rooms.map { ($0.roomName, $0.actors) } ?? []
        )
        var spawnRecords: [ActorSpawnRecord] = []

        for room in scene.manifest.rooms where roomIDs.contains(room.id) {
            guard let spawns = actorsByRoomName[room.name] else {
                continue
            }

            for spawn in spawns {
                guard let tableEntry = actorTable[spawn.actorID] else {
                    telemetryPublisher.publish("actor-context.missing-actor-table-entry.\(spawn.actorID)")
                    continue
                }

                let category = ActorCategory(rawValue: tableEntry.profile.category) ?? .misc
                spawnRecords.append(
                    ActorSpawnRecord(
                        roomID: room.id,
                        roomName: room.name,
                        spawn: spawn,
                        tableEntry: tableEntry,
                        category: category
                    )
                )
            }
        }

        return spawnRecords
    }
}

public typealias ActorSystem = ActorContext
