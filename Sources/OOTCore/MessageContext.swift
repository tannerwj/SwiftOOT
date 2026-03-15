import Foundation
import OOTDataModel

public enum MessagePhase: String, Codable, Sendable, Equatable {
    case idle
    case opening
    case displaying
    case waitingForAdvance
    case waitingForChoice
    case closing
}

public struct MessageTextRun: Sendable, Equatable, Hashable {
    public var text: String
    public var color: MessageTextColor

    public init(
        text: String,
        color: MessageTextColor
    ) {
        self.text = text
        self.color = color
    }
}

public struct MessageChoiceState: Sendable, Equatable, Hashable {
    public var options: [MessageChoiceOption]
    public var selectedIndex: Int

    public init(
        options: [MessageChoiceOption],
        selectedIndex: Int = 0
    ) {
        self.options = options
        self.selectedIndex = selectedIndex
    }
}

public struct MessagePresentation: Sendable, Equatable {
    public var messageID: Int
    public var variant: MessageBoxVariant
    public var phase: MessagePhase
    public var textRuns: [MessageTextRun]
    public var icon: MessageIcon?
    public var choiceState: MessageChoiceState?

    public init(
        messageID: Int,
        variant: MessageBoxVariant,
        phase: MessagePhase,
        textRuns: [MessageTextRun],
        icon: MessageIcon? = nil,
        choiceState: MessageChoiceState? = nil
    ) {
        self.messageID = messageID
        self.variant = variant
        self.phase = phase
        self.textRuns = textRuns
        self.icon = icon
        self.choiceState = choiceState
    }
}

public struct MessageContext: Sendable, Equatable {
    public var catalog: MessageCatalog

    public private(set) var phase: MessagePhase
    public private(set) var queue: [Int]
    public private(set) var activeMessageID: Int?
    public private(set) var activePresentation: MessagePresentation?

    private var activeState: ActiveMessageState?

    public init(
        catalog: MessageCatalog = MessageCatalog(),
        phase: MessagePhase = .idle,
        queue: [Int] = [],
        activeMessageID: Int? = nil,
        activePresentation: MessagePresentation? = nil
    ) {
        self.catalog = catalog
        self.phase = phase
        self.queue = queue
        self.activeMessageID = activeMessageID
        self.activePresentation = activePresentation
        activeState = nil
    }

    public var isPresenting: Bool {
        phase != .idle
    }

    public var canRequestChoiceSelection: Bool {
        phase == .waitingForChoice
    }

    public mutating func setCatalog(_ catalog: MessageCatalog) {
        self.catalog = catalog
    }

    public mutating func enqueue(messageID: Int, playerName: String) {
        queue.append(messageID)

        if activeState == nil {
            startNextMessageIfNeeded(playerName: playerName)
        }
    }

    public mutating func tick(playerName: String) {
        guard var activeState else {
            startNextMessageIfNeeded(playerName: playerName)
            return
        }

        switch activeState.phase {
        case .opening:
            activeState.openingFramesRemaining -= 1
            if activeState.openingFramesRemaining <= 0 {
                activeState.phase = .displaying
            }
        case .displaying:
            activeState.advanceDisplay()
        case .waitingForAdvance, .waitingForChoice:
            break
        case .closing:
            activeState.closingFramesRemaining -= 1
            if activeState.closingFramesRemaining <= 0 {
                self.activeState = nil
                activeMessageID = nil
                activePresentation = nil
                phase = .idle
                startNextMessageIfNeeded(playerName: playerName)
                return
            }
        case .idle:
            break
        }

        updatePresentation(with: activeState)
        self.activeState = activeState
    }

    public mutating func advanceOrConfirm(playerName: String) {
        guard var activeState else {
            startNextMessageIfNeeded(playerName: playerName)
            return
        }

        switch activeState.phase {
        case .displaying:
            activeState.finishDisplaying()
        case .waitingForAdvance:
            activeState.beginClosing()
        case .waitingForChoice:
            activeState.beginClosing()
        case .opening:
            activeState.phase = .displaying
        case .closing, .idle:
            break
        }

        updatePresentation(with: activeState)
        self.activeState = activeState
    }

    public mutating func moveSelection(delta: Int) {
        guard var activeState, activeState.phase == .waitingForChoice else {
            return
        }

        activeState.moveSelection(delta: delta)
        updatePresentation(with: activeState)
        self.activeState = activeState
    }
}

private extension MessageContext {
    mutating func startNextMessageIfNeeded(playerName: String) {
        guard activeState == nil else {
            return
        }

        while queue.isEmpty == false {
            let messageID = queue.removeFirst()
            guard let definition = catalog[messageID] else {
                continue
            }

            let activeState = ActiveMessageState(
                definition: definition,
                playerName: playerName
            )
            self.activeState = activeState
            updatePresentation(with: activeState)
            activeMessageID = definition.id
            return
        }

        phase = .idle
        activeMessageID = nil
        activePresentation = nil
    }

    mutating func updatePresentation(with activeState: ActiveMessageState) {
        phase = activeState.phase
        activeMessageID = activeState.definition.id
        activePresentation = MessagePresentation(
            messageID: activeState.definition.id,
            variant: activeState.definition.variant,
            phase: activeState.phase,
            textRuns: activeState.visibleTextRuns,
            icon: activeState.currentIcon,
            choiceState: activeState.choiceState
        )
    }
}

private struct ActiveMessageState: Sendable, Equatable {
    fileprivate enum Opcode: Sendable, Equatable {
        case text(String, MessageTextColor)
        case speed(Int)
        case delay(Int)
        case choice([MessageChoiceOption])
        case icon(MessageIcon)
    }

    fileprivate let definition: MessageDefinition
    fileprivate var phase: MessagePhase
    fileprivate var visibleTextRuns: [MessageTextRun]
    fileprivate var currentIcon: MessageIcon?
    fileprivate var choiceState: MessageChoiceState?
    fileprivate var openingFramesRemaining: Int
    fileprivate var closingFramesRemaining: Int

    private var opcodes: [Opcode]
    private var opcodeIndex: Int
    private var characterIndex: Int
    private var waitFramesRemaining: Int
    private var framesUntilNextCharacter: Int
    private var currentTextColor: MessageTextColor
    private var framesPerCharacter: Int

    fileprivate init(
        definition: MessageDefinition,
        playerName: String
    ) {
        self.definition = definition
        phase = .opening
        visibleTextRuns = []
        currentIcon = nil
        choiceState = nil
        openingFramesRemaining = 6
        closingFramesRemaining = 4
        opcodes = Self.makeOpcodes(
            from: definition.segments,
            playerName: playerName
        )
        opcodeIndex = 0
        characterIndex = 0
        waitFramesRemaining = 0
        framesUntilNextCharacter = 0
        currentTextColor = .white
        framesPerCharacter = 2
    }

    fileprivate mutating func advanceDisplay() {
        guard phase == .displaying else {
            return
        }

        if waitFramesRemaining > 0 {
            waitFramesRemaining -= 1
            return
        }

        while opcodeIndex < opcodes.count {
            switch opcodes[opcodeIndex] {
            case .text(let text, let color):
                currentTextColor = color

                guard characterIndex < text.count else {
                    opcodeIndex += 1
                    characterIndex = 0
                    continue
                }

                if framesUntilNextCharacter > 0 {
                    framesUntilNextCharacter -= 1
                    return
                }

                let stringIndex = text.index(text.startIndex, offsetBy: characterIndex)
                appendVisibleCharacter(text[stringIndex], color: color)
                characterIndex += 1
                framesUntilNextCharacter = max(0, framesPerCharacter - 1)
                return
            case .speed(let frames):
                framesPerCharacter = max(1, frames)
                opcodeIndex += 1
            case .delay(let frames):
                waitFramesRemaining = max(0, frames)
                opcodeIndex += 1
                return
            case .choice(let options):
                choiceState = MessageChoiceState(options: options)
                phase = .waitingForChoice
                opcodeIndex += 1
                return
            case .icon(let icon):
                currentIcon = icon
                opcodeIndex += 1
            }
        }

        phase = .waitingForAdvance
    }

    fileprivate mutating func finishDisplaying() {
        while phase == .displaying {
            waitFramesRemaining = 0
            framesUntilNextCharacter = 0
            advanceDisplay()
        }
    }

    fileprivate mutating func beginClosing() {
        phase = .closing
        choiceState = nil
    }

    fileprivate mutating func moveSelection(delta: Int) {
        guard var choiceState, choiceState.options.isEmpty == false else {
            return
        }

        let optionCount = choiceState.options.count
        let newIndex = (choiceState.selectedIndex + delta).positiveModulo(optionCount)
        choiceState.selectedIndex = newIndex
        self.choiceState = choiceState
    }

    private mutating func appendVisibleCharacter(
        _ character: Character,
        color: MessageTextColor
    ) {
        if visibleTextRuns.indices.last.map({ visibleTextRuns[$0].color == color }) == true {
            visibleTextRuns[visibleTextRuns.count - 1].text.append(character)
        } else {
            visibleTextRuns.append(
                MessageTextRun(
                    text: String(character),
                    color: color
                )
            )
        }
    }

    private static func makeOpcodes(
        from segments: [MessageSegment],
        playerName: String
    ) -> [Opcode] {
        var opcodes: [Opcode] = []
        var currentColor: MessageTextColor = .white

        for segment in segments {
            switch segment {
            case .text(let text):
                for inlineSegment in parseInlineSegments(text) {
                    switch inlineSegment {
                    case .text(let inlineText):
                        if inlineText.isEmpty == false {
                            opcodes.append(.text(inlineText, currentColor))
                        }
                    case .color(let color):
                        currentColor = color
                    case .speed(let speed):
                        opcodes.append(.speed(speed))
                    case .delay(let frames):
                        opcodes.append(.delay(frames))
                    case .playerName:
                        opcodes.append(.text(playerName, currentColor))
                    case .choice(let choices):
                        opcodes.append(.choice(choices))
                    case .icon(let icon):
                        opcodes.append(.icon(icon))
                    }
                }
            case .color(let color):
                currentColor = color
            case .speed(let speed):
                opcodes.append(.speed(speed))
            case .delay(let frames):
                opcodes.append(.delay(frames))
            case .playerName:
                opcodes.append(.text(playerName, currentColor))
            case .choice(let choices):
                opcodes.append(.choice(choices))
            case .icon(let icon):
                opcodes.append(.icon(icon))
            }
        }

        return opcodes
    }

    private static func parseInlineSegments(_ text: String) -> [MessageSegment] {
        let pattern = #"(</?[^>]+>|\{[^}]+\})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)

        guard matches.isEmpty == false else {
            return [.text(text)]
        }

        var segments: [MessageSegment] = []
        var currentLocation = text.startIndex

        for match in matches {
            guard let tokenRange = Range(match.range, in: text) else {
                continue
            }

            if currentLocation < tokenRange.lowerBound {
                segments.append(.text(String(text[currentLocation..<tokenRange.lowerBound])))
            }

            let token = String(text[tokenRange])
            segments.append(parseToken(token))
            currentLocation = tokenRange.upperBound
        }

        if currentLocation < text.endIndex {
            segments.append(.text(String(text[currentLocation...])))
        }

        return segments
    }

    private static func parseToken(_ token: String) -> MessageSegment {
        let rawToken = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>{}/ "))
        let components = rawToken.split(separator: ":", maxSplits: 1).map(String.init)
        let command = components.first?.lowercased() ?? ""
        let value = components.count > 1 ? components[1] : ""

        switch command {
        case "color":
            return .color(MessageTextColor(rawValue: value.lowercased()) ?? .white)
        case "speed":
            return .speed(Int(value) ?? 2)
        case "delay", "wait":
            return .delay(Int(value) ?? 0)
        case "player", "playername", "name":
            return .playerName
        case "choice", "choices":
            let options = value
                .split(separator: "|")
                .map { MessageChoiceOption(title: String($0)) }
            return .choice(options)
        case "icon":
            return .icon(MessageIcon(rawValue: value))
        default:
            return .text(token)
        }
    }
}

private extension Int {
    func positiveModulo(_ modulus: Int) -> Int {
        guard modulus > 0 else {
            return 0
        }

        let remainder = self % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
