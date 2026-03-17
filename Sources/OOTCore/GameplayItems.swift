public enum GameplayUsableItem: String, Codable, Sendable, Equatable, CaseIterable {
    case slingshot
    case bombs
    case boomerang
    case dekuStick
    case dekuNut
    case ocarina
    case bottle

    public static let childAssignableItems: [GameplayUsableItem] = [
        .slingshot,
        .bombs,
        .boomerang,
        .dekuStick,
        .dekuNut,
    ]

    public var hudButtonItem: GameplayHUDButtonItem {
        switch self {
        case .slingshot:
            return .slingshot
        case .bombs:
            return .bomb
        case .boomerang:
            return .boomerang
        case .dekuStick:
            return .dekuStick
        case .dekuNut:
            return .dekuNut
        case .ocarina:
            return .ocarina
        case .bottle:
            return .bottle
        }
    }

    public var displayName: String {
        switch self {
        case .slingshot:
            return "Fairy Slingshot"
        case .bombs:
            return "Bombs"
        case .boomerang:
            return "Boomerang"
        case .dekuStick:
            return "Deku Stick"
        case .dekuNut:
            return "Deku Nut"
        case .ocarina:
            return "Ocarina"
        case .bottle:
            return "Bottle"
        }
    }
}

public enum GameplayCButton: String, Codable, Sendable, Equatable, CaseIterable {
    case left
    case down
    case right

    public var label: String {
        switch self {
        case .left:
            return "C-Left"
        case .down:
            return "C-Down"
        case .right:
            return "C-Right"
        }
    }
}

public struct GameplayCButtonLoadout: Codable, Sendable, Equatable {
    public var left: GameplayUsableItem?
    public var down: GameplayUsableItem?
    public var right: GameplayUsableItem?

    public init(
        left: GameplayUsableItem? = nil,
        down: GameplayUsableItem? = nil,
        right: GameplayUsableItem? = nil
    ) {
        self.left = left
        self.down = down
        self.right = right
    }

    public subscript(button: GameplayCButton) -> GameplayUsableItem? {
        get {
            switch button {
            case .left:
                return left
            case .down:
                return down
            case .right:
                return right
            }
        }
        set {
            switch button {
            case .left:
                left = newValue
            case .down:
                down = newValue
            case .right:
                right = newValue
            }
        }
    }
}

public struct GameplayHUDButtonState: Codable, Sendable, Equatable {
    public var item: GameplayHUDButtonItem
    public var ammoCount: Int?
    public var isEnabled: Bool

    public init(
        item: GameplayHUDButtonItem = .none,
        ammoCount: Int? = nil,
        isEnabled: Bool = false
    ) {
        self.item = item
        self.ammoCount = ammoCount.map { max(0, $0) }
        self.isEnabled = isEnabled
    }

    public static let empty = GameplayHUDButtonState()
}

public struct GameplayHUDCButtonState: Codable, Sendable, Equatable {
    public var left: GameplayHUDButtonState
    public var down: GameplayHUDButtonState
    public var right: GameplayHUDButtonState

    public init(
        left: GameplayHUDButtonState = .empty,
        down: GameplayHUDButtonState = .empty,
        right: GameplayHUDButtonState = .empty
    ) {
        self.left = left
        self.down = down
        self.right = right
    }

    public subscript(button: GameplayCButton) -> GameplayHUDButtonState {
        get {
            switch button {
            case .left:
                return left
            case .down:
                return down
            case .right:
                return right
            }
        }
        set {
            switch button {
            case .left:
                left = newValue
            case .down:
                down = newValue
            case .right:
                right = newValue
            }
        }
    }
}
