import Foundation
import OOTDataModel

public struct MusicTrackPlaybackNote: Sendable, Equatable {
    public var sampleURL: URL
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var midiNote: Int
    public var gain: Float
    public var pan: Float
    public var baseMIDINoteOverride: Int?

    public init(
        sampleURL: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        midiNote: Int,
        gain: Float,
        pan: Float,
        baseMIDINoteOverride: Int? = nil
    ) {
        self.sampleURL = sampleURL
        self.startTime = startTime
        self.duration = duration
        self.midiNote = midiNote
        self.gain = gain
        self.pan = pan
        self.baseMIDINoteOverride = baseMIDINoteOverride
    }
}

public struct MusicTrackPlaybackAsset: Sendable, Equatable {
    public var trackID: String
    public var title: String
    public var kind: AudioTrackKind
    public var duration: TimeInterval
    public var notes: [MusicTrackPlaybackNote]

    public init(
        trackID: String,
        title: String,
        kind: AudioTrackKind,
        duration: TimeInterval,
        notes: [MusicTrackPlaybackNote]
    ) {
        self.trackID = trackID
        self.title = title
        self.kind = kind
        self.duration = duration
        self.notes = notes
    }
}

public protocol MusicTrackPlaybackAssetLoading {
    func loadPlaybackAsset(for track: AudioTrackManifest) throws -> MusicTrackPlaybackAsset
}

public enum MusicTrackPlaybackAssetLoaderError: Error, LocalizedError, Equatable, Sendable {
    case unreadableAsset(String, String)
    case missingSection(String, String)
    case missingInstrument(String, String)
    case missingSample(String, String)
    case invalidCommand(String)
    case invalidPitch(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableAsset(let path, let message):
            "Unable to read music asset at \(path): \(message)"
        case .missingSection(let trackID, let section):
            "Music track \(trackID) referenced missing sequence section \(section)."
        case .missingInstrument(let trackID, let instrument):
            "Music track \(trackID) referenced missing instrument \(instrument)."
        case .missingSample(let trackID, let sampleName):
            "Music track \(trackID) referenced missing sample \(sampleName)."
        case .invalidCommand(let command):
            "Unable to interpret extracted sequence command: \(command)"
        case .invalidPitch(let pitch):
            "Unable to interpret extracted pitch \(pitch)."
        }
    }
}

public struct MusicTrackPlaybackAssetLoader: MusicTrackPlaybackAssetLoading {
    public let contentRoot: URL

    public init(contentRoot: URL) {
        self.contentRoot = contentRoot.standardizedFileURL
    }

    public func loadPlaybackAsset(for track: AudioTrackManifest) throws -> MusicTrackPlaybackAsset {
        let sections = try parseSequenceSections(track: track)
        let soundfonts = try loadSoundfonts(track: track)
        let tempoAndChannels = try resolveSequencePlan(track: track, sections: sections)

        let notePlans = try tempoAndChannels.channelInvocations.flatMap { invocation in
            try resolveChannelNotes(
                track: track,
                sections: sections,
                invocation: invocation,
                soundfonts: soundfonts
            )
        }

        let duration = notePlans.reduce(tempoAndChannels.trackDuration) { partial, note in
            max(partial, seconds(forTick: note.endTick, tempoEvents: tempoAndChannels.tempoEvents))
        }

        let notes = notePlans.map { note in
            MusicTrackPlaybackNote(
                sampleURL: note.sampleURL,
                startTime: seconds(forTick: note.startTick, tempoEvents: tempoAndChannels.tempoEvents),
                duration: max(
                    1.0 / 1_000.0,
                    seconds(forTick: note.endTick, tempoEvents: tempoAndChannels.tempoEvents) -
                        seconds(forTick: note.startTick, tempoEvents: tempoAndChannels.tempoEvents)
                ),
                midiNote: note.midiNote,
                gain: note.gain,
                pan: note.pan,
                baseMIDINoteOverride: note.baseMIDINoteOverride
            )
        }
        .sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.midiNote < rhs.midiNote
            }
            return lhs.startTime < rhs.startTime
        }

        return MusicTrackPlaybackAsset(
            trackID: track.id,
            title: track.title,
            kind: track.kind,
            duration: duration,
            notes: notes
        )
    }
}

private extension MusicTrackPlaybackAssetLoader {
    struct SequenceSection {
        enum Kind {
            case sequence
            case channel
            case layer
        }

        let name: String
        let kind: Kind
        var commands: [SequenceCommand] = []
        var labels: [String: Int] = [:]
    }

    struct SequenceCommand {
        let mnemonic: String
        let arguments: [String]
        let rawLine: String
    }

    struct TempoEvent {
        let tick: Double
        let bpm: Double
    }

    struct ChannelInvocation {
        let sectionName: String
        let startTick: Double
        let masterGain: Float
    }

    struct SequencePlan {
        let tempoEvents: [TempoEvent]
        let channelInvocations: [ChannelInvocation]
        let trackDuration: TimeInterval
    }

    struct InstrumentReference: Hashable {
        let soundfontIndex: Int
        let programNumber: Int
    }

    struct InstrumentSampleZone {
        let sampleURL: URL
        let baseMIDINoteOverride: Int?
    }

    struct InstrumentDefinition {
        let defaultZone: InstrumentSampleZone
        let lowZoneUpperBound: Int?
        let lowZone: InstrumentSampleZone?
        let highZoneLowerBound: Int?
        let highZone: InstrumentSampleZone?
    }

    struct SoundfontDefinition {
        let instruments: [Int: InstrumentDefinition]
    }

    struct SamplePathCandidate {
        let relativePath: String
        let stem: String
        let bankName: String?
    }

    struct ChannelState {
        var localTick: Double = 0
        var gain: Float = 1
        var pan: Float = 0
        var transpose: Int = 0
        var instrument: InstrumentReference?
    }

    struct LayerState {
        var localTick: Double = 0
        var lastDuration: Double = 24
        var lastGate: Int = 255
    }

    struct ScheduledNote {
        let sampleURL: URL
        let startTick: Double
        let endTick: Double
        let midiNote: Int
        let gain: Float
        let pan: Float
        let baseMIDINoteOverride: Int?
    }

    func parseSequenceSections(track: AudioTrackManifest) throws -> [String: SequenceSection] {
        let sourceURL = try resolveContentURL(relativePath: track.sequencePath)
        let source: String
        do {
            source = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw MusicTrackPlaybackAssetLoaderError.unreadableAsset(
                sourceURL.path,
                error.localizedDescription
            )
        }

        var sections: [String: SequenceSection] = [:]
        var currentSection: SequenceSection?

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }

            if let header = parseSectionHeader(from: trimmed) {
                if let currentSection {
                    sections[currentSection.name] = currentSection
                }
                currentSection = SequenceSection(name: header.name, kind: header.kind)
                currentSection?.labels[header.name] = 0
                continue
            }

            if let label = parseLabel(from: trimmed) {
                if var section = currentSection {
                    section.labels[label] = section.commands.count
                    currentSection = section
                }
                continue
            }

            guard let command = parseCommand(from: trimmed) else {
                continue
            }
            if var section = currentSection {
                section.commands.append(command)
                currentSection = section
            }
        }

        if let currentSection {
            sections[currentSection.name] = currentSection
        }

        return sections
    }

    func resolveSequencePlan(
        track: AudioTrackManifest,
        sections: [String: SequenceSection]
    ) throws -> SequencePlan {
        guard let rootSection = sections.values.first(where: { $0.kind == .sequence }) else {
            throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, "sequence root")
        }

        var accumulator = 0
        var ioPorts: [String: Int] = [:]
        var localTick = 0.0
        var masterGain: Float = 1
        var tempo = 120.0
        var tempoEvents = [TempoEvent(tick: 0, bpm: tempo)]
        var channelInvocations: [ChannelInvocation] = []

        func executeSequenceSection(_ sectionName: String) throws {
            guard let section = sections[sectionName] else {
                throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, sectionName)
            }

            var index = 0
            while index < section.commands.count {
                let command = section.commands[index]
                switch command.mnemonic {
                case "delay":
                    localTick += parseDouble(command.arguments.first, rawLine: command.rawLine)
                case "tempo":
                    tempo = parseDouble(command.arguments.first, rawLine: command.rawLine)
                    tempoEvents.append(TempoEvent(tick: localTick, bpm: tempo))
                case "vol":
                    masterGain = normalize127(parseDouble(command.arguments.first, rawLine: command.rawLine))
                case "ldchan":
                    guard command.arguments.count == 2 else {
                        throw MusicTrackPlaybackAssetLoaderError.invalidCommand(command.rawLine)
                    }
                    channelInvocations.append(
                        ChannelInvocation(
                            sectionName: command.arguments[1],
                            startTick: localTick,
                            masterGain: masterGain
                        )
                    )
                case "call":
                    try executeSequenceSection(parseLabelReference(command.arguments.first, rawLine: command.rawLine))
                case "jump":
                    let label = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    let targetIndex = try resolveCommandIndex(
                        for: label,
                        in: section,
                        trackID: track.id
                    )
                    if targetIndex <= index {
                        return
                    }
                    index = targetIndex
                    continue
                case "beqz", "rbeqz":
                    guard accumulator == 0 else {
                        break
                    }
                    let label = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    index = try resolveCommandIndex(for: label, in: section, trackID: track.id)
                    continue
                case "rbltz":
                    guard accumulator < 0 else {
                        break
                    }
                    let label = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    index = try resolveCommandIndex(for: label, in: section, trackID: track.id)
                    continue
                case "ldi":
                    accumulator = parseInt(command.arguments.first, rawLine: command.rawLine)
                case "sub":
                    accumulator -= parseInt(command.arguments.first, rawLine: command.rawLine)
                case "ldio":
                    let port = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    accumulator = ioPorts[port, default: 0]
                case "stio":
                    let port = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    ioPorts[port] = accumulator
                case "initchan", "freechan", "mutebhv", "mutescale", "end":
                    if command.mnemonic == "end" {
                        return
                    }
                default:
                    break
                }
                index += 1
            }
        }

        try executeSequenceSection(rootSection.name)
        let duration = seconds(forTick: localTick, tempoEvents: tempoEvents)
        return SequencePlan(
            tempoEvents: normalizedTempoEvents(tempoEvents),
            channelInvocations: channelInvocations,
            trackDuration: duration
        )
    }

    func resolveChannelNotes(
        track: AudioTrackManifest,
        sections: [String: SequenceSection],
        invocation: ChannelInvocation,
        soundfonts: [Int: SoundfontDefinition]
    ) throws -> [ScheduledNote] {
        guard let section = sections[invocation.sectionName] else {
            throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, invocation.sectionName)
        }

        var notes: [ScheduledNote] = []
        var state = ChannelState(gain: invocation.masterGain)

        func executeChannelSection(_ sectionName: String) throws {
            guard let channelSection = sections[sectionName] else {
                throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, sectionName)
            }

            var index = 0
            while index < channelSection.commands.count {
                let command = channelSection.commands[index]
                switch command.mnemonic {
                case "delay", "cdelay":
                    state.localTick += parseDouble(command.arguments.first, rawLine: command.rawLine)
                case "vol":
                    state.gain = invocation.masterGain * normalize127(parseDouble(command.arguments.first, rawLine: command.rawLine))
                case "pan":
                    state.pan = panValue(parseDouble(command.arguments.first, rawLine: command.rawLine))
                case "transpose":
                    state.transpose = parseInt(command.arguments.first, rawLine: command.rawLine)
                case "instr":
                    state.instrument = try parseInstrumentReference(
                        command.arguments.first,
                        rawLine: command.rawLine
                    )
                case "ldlayer":
                    guard command.arguments.count == 2 else {
                        throw MusicTrackPlaybackAssetLoaderError.invalidCommand(command.rawLine)
                    }
                    notes.append(
                        contentsOf: try resolveLayerNotes(
                            track: track,
                            sections: sections,
                            layerName: command.arguments[1],
                            channelStartTick: invocation.startTick + state.localTick,
                            channelState: state,
                            soundfonts: soundfonts
                        )
                    )
                case "call":
                    try executeChannelSection(parseLabelReference(command.arguments.first, rawLine: command.rawLine))
                case "jump":
                    let label = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    let targetIndex = try resolveCommandIndex(
                        for: label,
                        in: channelSection,
                        trackID: track.id
                    )
                    if targetIndex <= index {
                        return
                    }
                    index = targetIndex
                    continue
                case "notepri", "reverb", "vibdepth", "noshort", "end":
                    if command.mnemonic == "end" {
                        return
                    }
                default:
                    break
                }
                index += 1
            }
        }

        try executeChannelSection(section.name)
        return notes
    }

    func resolveLayerNotes(
        track: AudioTrackManifest,
        sections: [String: SequenceSection],
        layerName: String,
        channelStartTick: Double,
        channelState: ChannelState,
        soundfonts: [Int: SoundfontDefinition]
    ) throws -> [ScheduledNote] {
        guard let section = sections[layerName] else {
            throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, layerName)
        }
        guard let instrument = channelState.instrument else {
            return []
        }

        var state = LayerState()
        var notes: [ScheduledNote] = []

        func executeLayerSection(_ sectionName: String) throws {
            guard let layerSection = sections[sectionName] else {
                throw MusicTrackPlaybackAssetLoaderError.missingSection(track.id, sectionName)
            }

            var index = 0
            while index < layerSection.commands.count {
                let command = layerSection.commands[index]
                switch command.mnemonic {
                case "ldelay", "delay", "cdelay":
                    state.localTick += parseDouble(command.arguments.first, rawLine: command.rawLine)
                case "notedvg":
                    guard command.arguments.count == 4 else {
                        throw MusicTrackPlaybackAssetLoaderError.invalidCommand(command.rawLine)
                    }
                    let duration = parseDouble(command.arguments[1], rawLine: command.rawLine)
                    let velocity = parseDouble(command.arguments[2], rawLine: command.rawLine)
                    let gate = parseInt(command.arguments[3], rawLine: command.rawLine)
                    try appendNote(
                        pitchToken: command.arguments[0],
                        duration: duration,
                        velocity: velocity,
                        gate: gate
                    )
                    state.lastDuration = duration
                    state.lastGate = gate
                case "notedv":
                    guard command.arguments.count == 3 else {
                        throw MusicTrackPlaybackAssetLoaderError.invalidCommand(command.rawLine)
                    }
                    let duration = parseDouble(command.arguments[1], rawLine: command.rawLine)
                    let velocity = parseDouble(command.arguments[2], rawLine: command.rawLine)
                    try appendNote(
                        pitchToken: command.arguments[0],
                        duration: duration,
                        velocity: velocity,
                        gate: state.lastGate
                    )
                    state.lastDuration = duration
                case "notevg":
                    guard command.arguments.count == 3 else {
                        throw MusicTrackPlaybackAssetLoaderError.invalidCommand(command.rawLine)
                    }
                    let velocity = parseDouble(command.arguments[1], rawLine: command.rawLine)
                    let gate = parseInt(command.arguments[2], rawLine: command.rawLine)
                    try appendNote(
                        pitchToken: command.arguments[0],
                        duration: state.lastDuration,
                        velocity: velocity,
                        gate: gate
                    )
                    state.lastGate = gate
                case "call":
                    try executeLayerSection(parseLabelReference(command.arguments.first, rawLine: command.rawLine))
                case "jump":
                    let label = parseLabelReference(command.arguments.first, rawLine: command.rawLine)
                    let targetIndex = try resolveCommandIndex(
                        for: label,
                        in: layerSection,
                        trackID: track.id
                    )
                    if targetIndex <= index {
                        return
                    }
                    index = targetIndex
                    continue
                case "end":
                    return
                default:
                    break
                }
                index += 1
            }
        }

        func appendNote(
            pitchToken: String,
            duration: Double,
            velocity: Double,
            gate: Int
        ) throws {
            let midiNote = try parseMIDINote(from: pitchToken) + channelState.transpose
            let definition = try resolveInstrument(
                trackID: track.id,
                instrument: instrument,
                soundfonts: soundfonts
            )
            let zone = try resolveZone(
                trackID: track.id,
                definition: definition,
                midiNote: midiNote
            )
            let gatedDuration = max(1.0, duration * gateFraction(gate))
            let startTick = channelStartTick + state.localTick
            let endTick = startTick + gatedDuration
            notes.append(
                ScheduledNote(
                    sampleURL: zone.sampleURL,
                    startTick: startTick,
                    endTick: endTick,
                    midiNote: midiNote,
                    gain: max(0, min(1, channelState.gain * normalize127(velocity))),
                    pan: channelState.pan,
                    baseMIDINoteOverride: zone.baseMIDINoteOverride
                )
            )
            state.localTick += duration
        }

        try executeLayerSection(section.name)
        return notes
    }

    func loadSoundfonts(track: AudioTrackManifest) throws -> [Int: SoundfontDefinition] {
        var definitions: [Int: SoundfontDefinition] = [:]

        for relativePath in track.soundfontPaths {
            let soundfontURL = try resolveContentURL(relativePath: relativePath)
            let source: String
            do {
                source = try String(contentsOf: soundfontURL, encoding: .utf8)
            } catch {
                throw MusicTrackPlaybackAssetLoaderError.unreadableAsset(
                    soundfontURL.path,
                    error.localizedDescription
                )
            }

            guard let rootAttributes = firstTagAttributes(named: "Soundfont", in: source) else {
                continue
            }

            let soundfontIndex = parseInt(rootAttributes["Index"], rawLine: soundfontURL.lastPathComponent)
            let sampleBankPath = try resolveSampleBankPath(
                track: track,
                soundfontURL: soundfontURL,
                soundfontAttributes: rootAttributes
            )
            let samplesByName = try loadSamplePathsByName(track: track, sampleBankURL: sampleBankPath)

            var instruments: [Int: InstrumentDefinition] = [:]
            for instrumentAttributes in tagAttributes(named: "Instrument", in: source) {
                let program = parseInt(instrumentAttributes["ProgramNumber"], rawLine: soundfontURL.lastPathComponent)
                let defaultSampleName = parseLabelReference(instrumentAttributes["Sample"], rawLine: soundfontURL.lastPathComponent)
                let defaultSampleURL = try resolveSampleURL(
                    sampleName: defaultSampleName,
                    samplesByName: samplesByName,
                    trackID: track.id
                )

                let lowZone: InstrumentSampleZone?
                if let sampleLo = instrumentAttributes["SampleLo"] {
                    lowZone = InstrumentSampleZone(
                        sampleURL: try resolveSampleURL(
                            sampleName: sampleLo,
                            samplesByName: samplesByName,
                            trackID: track.id
                        ),
                        baseMIDINoteOverride: parseOptionalPitch(instrumentAttributes["BaseNoteLo"])
                    )
                } else {
                    lowZone = nil
                }

                let highZone: InstrumentSampleZone?
                if let sampleHi = instrumentAttributes["SampleHi"] {
                    highZone = InstrumentSampleZone(
                        sampleURL: try resolveSampleURL(
                            sampleName: sampleHi,
                            samplesByName: samplesByName,
                            trackID: track.id
                        ),
                        baseMIDINoteOverride: parseOptionalPitch(instrumentAttributes["BaseNoteHi"])
                    )
                } else {
                    highZone = nil
                }

                let definition = InstrumentDefinition(
                    defaultZone: InstrumentSampleZone(
                        sampleURL: defaultSampleURL,
                        baseMIDINoteOverride: parseOptionalPitch(instrumentAttributes["BaseNote"])
                    ),
                    lowZoneUpperBound: parseOptionalPitch(instrumentAttributes["RangeLo"]),
                    lowZone: lowZone,
                    highZoneLowerBound: parseOptionalPitch(instrumentAttributes["RangeHi"]),
                    highZone: highZone
                )

                instruments[program] = definition
            }

            definitions[soundfontIndex] = SoundfontDefinition(instruments: instruments)
        }

        return definitions
    }

    func resolveInstrument(
        trackID: String,
        instrument: InstrumentReference,
        soundfonts: [Int: SoundfontDefinition]
    ) throws -> InstrumentDefinition {
        guard
            let soundfont = soundfonts[instrument.soundfontIndex],
            let definition = soundfont.instruments[instrument.programNumber]
        else {
            throw MusicTrackPlaybackAssetLoaderError.missingInstrument(
                trackID,
                "SF\(instrument.soundfontIndex)_INST_\(instrument.programNumber)"
            )
        }
        return definition
    }

    func resolveZone(
        trackID: String,
        definition: InstrumentDefinition,
        midiNote: Int
    ) throws -> (sampleURL: URL, baseMIDINoteOverride: Int?) {
        if let lowZoneUpperBound = definition.lowZoneUpperBound,
           midiNote <= lowZoneUpperBound,
           let lowZone = definition.lowZone {
            return (lowZone.sampleURL, lowZone.baseMIDINoteOverride)
        }

        if let highZoneLowerBound = definition.highZoneLowerBound,
           midiNote >= highZoneLowerBound,
           let highZone = definition.highZone {
            return (highZone.sampleURL, highZone.baseMIDINoteOverride)
        }

        return (definition.defaultZone.sampleURL, definition.defaultZone.baseMIDINoteOverride)
    }

    func loadSamplePathsByName(
        track: AudioTrackManifest,
        sampleBankURL: URL
    ) throws -> [String: URL] {
        let source: String
        do {
            source = try String(contentsOf: sampleBankURL, encoding: .utf8)
        } catch {
            throw MusicTrackPlaybackAssetLoaderError.unreadableAsset(
                sampleBankURL.path,
                error.localizedDescription
            )
        }

        let availableSamplePaths = track.samplePaths.map { relativePath in
            SamplePathCandidate(
                relativePath: relativePath,
                stem: sampleStem(for: relativePath),
                bankName: sampleBankName(for: relativePath)
            )
        }

        var resolved: [String: URL] = [:]
        for sampleAttributes in tagAttributes(named: "Sample", in: source) {
            guard let sampleName = sampleAttributes["Name"] else {
                continue
            }

            let stem: String?
            if let fileName = sampleAttributes["FileName"] {
                stem = sampleStem(for: fileName)
            } else if let path = sampleAttributes["Path"] {
                stem = sampleStem(for: path)
            } else {
                stem = nil
            }

            guard let stem else {
                continue
            }

            let requestedBankName = sampleAttributes["Path"].map(sampleBankName(for:))
                ?? sampleAttributes["FileName"].map(sampleBankName(for:))
                ?? sampleBankURL.deletingPathExtension().lastPathComponent

            if let relativePath = resolveSamplePath(
                stem: stem,
                requestedBankName: requestedBankName,
                availableSamplePaths: availableSamplePaths
            ) {
                resolved[sampleName] = try resolveContentURL(relativePath: relativePath)
            }
        }

        return resolved
    }

    func resolveSamplePath(
        stem: String,
        requestedBankName: String?,
        availableSamplePaths: [SamplePathCandidate]
    ) -> String? {
        let matchingStem = availableSamplePaths.filter { $0.stem == stem }
        guard matchingStem.isEmpty == false else {
            return nil
        }

        if let requestedBankName {
            let matchingBank = matchingStem.filter { $0.bankName == requestedBankName }
            if let match = matchingBank.first {
                return match.relativePath
            }
        }

        return matchingStem.first?.relativePath
    }

    func resolveSampleURL(
        sampleName: String,
        samplesByName: [String: URL],
        trackID: String
    ) throws -> URL {
        guard let sampleURL = samplesByName[sampleName] else {
            throw MusicTrackPlaybackAssetLoaderError.missingSample(trackID, sampleName)
        }
        return sampleURL
    }

    func resolveSampleBankPath(
        track: AudioTrackManifest,
        soundfontURL: URL,
        soundfontAttributes: [String: String]
    ) throws -> URL {
        guard let sampleBankValue = soundfontAttributes["SampleBank"] ?? soundfontAttributes["SampleBankDD"] else {
            throw MusicTrackPlaybackAssetLoaderError.invalidCommand(soundfontURL.lastPathComponent)
        }

        let sampleBankFileName = URL(fileURLWithPath: sampleBankValue).lastPathComponent
        guard let relativePath = track.sampleBankPaths.first(where: { $0.hasSuffix("/\(sampleBankFileName)") || $0.hasSuffix(sampleBankFileName) }) else {
            throw MusicTrackPlaybackAssetLoaderError.missingSample(track.id, sampleBankFileName)
        }

        return try resolveContentURL(relativePath: relativePath)
    }

    func resolveContentURL(relativePath: String) throws -> URL {
        let normalizedRelativePath: String
        if relativePath.hasPrefix("Audio/") {
            normalizedRelativePath = relativePath
        } else {
            normalizedRelativePath = relativePath
        }

        let resolvedURL = contentRoot
            .appendingPathComponent(normalizedRelativePath)
            .standardizedFileURL
        let rootPath = contentRoot.path
        guard resolvedURL.path == rootPath || resolvedURL.path.hasPrefix(rootPath + "/") else {
            throw ContentLoaderError.invalidReferencedPath(relativePath)
        }
        return resolvedURL
    }

    func parseSectionHeader(from line: String) -> (kind: SequenceSection.Kind, name: String)? {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return nil
        }

        switch parts[0] {
        case ".sequence":
            return (.sequence, parts[1])
        case ".channel":
            return (.channel, parts[1])
        case ".layer":
            return (.layer, parts[1])
        default:
            return nil
        }
    }

    func parseLabel(from line: String) -> String? {
        guard line.hasSuffix(":") else {
            return nil
        }
        return String(line.dropLast())
    }

    func parseCommand(from line: String) -> SequenceCommand? {
        guard let commentTerminator = line.range(of: "*/") else {
            return nil
        }
        let commandPortion = line[commentTerminator.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard commandPortion.isEmpty == false else {
            return nil
        }

        let components = commandPortion.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard let mnemonic = components.first else {
            return nil
        }
        let arguments = components.count > 1
            ? components[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            : []

        return SequenceCommand(
            mnemonic: mnemonic,
            arguments: arguments,
            rawLine: line
        )
    }

    func resolveCommandIndex(
        for label: String,
        in section: SequenceSection,
        trackID: String
    ) throws -> Int {
        guard let index = section.labels[label] else {
            throw MusicTrackPlaybackAssetLoaderError.missingSection(trackID, label)
        }
        return index
    }

    func parseInstrumentReference(
        _ token: String?,
        rawLine: String
    ) throws -> InstrumentReference {
        let value = parseLabelReference(token, rawLine: rawLine)
        let pattern = /^SF([0-9]+)_INST_([0-9]+)$/
        guard let match = value.wholeMatch(of: pattern) else {
            throw MusicTrackPlaybackAssetLoaderError.invalidCommand(rawLine)
        }
        return InstrumentReference(
            soundfontIndex: Int(match.1) ?? 0,
            programNumber: Int(match.2) ?? 0
        )
    }

    func parseMIDINote(from token: String) throws -> Int {
        let normalized = token.replacingOccurrences(of: "PITCH_", with: "")
        guard let note = parsePitchToken(normalized) else {
            throw MusicTrackPlaybackAssetLoaderError.invalidPitch(token)
        }
        return note
    }

    func parseOptionalPitch(_ token: String?) -> Int? {
        guard let token else {
            return nil
        }
        return parsePitchToken(token)
    }

    func parsePitchToken(_ token: String) -> Int? {
        let pattern = /^([A-G])([SF]?)(-?[0-9]+)$/
        guard let match = token.wholeMatch(of: pattern) else {
            return nil
        }

        let baseOffset: Int
        switch match.1 {
        case "C":
            baseOffset = 0
        case "D":
            baseOffset = 2
        case "E":
            baseOffset = 4
        case "F":
            baseOffset = 5
        case "G":
            baseOffset = 7
        case "A":
            baseOffset = 9
        case "B":
            baseOffset = 11
        default:
            return nil
        }

        let accidentalOffset: Int
        switch match.2 {
        case "S":
            accidentalOffset = 1
        case "F":
            accidentalOffset = -1
        default:
            accidentalOffset = 0
        }

        guard let octave = Int(match.3) else {
            return nil
        }

        return (octave + 1) * 12 + baseOffset + accidentalOffset
    }

    func parseInt(_ value: String?, rawLine: String) -> Int {
        Int(parseDouble(value, rawLine: rawLine))
    }

    func parseDouble(_ value: String?, rawLine: String) -> Double {
        guard let value else {
            return 0
        }

        if value.hasPrefix("0x") || value.hasPrefix("-0x") {
            return Double(Int(value.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0)
        }
        if value.hasPrefix("0b") {
            return Double(Int(value.dropFirst(2), radix: 2) ?? 0)
        }
        return Double(value) ?? 0
    }

    func parseLabelReference(_ value: String?, rawLine: String) -> String {
        guard let value, value.isEmpty == false else {
            return rawLine
        }
        return value
    }

    func normalize127(_ value: Double) -> Float {
        Float(max(0, min(1, value / 127.0)))
    }

    func panValue(_ value: Double) -> Float {
        let centered = (value - 64.0) / 63.0
        return Float(max(-1, min(1, centered)))
    }

    func gateFraction(_ gate: Int) -> Double {
        max(0.05, min(1.0, Double(gate) / 256.0))
    }

    func normalizedTempoEvents(_ tempoEvents: [TempoEvent]) -> [TempoEvent] {
        var normalized: [TempoEvent] = []
        for event in tempoEvents.sorted(by: { $0.tick < $1.tick }) {
            if let last = normalized.last, abs(last.tick - event.tick) < 0.000_1 {
                normalized[normalized.count - 1] = event
            } else {
                normalized.append(event)
            }
        }
        return normalized
    }

    func seconds(forTick tick: Double, tempoEvents: [TempoEvent]) -> TimeInterval {
        let events = normalizedTempoEvents(tempoEvents)
        guard let firstEvent = events.first else {
            return tick * (60.0 / (120.0 * 48.0))
        }

        var elapsed = 0.0
        var currentTempo = firstEvent.bpm
        var currentTick = firstEvent.tick

        for event in events.dropFirst() {
            guard tick > event.tick else {
                break
            }
            elapsed += (event.tick - currentTick) * (60.0 / (currentTempo * 48.0))
            currentTick = event.tick
            currentTempo = event.bpm
        }

        elapsed += max(0, tick - currentTick) * (60.0 / (currentTempo * 48.0))
        return elapsed
    }

    func sampleStem(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    func sampleBankName(for path: String) -> String? {
        let pathURL = URL(fileURLWithPath: path)
        let directoryName = pathURL.deletingLastPathComponent().lastPathComponent
        return directoryName.isEmpty ? nil : directoryName
    }

    func firstTagAttributes(named tagName: String, in source: String) -> [String: String]? {
        tagAttributes(named: tagName, in: source).first
    }

    func tagAttributes(named tagName: String, in source: String) -> [[String: String]] {
        let pattern = #"<\#(tagName)\b([^>]*)/?>(?:\s*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: nsRange)
        return matches.compactMap { match in
            guard
                let range = Range(match.range(at: 1), in: source)
            else {
                return nil
            }
            return attributeDictionary(from: String(source[range]))
        }
    }

    func attributeDictionary(from attributesSource: String) -> [String: String] {
        let pattern = #"([A-Za-z0-9_]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let nsRange = NSRange(attributesSource.startIndex..<attributesSource.endIndex, in: attributesSource)
        let matches = regex.matches(in: attributesSource, range: nsRange)
        var attributes: [String: String] = [:]

        for match in matches {
            guard
                let nameRange = Range(match.range(at: 1), in: attributesSource),
                let valueRange = Range(match.range(at: 2), in: attributesSource)
            else {
                continue
            }
            attributes[String(attributesSource[nameRange])] = String(attributesSource[valueRange])
        }

        return attributes
    }
}
