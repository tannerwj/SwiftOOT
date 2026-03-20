@preconcurrency import AVFoundation
import Foundation
import OOTCore
import OOTDataModel

@MainActor
final class RuntimeSoundEffectPlayer {
    private let engine = AVAudioEngine()
    private var sampleCache: [URL: AVAudioPCMBuffer] = [:]
    private var hasStartedEngine = false

    func drainAndPlay(from runtime: GameRuntime) {
        let requests = runtime.drainPendingSoundEffectPlaybackRequests()
        guard requests.isEmpty == false else {
            return
        }

        startEngineIfNeeded()

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

    private func loadSampleBuffer(url: URL) -> AVAudioPCMBuffer? {
        if let cached = sampleCache[url] {
            return cached
        }

        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return nil
        }
        try? file.read(into: buffer)
        sampleCache[url] = buffer
        return buffer
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
