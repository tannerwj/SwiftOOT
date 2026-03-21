@preconcurrency import AVFoundation
import Foundation
import OOTCore
import OOTDataModel

@MainActor
final class RuntimeSoundEffectPlayer {
    private let engine = AVAudioEngine()
    private var sampleCache: [URL: AVAudioPCMBuffer] = [:]
    private var hasStartedEngine = false
    private var activeSamplePlayers: [ObjectIdentifier: AVAudioPlayer] = [:]

    func drainAndPlay(from runtime: GameRuntime) {
        let requests = runtime.drainPendingSoundEffectPlaybackRequests()
        guard requests.isEmpty == false else {
            return
        }

        for request in requests {
            play(request)
        }
    }

    private func startEngineIfNeeded() {
        guard hasStartedEngine == false else {
            return
        }

        engine.prepare()
        try? engine.start()
        hasStartedEngine = true
    }

    private func play(_ request: SoundEffectPlaybackRequest) {
        for layer in request.layers {
            switch layer.source {
            case .sample(let url):
                if playSampleLayer(
                    url: url,
                    layer: layer,
                    request: request
                ) == false {
                    continue
                }
            case .synth:
                startEngineIfNeeded()
                guard let buffer = makeBuffer(for: layer) else {
                    continue
                }

                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                player.volume = request.gain * layer.gain
                player.pan = max(-1, min(1, request.pan + layer.pan))
                player.scheduleBuffer(buffer) { [weak self, weak player] in
                    Task { @MainActor in
                        guard let self, let player else {
                            return
                        }
                        self.engine.disconnectNodeInput(player)
                        self.engine.detach(player)
                    }
                }
                player.play()
            }
        }
    }

    @discardableResult
    private func playSampleLayer(
        url: URL,
        layer: SoundEffectPlaybackLayer,
        request: SoundEffectPlaybackRequest
    ) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            return false
        }

        player.volume = request.gain * layer.gain
        player.pan = max(-1, min(1, request.pan + layer.pan))
        player.prepareToPlay()

        let key = ObjectIdentifier(player)
        activeSamplePlayers[key] = player

        let delaySeconds = max(0, Double(layer.delayFrames) / 60.0)
        let startTime = player.deviceCurrentTime + delaySeconds
        player.play(atTime: startTime)
        let cleanupDelay = delaySeconds + player.duration + 0.25
        Task { @MainActor [weak self] in
            let nanoseconds = UInt64(cleanupDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.activeSamplePlayers.removeValue(forKey: key)
        }
        return true
    }

    private func makeBuffer(for layer: SoundEffectPlaybackLayer) -> AVAudioPCMBuffer? {
        switch layer.source {
        case .sample(let url):
            makeSampleBuffer(url: url, delayFrames: layer.delayFrames)
        case .synth(let waveform, let frequencyHz):
            makeSynthBuffer(
                waveform: waveform,
                frequencyHz: frequencyHz,
                delayFrames: layer.delayFrames,
                durationFrames: layer.durationFrames
            )
        }
    }

    private func makeSampleBuffer(
        url: URL,
        delayFrames: Int
    ) -> AVAudioPCMBuffer? {
        guard let baseBuffer = loadSampleBuffer(url: url) else {
            return nil
        }

        let delaySampleFrames = Int64(delayFrames) * Int64(baseBuffer.format.sampleRate) / 60
        let totalFrames = AVAudioFrameCount(Int64(baseBuffer.frameLength) + delaySampleFrames)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: baseBuffer.format,
            frameCapacity: totalFrames
        ) else {
            return nil
        }

        outputBuffer.frameLength = totalFrames

        guard
            let sourceChannels = baseBuffer.floatChannelData,
            let destinationChannels = outputBuffer.floatChannelData
        else {
            return nil
        }

        let channelCount = Int(baseBuffer.format.channelCount)
        let sourceFrameCount = Int(baseBuffer.frameLength)
        let delayFrameCount = Int(delaySampleFrames)

        for channelIndex in 0..<channelCount {
            let destination = destinationChannels[channelIndex]
            destination.initialize(repeating: 0, count: Int(totalFrames))
            let source = sourceChannels[channelIndex]
            let destinationStart = destination.advanced(by: delayFrameCount)
            destinationStart.update(from: source, count: sourceFrameCount)
        }

        return outputBuffer
    }

    func loadSampleBuffer(url: URL) -> AVAudioPCMBuffer? {
        if let cached = sampleCache[url] {
            return cached
        }

        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return nil
        }

        do {
            try file.read(into: sourceBuffer)
        } catch {
            return nil
        }

        guard let playbackBuffer = makePlaybackSampleBuffer(from: sourceBuffer) else {
            return nil
        }

        sampleCache[url] = playbackBuffer
        return playbackBuffer
    }

    private func makePlaybackSampleBuffer(from sourceBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sourceFormat = sourceBuffer.format
        if sourceFormat.commonFormat == .pcmFormatFloat32,
           sourceFormat.isInterleaved == false,
           sourceBuffer.floatChannelData != nil {
            return sourceBuffer
        }

        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ) else {
            return nil
        }

        let frameCapacity = max(
            AVAudioFrameCount(1),
            AVAudioFrameCount(
                ceil(Double(sourceBuffer.frameLength) * playbackFormat.sampleRate / sourceFormat.sampleRate)
            )
        )
        guard
            let playbackBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCapacity),
            let converter = AVAudioConverter(from: sourceFormat, to: playbackFormat)
        else {
            return nil
        }

        let conversionState = AudioConversionState()
        var conversionError: NSError?
        let status = converter.convert(to: playbackBuffer, error: &conversionError) { _, outStatus in
            if conversionState.didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            conversionState.didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard conversionError == nil else {
            return nil
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return playbackBuffer
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    private func makeSynthBuffer(
        waveform: SoundEffectWaveform,
        frequencyHz: Double,
        delayFrames: Int,
        durationFrames: Int
    ) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let delaySampleFrames = Int(Double(delayFrames) / 60 * sampleRate)
        let toneSampleFrames = max(1, Int(Double(durationFrames) / 60 * sampleRate))
        let totalFrames = AVAudioFrameCount(delaySampleFrames + toneSampleFrames)

        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
            let channelData = buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength = totalFrames
        channelData.initialize(repeating: 0, count: Int(totalFrames))

        for sampleIndex in 0..<toneSampleFrames {
            let phase = (Double(sampleIndex) * frequencyHz / sampleRate).truncatingRemainder(dividingBy: 1)
            channelData[delaySampleFrames + sampleIndex] = waveform.sampleValue(at: phase)
        }

        return buffer
    }
}

private final class AudioConversionState: @unchecked Sendable {
    var didProvideInput = false
}

private extension SoundEffectWaveform {
    func sampleValue(at phase: Double) -> Float {
        let value: Double
        switch self {
        case .sine:
            value = sin(phase * 2 * .pi)
        case .square:
            value = phase < 0.5 ? 1 : -1
        case .sawtooth:
            value = (2 * phase) - 1
        case .triangle:
            value = 1 - (4 * abs(phase - 0.5))
        }

        return Float(value) * 0.2
    }
}
