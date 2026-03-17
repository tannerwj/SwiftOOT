import AVFoundation
import OOTCore

@MainActor
final class OcarinaTonePlayer {
    static let shared = OcarinaTonePlayer()

    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConfigured = false

    private init() {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            fatalError("Unable to create ocarina audio format.")
        }
        self.format = format
    }

    func play(note: OcarinaNote) {
        guard configureIfNeeded() else {
            return
        }

        let duration = 0.18
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            return
        }

        let attack = max(1, Int(Double(frameCount) * 0.08))
        let release = max(1, Int(Double(frameCount) * 0.2))

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let phase = sin(2.0 * .pi * note.frequency * time)
            let envelope: Double
            if frame < attack {
                envelope = Double(frame) / Double(attack)
            } else if frame > Int(frameCount) - release {
                envelope = Double(Int(frameCount) - frame) / Double(release)
            } else {
                envelope = 1.0
            }
            channel[frame] = Float(phase * envelope * 0.18)
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
        if player.isPlaying == false {
            player.play()
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured == false {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConfigured = true
        }

        guard engine.isRunning == false else {
            return true
        }

        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
}
