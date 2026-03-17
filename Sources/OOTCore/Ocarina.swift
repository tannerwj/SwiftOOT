import Foundation

public enum OcarinaNote: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case a
    case cUp
    case cRight
    case cLeft
    case cDown

    public var buttonLabel: String {
        switch self {
        case .a:
            return "A"
        case .cUp:
            return "C-Up"
        case .cRight:
            return "C-Right"
        case .cLeft:
            return "C-Left"
        case .cDown:
            return "C-Down"
        }
    }

    public var pitchLabel: String {
        switch self {
        case .a:
            return "D"
        case .cUp:
            return "A"
        case .cRight:
            return "F"
        case .cLeft:
            return "B"
        case .cDown:
            return "D Low"
        }
    }

    public var staffLineIndex: Int {
        switch self {
        case .cUp:
            return 0
        case .cLeft:
            return 1
        case .a:
            return 2
        case .cRight:
            return 3
        case .cDown:
            return 4
        }
    }

    public var frequency: Double {
        switch self {
        case .a:
            return 293.66
        case .cUp:
            return 440.00
        case .cRight:
            return 349.23
        case .cLeft:
            return 493.88
        case .cDown:
            return 146.83
        }
    }
}

public enum OcarinaSessionMode: String, Codable, Sendable, Equatable {
    case freePlay
    case teachingPlayback
    case teachingRepeat
}

public struct OcarinaSessionState: Codable, Sendable, Equatable {
    public var mode: OcarinaSessionMode
    public var teachingSong: QuestSong?
    public var enteredNotes: [OcarinaNote]
    public var promptNotes: [OcarinaNote]
    public var highlightedPromptNoteIndex: Int?
    public var playbackFrameCounter: Int
    public var noteLimit: Int

    public init(
        mode: OcarinaSessionMode,
        teachingSong: QuestSong? = nil,
        enteredNotes: [OcarinaNote] = [],
        promptNotes: [OcarinaNote] = [],
        highlightedPromptNoteIndex: Int? = nil,
        playbackFrameCounter: Int = 0,
        noteLimit: Int = 8
    ) {
        self.mode = mode
        self.teachingSong = teachingSong
        self.enteredNotes = enteredNotes
        self.promptNotes = promptNotes
        self.highlightedPromptNoteIndex = highlightedPromptNoteIndex
        self.playbackFrameCounter = max(0, playbackFrameCounter)
        self.noteLimit = max(1, noteLimit)
    }
}

public struct OcarinaRecognitionState: Codable, Sendable, Equatable {
    public var song: QuestSong
    public var summary: String
    public var remainingFrames: Int
    public var learnedThroughTeaching: Bool

    public init(
        song: QuestSong,
        summary: String,
        remainingFrames: Int = 120,
        learnedThroughTeaching: Bool = false
    ) {
        self.song = song
        self.summary = summary
        self.remainingFrames = max(0, remainingFrames)
        self.learnedThroughTeaching = learnedThroughTeaching
    }
}

public enum OcarinaWorldEffectKind: String, Codable, Sendable, Equatable {
    case worldTrigger
    case advanceToDay
    case advanceToNight
    case callEpona
    case contactSaria
    case startRain
    case teachingSuccess
    case practice
}

public struct OcarinaWorldEffectResult: Codable, Sendable, Equatable {
    public var song: QuestSong
    public var kind: OcarinaWorldEffectKind
    public var summary: String
    public var eventFlag: DungeonEventFlagKey?

    public init(
        song: QuestSong,
        kind: OcarinaWorldEffectKind,
        summary: String,
        eventFlag: DungeonEventFlagKey? = nil
    ) {
        self.song = song
        self.kind = kind
        self.summary = summary
        self.eventFlag = eventFlag
    }
}

public extension QuestSong {
    static let childEraSongs: [QuestSong] = [
        .zeldasLullaby,
        .eponasSong,
        .sariasSong,
        .sunsSong,
        .songOfTime,
        .songOfStorms,
    ]

    var isChildEraSong: Bool {
        Self.childEraSongs.contains(self)
    }

    var ocarinaNotes: [OcarinaNote] {
        switch self {
        case .zeldasLullaby:
            return [.cLeft, .cUp, .cRight, .cLeft, .cUp, .cRight]
        case .eponasSong:
            return [.cUp, .cLeft, .cRight, .cUp, .cLeft, .cRight]
        case .sariasSong:
            return [.cDown, .cRight, .cLeft, .cDown, .cRight, .cLeft]
        case .sunsSong:
            return [.cRight, .cDown, .cUp, .cRight, .cDown, .cUp]
        case .songOfTime:
            return [.cRight, .a, .cDown, .cRight, .a, .cDown]
        case .songOfStorms:
            return [.a, .cDown, .cUp, .a, .cDown, .cUp]
        case .minuetOfForest:
            return [.a, .cUp, .cLeft, .cRight, .cLeft, .cRight]
        case .boleroOfFire:
            return [.cDown, .a, .cDown, .a, .cRight, .cDown, .cRight, .cDown]
        case .serenadeOfWater:
            return [.a, .cDown, .cRight, .cRight, .cLeft]
        case .requiemOfSpirit:
            return [.a, .cDown, .a, .cRight, .cDown, .a]
        case .nocturneOfShadow:
            return [.cLeft, .cRight, .cRight, .a, .cLeft, .cRight, .cDown]
        case .preludeOfLight:
            return [.cUp, .cRight, .cUp, .cRight, .cLeft, .cUp]
        }
    }

    var ocarinaButtonLabels: [String] {
        ocarinaNotes.map(\.buttonLabel)
    }

    init?(ocarinaSongIndex: Int) {
        switch ocarinaSongIndex {
        case 0:
            self = .zeldasLullaby
        case 1:
            self = .eponasSong
        case 2:
            self = .sariasSong
        case 3:
            self = .sunsSong
        case 4:
            self = .songOfTime
        case 5:
            self = .songOfStorms
        case 6:
            self = .sariasSong
        default:
            return nil
        }
    }
}
