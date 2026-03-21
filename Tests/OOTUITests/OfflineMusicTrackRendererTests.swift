import AVFoundation
import XCTest
import OOTContent
import OOTDataModel
@testable import OOTUI

@MainActor
final class OfflineMusicTrackRendererTests: XCTestCase {
    func testRendererProducesPCMOutputForScheduledNotes() throws {
        let sampleURL = try makePCM16WaveFile(frameCount: 2_048)
        var renderer = OfflineMusicTrackRenderer()

        let asset = MusicTrackPlaybackAsset(
            trackID: "test-track",
            title: "Test Track",
            kind: .fanfare,
            duration: 0.55,
            notes: [
                MusicTrackPlaybackNote(
                    sampleURL: sampleURL,
                    startTime: 0.0,
                    duration: 0.2,
                    midiNote: 60,
                    gain: 1,
                    pan: 0,
                    baseMIDINoteOverride: 60
                ),
                MusicTrackPlaybackNote(
                    sampleURL: sampleURL,
                    startTime: 0.3,
                    duration: 0.18,
                    midiNote: 72,
                    gain: 1,
                    pan: 0,
                    baseMIDINoteOverride: 60
                ),
            ]
        )

        let rendered = try renderer.render(asset: asset)

        XCTAssertGreaterThan(rendered.duration, 0.5)
        XCTAssertEqual(rendered.buffer.format.channelCount, 2)
        XCTAssertGreaterThan(
            energy(in: rendered.buffer, startTime: 0.02, duration: 0.08),
            0.01
        )
        XCTAssertGreaterThan(
            energy(in: rendered.buffer, startTime: 0.32, duration: 0.08),
            0.01
        )
        XCTAssertLessThan(
            energy(in: rendered.buffer, startTime: 0.24, duration: 0.03),
            0.005
        )
    }
}

private extension OfflineMusicTrackRendererTests {
    func makePCM16WaveFile(frameCount: AVAudioFrameCount) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("sample.wav")
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 22_050,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.int16ChannelData?[0]
        else {
            throw NSError(domain: "OfflineMusicTrackRendererTests", code: 1)
        }

        buffer.frameLength = frameCount
        for sampleIndex in 0..<Int(frameCount) {
            let phase = Double(sampleIndex) / 24.0
            channelData[sampleIndex] = Int16(sin(phase) * Double(Int16.max / 3))
        }

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try file.write(from: buffer)
        return fileURL
    }

    func energy(
        in buffer: AVAudioPCMBuffer,
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard let channels = buffer.floatChannelData else {
            return 0
        }

        let frameStart = max(0, Int(startTime * buffer.format.sampleRate))
        let frameEnd = min(
            Int(buffer.frameLength),
            Int((startTime + duration) * buffer.format.sampleRate)
        )
        guard frameEnd > frameStart else {
            return 0
        }

        var total = 0.0
        for frameIndex in frameStart..<frameEnd {
            total += Double(abs(channels[0][frameIndex]))
            total += Double(abs(channels[1][frameIndex]))
        }
        return total / Double(frameEnd - frameStart)
    }
}
