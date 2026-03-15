import Foundation

public enum MessageBoxVariant: String, Codable, CaseIterable, Sendable, Equatable {
    case blue
    case red
    case white
}

public enum MessageTextColor: String, Codable, CaseIterable, Sendable, Equatable {
    case white
    case red
    case green
    case blue
    case yellow
    case cyan
    case purple
}

public struct MessageIcon: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MessageChoiceOption: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var value: String?

    public init(
        title: String,
        value: String? = nil
    ) {
        self.title = title
        self.value = value
    }
}

public enum MessageSegment: Codable, Sendable, Equatable, Hashable {
    case text(String)
    case color(MessageTextColor)
    case speed(Int)
    case delay(Int)
    case playerName
    case choice([MessageChoiceOption])
    case icon(MessageIcon)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case text
        case color
        case frames
        case speed
        case choices
        case title
        case icon
        case name
    }

    private enum SegmentType: String, Codable {
        case text
        case color
        case speed
        case delay
        case playerName
        case choice
        case icon
    }

    public init(from decoder: any Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let text = try? singleValueContainer.decode(String.self) {
            self = .text(text)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(SegmentType.self, forKey: .type)

        switch type {
        case .text?:
            let text =
                try container.decodeIfPresent(String.self, forKey: .text) ??
                container.decode(String.self, forKey: .value)
            self = .text(text)
        case .color?:
            let color =
                try container.decodeIfPresent(MessageTextColor.self, forKey: .color) ??
                container.decode(MessageTextColor.self, forKey: .value)
            self = .color(color)
        case .speed?:
            let speed =
                try container.decodeIfPresent(Int.self, forKey: .speed) ??
                container.decode(Int.self, forKey: .value)
            self = .speed(speed)
        case .delay?:
            let frames =
                try container.decodeIfPresent(Int.self, forKey: .frames) ??
                container.decode(Int.self, forKey: .value)
            self = .delay(frames)
        case .playerName?:
            self = .playerName
        case .choice?:
            if let choices = try container.decodeIfPresent([MessageChoiceOption].self, forKey: .choices) {
                self = .choice(choices)
            } else {
                let rawChoices = try container.decode([String].self, forKey: .value)
                self = .choice(rawChoices.map { MessageChoiceOption(title: $0) })
            }
        case .icon?:
            if let icon = try container.decodeIfPresent(MessageIcon.self, forKey: .icon) {
                self = .icon(icon)
            } else if let icon = try container.decodeIfPresent(MessageIcon.self, forKey: .value) {
                self = .icon(icon)
            } else {
                self = .icon(MessageIcon(rawValue: try container.decode(String.self, forKey: .name)))
            }
        case nil:
            if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                self = .text(text)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unable to infer a message segment type."
                )
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode(SegmentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .color(let color):
            try container.encode(SegmentType.color, forKey: .type)
            try container.encode(color, forKey: .color)
        case .speed(let speed):
            try container.encode(SegmentType.speed, forKey: .type)
            try container.encode(speed, forKey: .speed)
        case .delay(let frames):
            try container.encode(SegmentType.delay, forKey: .type)
            try container.encode(frames, forKey: .frames)
        case .playerName:
            try container.encode(SegmentType.playerName, forKey: .type)
        case .choice(let choices):
            try container.encode(SegmentType.choice, forKey: .type)
            try container.encode(choices, forKey: .choices)
        case .icon(let icon):
            try container.encode(SegmentType.icon, forKey: .type)
            try container.encode(icon, forKey: .icon)
        }
    }
}

public struct MessageDefinition: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var variant: MessageBoxVariant
    public var segments: [MessageSegment]

    public init(
        id: Int,
        variant: MessageBoxVariant = .blue,
        segments: [MessageSegment]
    ) {
        self.id = id
        self.variant = variant
        self.segments = segments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case messageID
        case key
        case variant
        case boxVariant
        case boxStyle
        case style
        case text
        case content
        case rawText
        case segments
        case choices
        case icon
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeID(from: container)
        variant = try Self.decodeVariant(from: container)

        if let segments = try container.decodeIfPresent([MessageSegment].self, forKey: .segments) {
            self.segments = segments
            return
        }

        if let text = try Self.decodeText(from: container) {
            var segments: [MessageSegment] = [.text(text)]
            if let icon = try? container.decode(MessageIcon.self, forKey: .icon) {
                segments.append(.icon(icon))
            }
            if let choices = try? container.decode([MessageChoiceOption].self, forKey: .choices) {
                segments.append(.choice(choices))
            } else if let rawChoices = try? container.decode([String].self, forKey: .choices) {
                segments.append(.choice(rawChoices.map { MessageChoiceOption(title: $0) }))
            }
            self.segments = segments
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .segments,
            in: container,
            debugDescription: "Message definition requires either `segments` or `text`."
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(variant, forKey: .variant)
        try container.encode(segments, forKey: .segments)
    }

    private static func decodeID(from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        if let numericID = try? container.decode(Int.self, forKey: .id) {
            return numericID
        }
        if let numericID = try? container.decode(Int.self, forKey: .messageID) {
            return numericID
        }
        if let stringID = try? container.decode(String.self, forKey: .id) {
            return try decodeID(from: stringID)
        }
        if let stringID = try? container.decode(String.self, forKey: .messageID) {
            return try decodeID(from: stringID)
        }
        if let stringID = try? container.decode(String.self, forKey: .key) {
            return try decodeID(from: stringID)
        }

        throw DecodingError.keyNotFound(
            CodingKeys.id,
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Message definition is missing an id."
            )
        )
    }

    fileprivate static func decodeID(from rawValue: String) throws -> Int {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let value = Int(normalized) {
            return value
        }

        let hexString = normalized
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "#", with: "")

        if let value = Int(hexString, radix: 16) {
            return value
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Unable to decode message id '\(rawValue)'."
            )
        )
    }

    private static func decodeVariant(from container: KeyedDecodingContainer<CodingKeys>) throws -> MessageBoxVariant {
        if let variant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .variant) {
            return variant
        }
        if let variant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .boxVariant) {
            return variant
        }
        if let variant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .boxStyle) {
            return variant
        }
        if let variant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .style) {
            return variant
        }
        return .blue
    }

    private static func decodeText(from container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            return text
        }
        if let text = try container.decodeIfPresent(String.self, forKey: .content) {
            return text
        }
        if let text = try container.decodeIfPresent(String.self, forKey: .rawText) {
            return text
        }
        return nil
    }
}

public struct MessageCatalog: Codable, Sendable, Equatable {
    public var messages: [Int: MessageDefinition]

    public init(messages: [Int: MessageDefinition] = [:]) {
        self.messages = messages
    }

    public init(messageList: [MessageDefinition]) {
        messages = Dictionary(uniqueKeysWithValues: messageList.map { ($0.id, $0) })
    }

    public subscript(messageID: Int) -> MessageDefinition? {
        messages[messageID]
    }

    private enum CodingKeys: String, CodingKey {
        case messages
    }

    public init(from decoder: any Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let messageList = try? singleValueContainer.decode([MessageDefinition].self) {
            self.init(messageList: messageList)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let messageList = try? container.decode([MessageDefinition].self, forKey: .messages) {
            self.init(messageList: messageList)
            return
        }

        if let messageMap = try? container.decode([String: MessagePayload].self, forKey: .messages) {
            self.init(messages: try Self.expandMap(messageMap))
            return
        }

        let dynamicContainer = try decoder.singleValueContainer()
        let messageMap = try dynamicContainer.decode([String: MessagePayload].self)
        self.init(messages: try Self.expandMap(messageMap))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(messages.values).sorted(by: { $0.id < $1.id }), forKey: .messages)
    }

    private static func expandMap(_ rawMessages: [String: MessagePayload]) throws -> [Int: MessageDefinition] {
        var expanded: [Int: MessageDefinition] = [:]

        for (key, payload) in rawMessages {
            let messageID = try MessageDefinition.decodeID(from: key)
            expanded[messageID] = payload.definition(for: messageID)
        }

        return expanded
    }

    private enum MessagePayload: Codable, Sendable, Equatable {
        case string(String)
        case definition(PartialMessageDefinition)

        init(from decoder: any Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            if let text = try? singleValueContainer.decode(String.self) {
                self = .string(text)
            } else {
                self = .definition(try singleValueContainer.decode(PartialMessageDefinition.self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var singleValueContainer = encoder.singleValueContainer()

            switch self {
            case .string(let text):
                try singleValueContainer.encode(text)
            case .definition(let definition):
                try singleValueContainer.encode(definition)
            }
        }

        func definition(for messageID: Int) -> MessageDefinition {
            switch self {
            case .string(let text):
                return MessageDefinition(
                    id: messageID,
                    segments: [.text(text)]
                )
            case .definition(let definition):
                return MessageDefinition(
                    id: messageID,
                    variant: definition.variant,
                    segments: definition.segments
                )
            }
        }
    }

    private struct PartialMessageDefinition: Codable, Sendable, Equatable {
        var variant: MessageBoxVariant
        var segments: [MessageSegment]

        private enum CodingKeys: String, CodingKey {
            case variant
            case boxVariant
            case boxStyle
            case style
            case text
            case content
            case rawText
            case segments
            case choices
            case icon
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let resolvedVariant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .variant) {
                variant = resolvedVariant
            } else if let resolvedVariant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .boxVariant) {
                variant = resolvedVariant
            } else if let resolvedVariant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .boxStyle) {
                variant = resolvedVariant
            } else if let resolvedVariant = try container.decodeIfPresent(MessageBoxVariant.self, forKey: .style) {
                variant = resolvedVariant
            } else {
                variant = .blue
            }

            if let segments = try container.decodeIfPresent([MessageSegment].self, forKey: .segments) {
                self.segments = segments
                return
            }

            let text =
                try container.decodeIfPresent(String.self, forKey: .text) ??
                container.decodeIfPresent(String.self, forKey: .content) ??
                container.decodeIfPresent(String.self, forKey: .rawText)

            guard let text else {
                throw DecodingError.dataCorruptedError(
                    forKey: .segments,
                    in: container,
                    debugDescription: "Message definition requires either `segments` or `text`."
                )
            }

            var resolvedSegments: [MessageSegment] = [.text(text)]
            if let icon = try? container.decode(MessageIcon.self, forKey: .icon) {
                resolvedSegments.append(.icon(icon))
            }
            if let choices = try? container.decode([MessageChoiceOption].self, forKey: .choices) {
                resolvedSegments.append(.choice(choices))
            } else if let rawChoices = try? container.decode([String].self, forKey: .choices) {
                resolvedSegments.append(.choice(rawChoices.map { MessageChoiceOption(title: $0) }))
            }
            segments = resolvedSegments
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(variant, forKey: .variant)
            try container.encode(segments, forKey: .segments)
        }
    }
}
