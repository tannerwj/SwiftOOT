import Foundation
import OOTContent
import OOTDataModel

public struct SoundEffectVolumeSettings: Sendable, Equatable {
    public var ui: Float
    public var player: Float
    public var environment: Float

    public init(
        ui: Float = 0.85,
        player: Float = 0.9,
        environment: Float = 0.8
    ) {
        self.ui = Self.clamped(ui)
        self.player = Self.clamped(player)
        self.environment = Self.clamped(environment)
    }

    public func volume(for category: SoundEffectCategory) -> Float {
        switch category {
        case .ui:
            ui
        case .player:
            player
        case .environment:
            environment
        }
    }

    private static func clamped(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}

public enum SoundEffectPlaybackSource: Sendable, Equatable {
    case sample(URL)
    case synth(SoundEffectWaveform, Double)
}

public struct SoundEffectPlaybackLayer: Sendable, Equatable {
    public var source: SoundEffectPlaybackSource
    public var delayFrames: Int
    public var durationFrames: Int
    public var gain: Float
    public var pan: Float

    public init(
        source: SoundEffectPlaybackSource,
        delayFrames: Int = 0,
        durationFrames: Int,
        gain: Float = 1,
        pan: Float = 0
    ) {
        self.source = source
        self.delayFrames = max(0, delayFrames)
        self.durationFrames = max(1, durationFrames)
        self.gain = gain
        self.pan = max(-1, min(1, pan))
    }
}

public struct SoundEffectPlaybackRequest: Identifiable, Sendable, Equatable {
    public var id: Int
    public var event: NamedSoundEffect
    public var category: SoundEffectCategory
    public var gain: Float
    public var pan: Float
    public var playbackDurationFrames: Int
    public var layers: [SoundEffectPlaybackLayer]

    public init(
        id: Int,
        event: NamedSoundEffect,
        category: SoundEffectCategory,
        gain: Float,
        pan: Float,
        playbackDurationFrames: Int,
        layers: [SoundEffectPlaybackLayer]
    ) {
        self.id = id
        self.event = event
        self.category = category
        self.gain = gain
        self.pan = max(-1, min(1, pan))
        self.playbackDurationFrames = max(1, playbackDurationFrames)
        self.layers = layers
    }
}

struct ResolvedSoundEffect: Sendable, Equatable {
    let event: NamedSoundEffect
    let category: SoundEffectCategory
    let concurrencyLimit: Int
    let playbackDurationFrames: Int
    let layers: [SoundEffectPlaybackLayer]
}

struct ActiveSoundEffectState: Sendable, Equatable {
    let event: NamedSoundEffect
    let expiresAtFrame: Int
}

extension GameRuntime {
    func loadSoundEffectCatalogIfAvailable() {
        guard soundEffectsByEvent.isEmpty else {
            return
        }

        guard let catalog = try? contentLoader.loadSoundEffectCatalog() else {
            return
        }

        var resolved: [NamedSoundEffect: ResolvedSoundEffect] = [:]

        for effect in catalog.effects {
            let layers = effect.layers.compactMap { layer -> SoundEffectPlaybackLayer? in
                if let samplePath = layer.samplePath,
                   let url = try? contentLoader.resolveContentURL(relativePath: samplePath) {
                    return SoundEffectPlaybackLayer(
                        source: .sample(url),
                        delayFrames: layer.delayFrames,
                        durationFrames: layer.durationFrames,
                        gain: layer.gain,
                        pan: layer.pan
                    )
                }
                if let waveform = layer.waveform,
                   let frequencyHz = layer.frequencyHz {
                    return SoundEffectPlaybackLayer(
                        source: .synth(waveform, frequencyHz),
                        delayFrames: layer.delayFrames,
                        durationFrames: layer.durationFrames,
                        gain: layer.gain,
                        pan: layer.pan
                    )
                }
                return nil
            }

            guard layers.isEmpty == false else {
                continue
            }

            resolved[effect.event] = ResolvedSoundEffect(
                event: effect.event,
                category: effect.category,
                concurrencyLimit: effect.concurrencyLimit,
                playbackDurationFrames: effect.playbackDurationFrames,
                layers: layers
            )
        }

        soundEffectsByEvent = resolved
    }

    public func drainPendingSoundEffectPlaybackRequests() -> [SoundEffectPlaybackRequest] {
        let drained = pendingSoundEffectPlaybackRequests
        pendingSoundEffectPlaybackRequests.removeAll(keepingCapacity: true)
        return drained
    }

    func queueSoundEffect(
        _ event: NamedSoundEffect,
        sourcePosition: Vec3f? = nil
    ) {
        loadSoundEffectCatalogIfAvailable()
        cleanupExpiredSoundEffects()

        guard let effect = soundEffectsByEvent[event] else {
            return
        }

        let activeCount = activeSoundEffects.filter { $0.event == event }.count
        guard activeCount < effect.concurrencyLimit else {
            return
        }

        let request = SoundEffectPlaybackRequest(
            id: nextSoundEffectRequestID,
            event: event,
            category: effect.category,
            gain: soundEffectVolumeSettings.volume(for: effect.category),
            pan: resolveSoundEffectPan(sourcePosition: sourcePosition),
            playbackDurationFrames: effect.playbackDurationFrames,
            layers: effect.layers
        )
        nextSoundEffectRequestID += 1
        pendingSoundEffectPlaybackRequests.append(request)
        activeSoundEffects.append(
            ActiveSoundEffectState(
                event: event,
                expiresAtFrame: gameTime.frameCount + effect.playbackDurationFrames
            )
        )
    }

    func cleanupExpiredSoundEffects() {
        activeSoundEffects.removeAll { $0.expiresAtFrame <= gameTime.frameCount }
    }

    func queueAmbientSoundIfNeeded(for scene: LoadedScene) {
        guard scene.manifest.name == "spot04" else {
            return
        }

        queueSoundEffect(.ambientRiver)
    }

    private func resolveSoundEffectPan(sourcePosition: Vec3f?) -> Float {
        guard let sourcePosition, let listenerPosition = playerState?.position else {
            return 0
        }

        let deltaX = sourcePosition.x - listenerPosition.x
        return max(-1, min(1, deltaX / 240))
    }
}
