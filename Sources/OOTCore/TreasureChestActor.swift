import Foundation

@MainActor
public final class TreasureChestActor: BaseActor, TalkRequestingActor {
    public private(set) var chestSize: TreasureChestSize
    public private(set) var reward: TreasureChestReward?
    public private(set) var treasureFlagKey: TreasureFlagKey?
    public private(set) var isOpened = false
    public private(set) var lidOpenProgress: Float = 0

    private var isAnimatingOpen = false

    public override init(spawnRecord: ActorSpawnRecord) {
        let chestParams = TreasureChestParams(rawValue: UInt16(bitPattern: spawnRecord.spawn.params))
        chestSize = chestParams.chestSize
        reward = TreasureChestReward(getItemID: chestParams.getItemID)
        treasureFlagKey = TreasureFlagKey(
            scene: SceneIdentity(
                id: nil,
                name: spawnRecord.roomName
            ),
            flag: chestParams.treasureFlag
        )
        super.init(spawnRecord: spawnRecord)
    }

    public var talkPrompt: String {
        "Open"
    }

    public var talkInteractionRange: Float {
        isInteractable ? 72 : 0
    }

    public var talkFacingThreshold: Float {
        0.55
    }

    public override func initialize(playState: PlayState) {
        guard let key = treasureFlagKey(for: playState) else {
            return
        }

        if playState.isTreasureOpened(key) {
            isOpened = true
            lidOpenProgress = 1
        } else {
            treasureFlagKey = key
        }
    }

    public override func update(playState: PlayState) {
        guard isAnimatingOpen else {
            return
        }

        lidOpenProgress = min(1, lidOpenProgress + 0.08)
        if lidOpenProgress >= 1 {
            isAnimatingOpen = false
        }
    }

    public func talkRequested(playState: PlayState) -> Bool {
        guard
            isInteractable,
            let reward,
            let treasureFlagKey = treasureFlagKey(for: playState)
        else {
            return false
        }

        let request = TreasureChestOpenRequest(
            chestSize: chestSize,
            reward: reward,
            treasureFlag: treasureFlagKey
        )
        guard playState.requestChestOpen(request) else {
            return false
        }

        isOpened = true
        isAnimatingOpen = true
        return true
    }

    public var renderYawRadians: Float {
        rawRotationToRadians(Float(rotation.y)) + .pi
    }

    public var renderScale: Float {
        chestSize == .small ? 0.005 : 0.01
    }
}

private extension TreasureChestActor {
    var isInteractable: Bool {
        isOpened == false && reward != nil
    }

    func treasureFlagKey(for playState: PlayState) -> TreasureFlagKey? {
        guard let currentScene = playState.currentSceneIdentity else {
            return treasureFlagKey
        }

        let params = TreasureChestParams(rawValue: params)
        return TreasureFlagKey(
            scene: currentScene,
            flag: params.treasureFlag
        )
    }

    func rawRotationToRadians(_ rawValue: Float) -> Float {
        rawValue * (.pi / 32_768)
    }
}
