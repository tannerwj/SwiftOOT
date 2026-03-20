import AVFoundation
import Foundation
import OOTCore
import OOTDataModel

@MainActor
public final class AVFoundationMusicPlaybackController: MusicPlaybackControlling {
    private let contentRoot: URL
    private let engine = AVAudioEngine()
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var buffersByPlayerIndex: [Int: AVAudioPCMBuffer] = [:]
    private var currentPlayerIndex: Int?
    private var isConfigured = false
    private var crossfadeTask: Task<Void, Never>?

    public init(contentRoot: URL) {
        self.contentRoot = contentRoot.standardizedFileURL
    }

    public func play(
        track: AudioTrackManifest,
        crossfadeDuration: TimeInterval
    ) throws -> TimeInterval? {
        try configureIfNeeded()

        let sampleURL = try resolvePlayableSampleURL(for: track)
        let buffer = try loadBuffer(from: sampleURL)
        let shouldLoop = track.kind == .bgm
        let duration = shouldLoop ? nil : Double(buffer.frameLength) / buffer.format.sampleRate

        crossfadeTask?.cancel()
        let targetPlayerIndex = nextPlayerIndex(for: currentPlayerIndex, crossfadeDuration: crossfadeDuration)
        let targetPlayer = players[targetPlayerIndex]

        targetPlayer.stop()
        buffersByPlayerIndex[targetPlayerIndex] = buffer
        targetPlayer.volume = currentPlayerIndex == nil || crossfadeDuration <= 0 ? 1 : 0
        targetPlayer.scheduleBuffer(
            buffer,
            at: nil,
            options: shouldLoop ? [.loops] : [],
            completionHandler: nil
        )
        targetPlayer.play()

        guard
            let currentPlayerIndex,
            currentPlayerIndex != targetPlayerIndex,
            crossfadeDuration > 0
        else {
            stopInactivePlayers(except: targetPlayerIndex)
            self.currentPlayerIndex = targetPlayerIndex
            return duration
        }

        let outgoingPlayer = players[currentPlayerIndex]
        self.currentPlayerIndex = targetPlayerIndex
        startCrossfade(
            from: outgoingPlayer,
            to: targetPlayer,
            outgoingIndex: currentPlayerIndex,
            incomingIndex: targetPlayerIndex,
            duration: crossfadeDuration
        )
        return duration
    }

    public func stop() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        currentPlayerIndex = nil
        buffersByPlayerIndex.removeAll()
        for player in players {
            player.stop()
            player.volume = 1
        }
    }

    public func pause() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        players.forEach { $0.pause() }
    }

    public func resume() {
        try? configureIfNeeded()
        for player in players where player.isPlaying == false {
            player.play()
        }
    }
}

private extension AVFoundationMusicPlaybackController {
    func configureIfNeeded() throws {
        if isConfigured == false {
            for player in players {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: nil)
            }
            isConfigured = true
        }

        guard engine.isRunning == false else {
            return
        }

        try engine.start()
    }

    func resolvePlayableSampleURL(for track: AudioTrackManifest) throws -> URL {
        for relativePath in track.samplePaths where relativePath.isEmpty == false {
            let candidate = contentRoot
                .appendingPathComponent(relativePath, isDirectory: false)
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw MusicPlaybackControllerError.missingPlayableSample(track.id)
    }

    func loadBuffer(from fileURL: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: fileURL)
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try file.read(into: buffer)
        return buffer
    }

    func nextPlayerIndex(
        for currentPlayerIndex: Int?,
        crossfadeDuration: TimeInterval
    ) -> Int {
        guard let currentPlayerIndex, crossfadeDuration > 0 else {
            return 0
        }

        return currentPlayerIndex == 0 ? 1 : 0
    }

    func stopInactivePlayers(except activeIndex: Int) {
        for (index, player) in players.enumerated() where index != activeIndex {
            player.stop()
            player.volume = 1
            buffersByPlayerIndex.removeValue(forKey: index)
        }
    }

    func startCrossfade(
        from outgoingPlayer: AVAudioPlayerNode,
        to incomingPlayer: AVAudioPlayerNode,
        outgoingIndex: Int,
        incomingIndex: Int,
        duration: TimeInterval
    ) {
        let steps = max(1, Int(duration * 20))
        crossfadeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for step in 1...steps {
                guard Task.isCancelled == false else {
                    return
                }

                let progress = Float(step) / Float(steps)
                outgoingPlayer.volume = 1 - progress
                incomingPlayer.volume = progress
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
            }

            outgoingPlayer.stop()
            outgoingPlayer.volume = 1
            incomingPlayer.volume = 1
            self.buffersByPlayerIndex.removeValue(forKey: outgoingIndex)
            self.currentPlayerIndex = incomingIndex
            self.crossfadeTask = nil
        }
    }
}
