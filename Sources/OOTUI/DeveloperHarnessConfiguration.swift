import CoreGraphics
import Foundation
import OOTCore
import OOTRender

public struct DeveloperHarnessViewport: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

public struct DeveloperInputVector: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    var stickInput: StickInput {
        StickInput(x: x, y: y).normalized
    }
}

public struct DeveloperInputFrameRange: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct DeveloperInputStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case duration
        case frameRange
        case stick
        case lPressed
        case rPressed
        case aPressed
        case bPressed
        case cLeftPressed
        case cDownPressed
        case cRightPressed
        case zPressed
        case startPressed
    }

    public var duration: Int?
    public var frameRange: DeveloperInputFrameRange?
    public var stick: DeveloperInputVector?
    public var lPressed: Bool
    public var rPressed: Bool
    public var aPressed: Bool
    public var bPressed: Bool
    public var cLeftPressed: Bool
    public var cDownPressed: Bool
    public var cRightPressed: Bool
    public var zPressed: Bool
    public var startPressed: Bool

    public init(
        duration: Int? = nil,
        frameRange: DeveloperInputFrameRange? = nil,
        stick: DeveloperInputVector? = nil,
        lPressed: Bool = false,
        rPressed: Bool = false,
        aPressed: Bool = false,
        bPressed: Bool = false,
        cLeftPressed: Bool = false,
        cDownPressed: Bool = false,
        cRightPressed: Bool = false,
        zPressed: Bool = false,
        startPressed: Bool = false
    ) {
        self.duration = duration
        self.frameRange = frameRange
        self.stick = stick
        self.lPressed = lPressed
        self.rPressed = rPressed
        self.aPressed = aPressed
        self.bPressed = bPressed
        self.cLeftPressed = cLeftPressed
        self.cDownPressed = cDownPressed
        self.cRightPressed = cRightPressed
        self.zPressed = zPressed
        self.startPressed = startPressed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        frameRange = try container.decodeIfPresent(DeveloperInputFrameRange.self, forKey: .frameRange)
        stick = try container.decodeIfPresent(DeveloperInputVector.self, forKey: .stick)
        lPressed = try container.decodeIfPresent(Bool.self, forKey: .lPressed) ?? false
        rPressed = try container.decodeIfPresent(Bool.self, forKey: .rPressed) ?? false
        aPressed = try container.decodeIfPresent(Bool.self, forKey: .aPressed) ?? false
        bPressed = try container.decodeIfPresent(Bool.self, forKey: .bPressed) ?? false
        cLeftPressed = try container.decodeIfPresent(Bool.self, forKey: .cLeftPressed) ?? false
        cDownPressed = try container.decodeIfPresent(Bool.self, forKey: .cDownPressed) ?? false
        cRightPressed = try container.decodeIfPresent(Bool.self, forKey: .cRightPressed) ?? false
        zPressed = try container.decodeIfPresent(Bool.self, forKey: .zPressed) ?? false
        startPressed = try container.decodeIfPresent(Bool.self, forKey: .startPressed) ?? false
    }
}

public struct DeveloperInputScript: Codable, Sendable, Equatable {
    private struct ResolvedStep: Sendable, Equatable {
        var startFrame: Int
        var endFrame: Int
        var stick: StickInput?
        var lPressed: Bool
        var rPressed: Bool
        var aPressed: Bool
        var bPressed: Bool
        var cLeftPressed: Bool
        var cDownPressed: Bool
        var cRightPressed: Bool
        var zPressed: Bool
        var startPressed: Bool
    }

    public var steps: [DeveloperInputStep]

    public init(steps: [DeveloperInputStep]) throws {
        self.steps = steps
        _ = try Self.resolveSteps(from: steps)
    }

    public var totalFrameCount: Int {
        ((try? Self.resolveSteps(from: steps).map(\.endFrame).max()) ?? -1) + 1
    }

    public func inputState(for frame: Int) -> ControllerInputState {
        guard let resolvedSteps = try? Self.resolveSteps(from: steps) else {
            return ControllerInputState()
        }

        var resolvedInput = ControllerInputState()
        for step in resolvedSteps where frame >= step.startFrame && frame <= step.endFrame {
            if let stick = step.stick {
                resolvedInput.stick = stick
            }
            resolvedInput.lPressed = resolvedInput.lPressed || step.lPressed
            resolvedInput.rPressed = resolvedInput.rPressed || step.rPressed
            resolvedInput.aPressed = resolvedInput.aPressed || step.aPressed
            resolvedInput.bPressed = resolvedInput.bPressed || step.bPressed
            resolvedInput.cLeftPressed = resolvedInput.cLeftPressed || step.cLeftPressed
            resolvedInput.cDownPressed = resolvedInput.cDownPressed || step.cDownPressed
            resolvedInput.cRightPressed = resolvedInput.cRightPressed || step.cRightPressed
            resolvedInput.zPressed = resolvedInput.zPressed || step.zPressed
            resolvedInput.startPressed = resolvedInput.startPressed || step.startPressed
        }
        return resolvedInput
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let steps = try container.decode([DeveloperInputStep].self)
        try self.init(steps: steps)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(steps)
    }

    private static func resolveSteps(from steps: [DeveloperInputStep]) throws -> [ResolvedStep] {
        var resolvedSteps: [ResolvedStep] = []
        var nextStartFrame = 0

        for step in steps {
            let usesDuration = step.duration != nil
            let usesRange = step.frameRange != nil
            guard usesDuration != usesRange else {
                throw DeveloperHarnessConfigurationError.invalidInputScript(
                    "Each scripted input step must define exactly one of `duration` or `frameRange`."
                )
            }

            let startFrame: Int
            let endFrame: Int

            if let duration = step.duration {
                guard duration > 0 else {
                    throw DeveloperHarnessConfigurationError.invalidInputScript(
                        "Scripted input step durations must be greater than zero."
                    )
                }
                startFrame = nextStartFrame
                endFrame = nextStartFrame + duration - 1
                nextStartFrame += duration
            } else if let frameRange = step.frameRange {
                guard frameRange.start >= 0, frameRange.end >= frameRange.start else {
                    throw DeveloperHarnessConfigurationError.invalidInputScript(
                        "Scripted input frame ranges must be non-negative and ordered."
                    )
                }
                startFrame = frameRange.start
                endFrame = frameRange.end
                nextStartFrame = max(nextStartFrame, endFrame + 1)
            } else {
                throw DeveloperHarnessConfigurationError.invalidInputScript(
                    "Scripted input step is missing timing information."
                )
            }

            resolvedSteps.append(
                ResolvedStep(
                    startFrame: startFrame,
                    endFrame: endFrame,
                    stick: step.stick?.stickInput,
                    lPressed: step.lPressed,
                    rPressed: step.rPressed,
                    aPressed: step.aPressed,
                    bPressed: step.bPressed,
                    cLeftPressed: step.cLeftPressed,
                    cDownPressed: step.cDownPressed,
                    cRightPressed: step.cRightPressed,
                    zPressed: step.zPressed,
                    startPressed: step.startPressed
                )
            )
        }

        return resolvedSteps
    }
}

public enum DeveloperHarnessConfigurationError: LocalizedError, Sendable, Equatable {
    case invalidInteger(name: String, value: String)
    case invalidTimeOfDay(value: String)
    case invalidViewport(value: String)
    case unreadableInputScript(path: String, reason: String)
    case invalidInputScript(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInteger(let name, let value):
            return "\(name) must be an integer. Received '\(value)'."
        case .invalidTimeOfDay(let value):
            return "SWIFTOOT_TIME_OF_DAY must be a numeric hour value. Received '\(value)'."
        case .invalidViewport(let value):
            return "SWIFTOOT_CAPTURE_VIEWPORT must look like WIDTHxHEIGHT. Received '\(value)'."
        case .unreadableInputScript(let path, let reason):
            return "Failed to read SWIFTOOT_INPUT_SCRIPT at '\(path)': \(reason)"
        case .invalidInputScript(let reason):
            return "SWIFTOOT_INPUT_SCRIPT is invalid: \(reason)"
        }
    }
}

public struct DeveloperHarnessConfiguration: Sendable, Equatable {
    public static let sceneEnvironmentVariable = "SWIFTOOT_SCENE"
    public static let entranceEnvironmentVariable = "SWIFTOOT_ENTRANCE"
    public static let spawnEnvironmentVariable = "SWIFTOOT_SPAWN"
    public static let timeOfDayEnvironmentVariable = "SWIFTOOT_TIME_OF_DAY"
    public static let inputScriptEnvironmentVariable = "SWIFTOOT_INPUT_SCRIPT"
    public static let captureFrameEnvironmentVariable = "SWIFTOOT_CAPTURE_FRAME"
    public static let captureStateEnvironmentVariable = "SWIFTOOT_CAPTURE_STATE"
    public static let captureViewportEnvironmentVariable = "SWIFTOOT_CAPTURE_VIEWPORT"

    public static let defaultCaptureViewport = DeveloperHarnessViewport(width: 960, height: 540)

    public var launchConfiguration: DeveloperSceneLaunchConfiguration
    public var inputScript: DeveloperInputScript?
    public var captureFrameURL: URL?
    public var captureStateURL: URL?
    public var captureViewport: DeveloperHarnessViewport

    public init(
        launchConfiguration: DeveloperSceneLaunchConfiguration,
        inputScript: DeveloperInputScript? = nil,
        captureFrameURL: URL? = nil,
        captureStateURL: URL? = nil,
        captureViewport: DeveloperHarnessViewport = Self.defaultCaptureViewport
    ) {
        self.launchConfiguration = launchConfiguration
        self.inputScript = inputScript
        self.captureFrameURL = captureFrameURL
        self.captureStateURL = captureStateURL
        self.captureViewport = captureViewport
    }

    public var isEnabled: Bool {
        launchConfiguration.scene != nil ||
            launchConfiguration.entranceIndex != nil ||
            launchConfiguration.spawnIndex != nil ||
            launchConfiguration.fixedTimeOfDay != nil ||
            inputScript != nil ||
            captureFrameURL != nil ||
            captureStateURL != nil
    }

    public var captureRequested: Bool {
        captureFrameURL != nil || captureStateURL != nil
    }

    public var captureTriggerFrame: Int {
        max(inputScript?.totalFrameCount ?? 0, 1)
    }

    public static func load(
        from environment: [String: String],
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws -> DeveloperHarnessConfiguration? {
        let sceneValue = environment[sceneEnvironmentVariable]
        let entranceValue = environment[entranceEnvironmentVariable]
        let spawnValue = environment[spawnEnvironmentVariable]
        let timeValue = environment[timeOfDayEnvironmentVariable]
        let inputScriptValue = environment[inputScriptEnvironmentVariable]
        let captureFrameValue = environment[captureFrameEnvironmentVariable]
        let captureStateValue = environment[captureStateEnvironmentVariable]
        let captureViewportValue = environment[captureViewportEnvironmentVariable]

        let hasHarnessSignal =
            sceneValue != nil ||
            entranceValue != nil ||
            spawnValue != nil ||
            timeValue != nil ||
            inputScriptValue != nil ||
            captureFrameValue != nil ||
            captureStateValue != nil ||
            captureViewportValue != nil

        guard hasHarnessSignal else {
            return nil
        }

        let launchConfiguration = DeveloperSceneLaunchConfiguration(
            scene: try sceneValue.map(parseSceneSelection),
            entranceIndex: try parseInteger(
                environment[entranceEnvironmentVariable],
                name: entranceEnvironmentVariable
            ),
            spawnIndex: try parseInteger(
                environment[spawnEnvironmentVariable],
                name: spawnEnvironmentVariable
            ),
            fixedTimeOfDay: try parseTimeOfDay(environment[timeOfDayEnvironmentVariable])
        )

        let inputScript = try loadInputScript(
            path: environment[inputScriptEnvironmentVariable],
            currentDirectoryURL: currentDirectoryURL
        )
        let captureFrameURL = resolvePath(
            environment[captureFrameEnvironmentVariable],
            currentDirectoryURL: currentDirectoryURL
        )
        let captureStateURL = resolvePath(
            environment[captureStateEnvironmentVariable],
            currentDirectoryURL: currentDirectoryURL
        )
        let captureViewport = try parseViewport(environment[captureViewportEnvironmentVariable])

        return DeveloperHarnessConfiguration(
            launchConfiguration: launchConfiguration,
            inputScript: inputScript,
            captureFrameURL: captureFrameURL,
            captureStateURL: captureStateURL,
            captureViewport: captureViewport
        )
    }

    private static func parseSceneSelection(_ value: String) throws -> DeveloperSceneSelection {
        if let integerValue = parseIntegerLiteral(value) {
            return .id(integerValue)
        }
        return .name(value)
    }

    private static func parseInteger(
        _ value: String?,
        name: String
    ) throws -> Int? {
        guard let value else {
            return nil
        }

        guard let parsedValue = parseIntegerLiteral(value) else {
            throw DeveloperHarnessConfigurationError.invalidInteger(name: name, value: value)
        }
        return parsedValue
    }

    private static func parseIntegerLiteral(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed)
    }

    private static func parseTimeOfDay(_ value: String?) throws -> Double? {
        guard let value else {
            return nil
        }

        guard let parsedValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DeveloperHarnessConfigurationError.invalidTimeOfDay(value: value)
        }
        return parsedValue
    }

    private static func parseViewport(_ value: String?) throws -> DeveloperHarnessViewport {
        guard let value else {
            return defaultCaptureViewport
        }

        let normalizedValue = value.lowercased().replacingOccurrences(of: " ", with: "")
        let separators = ["x", ","]
        for separator in separators {
            let separatorCharacter = separator.first!
            let components = normalizedValue.split(separator: separatorCharacter, omittingEmptySubsequences: true)
            if components.count == 2,
               let width = Int(components[0]),
               let height = Int(components[1]),
               width > 0,
               height > 0
            {
                return DeveloperHarnessViewport(width: width, height: height)
            }
        }

        throw DeveloperHarnessConfigurationError.invalidViewport(value: value)
    }

    private static func loadInputScript(
        path: String?,
        currentDirectoryURL: URL
    ) throws -> DeveloperInputScript? {
        guard let scriptPath = path, !scriptPath.isEmpty else {
            return nil
        }

        let scriptURL = resolvedPath(scriptPath, currentDirectoryURL: currentDirectoryURL)
        do {
            let data = try Data(contentsOf: scriptURL)
            return try JSONDecoder().decode(DeveloperInputScript.self, from: data)
        } catch let error as DeveloperHarnessConfigurationError {
            throw error
        } catch {
            throw DeveloperHarnessConfigurationError.unreadableInputScript(
                path: scriptURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private static func resolvePath(
        _ value: String?,
        currentDirectoryURL: URL
    ) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return resolvedPath(value, currentDirectoryURL: currentDirectoryURL)
    }

    private static func resolvedPath(
        _ value: String,
        currentDirectoryURL: URL
    ) -> URL {
        let url = URL(fileURLWithPath: value, relativeTo: currentDirectoryURL)
        return url.standardizedFileURL
    }
}

@MainActor
final class ScriptedInputDriver: GameplayInputSyncing {
    private weak var runtime: GameRuntime?
    private let script: DeveloperInputScript

    init(runtime: GameRuntime, script: DeveloperInputScript) {
        self.runtime = runtime
        self.script = script
    }

    func sync(frame: Int) {
        runtime?.setControllerInput(script.inputState(for: frame))
    }
}
