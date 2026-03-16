import Foundation

public enum DeveloperSceneSelection: Sendable, Equatable {
    case id(Int)
    case name(String)
}

public struct DeveloperSceneLaunchConfiguration: Sendable, Equatable {
    public var scene: DeveloperSceneSelection?
    public var entranceIndex: Int?
    public var spawnIndex: Int?
    public var fixedTimeOfDay: Double?

    public init(
        scene: DeveloperSceneSelection? = nil,
        entranceIndex: Int? = nil,
        spawnIndex: Int? = nil,
        fixedTimeOfDay: Double? = nil
    ) {
        self.scene = scene
        self.entranceIndex = entranceIndex
        self.spawnIndex = spawnIndex
        self.fixedTimeOfDay = fixedTimeOfDay
    }
}

public enum DeveloperSceneLaunchError: LocalizedError, Sendable, Equatable {
    case noAvailableScenes
    case unknownSceneName(String)
    case unknownSceneID(Int)

    public var errorDescription: String? {
        switch self {
        case .noAvailableScenes:
            return "No extracted scenes are available under the configured content root."
        case .unknownSceneName(let name):
            return "No extracted scene matched '\(name)'."
        case .unknownSceneID(let id):
            return "No extracted scene matched id \(id)."
        }
    }
}

public struct DeveloperRuntimeStateSnapshot: Codable, Sendable, Equatable {
    public struct Vector3Snapshot: Codable, Sendable, Equatable {
        public var x: Float
        public var y: Float
        public var z: Float

        public init(x: Float, y: Float, z: Float) {
            self.x = x
            self.y = y
            self.z = z
        }

        public init(_ vector: Vec3f) {
            self.init(x: vector.x, y: vector.y, z: vector.z)
        }
    }

    public struct PlayerSnapshot: Codable, Sendable, Equatable {
        public var position: Vector3Snapshot
        public var velocity: Vector3Snapshot
        public var facingRadians: Float
        public var isGrounded: Bool
        public var locomotionState: String
        public var animationClip: String
        public var animationFrame: Float
        public var floorHeight: Float?

        public init(
            position: Vector3Snapshot,
            velocity: Vector3Snapshot,
            facingRadians: Float,
            isGrounded: Bool,
            locomotionState: String,
            animationClip: String,
            animationFrame: Float,
            floorHeight: Float?
        ) {
            self.position = position
            self.velocity = velocity
            self.facingRadians = facingRadians
            self.isGrounded = isGrounded
            self.locomotionState = locomotionState
            self.animationClip = animationClip
            self.animationFrame = animationFrame
            self.floorHeight = floorHeight
        }
    }

    public struct MessageSnapshot: Codable, Sendable, Equatable {
        public var messageID: Int
        public var phase: String
        public var variant: String
        public var selectedChoiceIndex: Int?
        public var choiceCount: Int

        public init(
            messageID: Int,
            phase: String,
            variant: String,
            selectedChoiceIndex: Int?,
            choiceCount: Int
        ) {
            self.messageID = messageID
            self.phase = phase
            self.variant = variant
            self.selectedChoiceIndex = selectedChoiceIndex
            self.choiceCount = choiceCount
        }
    }

    public struct TalkTargetSnapshot: Codable, Sendable, Equatable {
        public var actorID: Int
        public var actorType: String
        public var prompt: String
        public var position: Vector3Snapshot
        public var planarDistance: Float
        public var facingAlignment: Float

        public init(
            actorID: Int,
            actorType: String,
            prompt: String,
            position: Vector3Snapshot,
            planarDistance: Float,
            facingAlignment: Float
        ) {
            self.actorID = actorID
            self.actorType = actorType
            self.prompt = prompt
            self.position = position
            self.planarDistance = planarDistance
            self.facingAlignment = facingAlignment
        }
    }

    public var gameState: GameState
    public var frameCount: Int
    public var timeOfDay: Double
    public var sceneName: String?
    public var sceneID: Int?
    public var roomID: Int?
    public var entranceIndex: Int?
    public var spawnIndex: Int?
    public var activeRoomIDs: [Int]
    public var loadedObjectIDs: [Int]
    public var playerName: String?
    public var player: PlayerSnapshot?
    public var message: MessageSnapshot?
    public var talkTarget: TalkTargetSnapshot?
    public var actionLabel: String?
    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        gameState: GameState,
        frameCount: Int,
        timeOfDay: Double,
        sceneName: String?,
        sceneID: Int?,
        roomID: Int?,
        entranceIndex: Int?,
        spawnIndex: Int?,
        activeRoomIDs: [Int],
        loadedObjectIDs: [Int],
        playerName: String?,
        player: PlayerSnapshot?,
        message: MessageSnapshot?,
        talkTarget: TalkTargetSnapshot?,
        actionLabel: String?,
        statusMessage: String?,
        errorMessage: String?
    ) {
        self.gameState = gameState
        self.frameCount = frameCount
        self.timeOfDay = timeOfDay
        self.sceneName = sceneName
        self.sceneID = sceneID
        self.roomID = roomID
        self.entranceIndex = entranceIndex
        self.spawnIndex = spawnIndex
        self.activeRoomIDs = activeRoomIDs
        self.loadedObjectIDs = loadedObjectIDs
        self.playerName = playerName
        self.player = player
        self.message = message
        self.talkTarget = talkTarget
        self.actionLabel = actionLabel
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
    }
}
