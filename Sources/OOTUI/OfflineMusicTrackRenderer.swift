@preconcurrency import AVFoundation
import Foundation
import OOTContent

struct RenderedMusicTrack {
    let buffer: AVAudioPCMBuffer
    let duration: TimeInterval
}

enum OfflineMusicTrackRendererError: Error, LocalizedError {
    case invalidOutputFormat
    case unreadableSample(String)
    case invalidSampleData(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutputFormat:
            "Unable to create the music renderer output format."
        case .unreadableSample(let path):
            "Unable to read music sample at \(path)."
        case .invalidSampleData(let path):
            "Music sample at \(path) did not decode into playable PCM data."
        }
    }
}

struct OfflineMusicTrackRenderer {
    private let outputSampleRate = 32_000.0
    private var sampleCache: [URL: RenderSample] = [:]

    mutating func render(asset: MusicTrackPlaybackAsset) throws -> RenderedMusicTrack {
        let duration = max(
            asset.duration,
            asset.notes.reduce(0) { partial, note in
                max(partial, note.startTime + note.duration)
            }
        )
        let totalFrames = max(1, Int(ceil(duration * outputSampleRate)))
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: 2,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
            ),
            let outputChannels = buffer.floatChannelData
        else {
            throw OfflineMusicTrackRendererError.invalidOutputFormat
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        outputChannels[0].initialize(repeating: 0, count: totalFrames)
        outputChannels[1].initialize(repeating: 0, count: totalFrames)

        for note in asset.notes where note.duration > 0 {
            let sample = try loadSample(url: note.sampleURL)
            mix(
                note: note,
                sample: sample,
                left: outputChannels[0],
                right: outputChannels[1],
                totalFrames: totalFrames
            )
        }

        normalizeIfNeeded(left: outputChannels[0], right: outputChannels[1], frameCount: totalFrames)
        return RenderedMusicTrack(buffer: buffer, duration: Double(totalFrames) / outputSampleRate)
    }
}

private extension OfflineMusicTrackRenderer {
    struct RenderSample {
        let frames: [Float]
        let sampleRate: Double
        let rootMIDINote: Int
        let loopStartFrame: Int?
        let loopEndFrame: Int?
    }

    mutating func loadSample(url: URL) throws -> RenderSample {
        if let cached = sampleCache[url] {
            return cached
        }

        guard let file = try? AVAudioFile(forReading: url) else {
            throw OfflineMusicTrackRendererError.unreadableSample(url.path)
        }

        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw OfflineMusicTrackRendererError.invalidSampleData(url.path)
        }

        try file.read(into: sourceBuffer)

        guard let playbackBuffer = convertToFloatBuffer(sourceBuffer, sourceURL: url) else {
            throw OfflineMusicTrackRendererError.invalidSampleData(url.path)
        }

        let metadata = try parseWaveMetadata(url: url)
        let frames = makeMonoFrames(from: playbackBuffer)
        let sample = RenderSample(
            frames: frames,
            sampleRate: playbackBuffer.format.sampleRate,
            rootMIDINote: metadata.rootMIDINote ?? 60,
            loopStartFrame: metadata.loopStartFrame,
            loopEndFrame: metadata.loopEndFrame
        )
        sampleCache[url] = sample
        return sample
    }

    func convertToFloatBuffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        sourceURL: URL
    ) -> AVAudioPCMBuffer? {
        let sourceFormat = sourceBuffer.format
        if sourceFormat.commonFormat == .pcmFormatFloat32,
           sourceFormat.isInterleaved == false,
           sourceBuffer.floatChannelData != nil {
            return sourceBuffer
        }

        guard
            let playbackFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: sourceFormat.channelCount,
                interleaved: false
            ),
            let playbackBuffer = AVAudioPCMBuffer(
                pcmFormat: playbackFormat,
                frameCapacity: AVAudioFrameCount(max(1, sourceBuffer.frameLength))
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: playbackFormat)
        else {
            return nil
        }

        let conversionState = AudioConversionState()
        var error: NSError?
        let status = converter.convert(to: playbackBuffer, error: &error) { _, outStatus in
            if conversionState.didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            conversionState.didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard error == nil else {
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

    func makeMonoFrames(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard
            let channels = buffer.floatChannelData
        else {
            return []
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
        }

        var mono = Array(repeating: Float.zero, count: frameCount)
        for frameIndex in 0..<frameCount {
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                sum += channels[channelIndex][frameIndex]
            }
            mono[frameIndex] = sum / Float(channelCount)
        }
        return mono
    }

    func mix(
        note: MusicTrackPlaybackNote,
        sample: RenderSample,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        totalFrames: Int
    ) {
        guard sample.frames.isEmpty == false else {
            return
        }

        let startFrame = max(0, Int(note.startTime * outputSampleRate))
        guard startFrame < totalFrames else {
            return
        }

        let framesToRender = max(1, Int(note.duration * outputSampleRate))
        let baseMIDINote = note.baseMIDINoteOverride ?? sample.rootMIDINote
        let pitchRatio = pow(2.0, Double(note.midiNote - baseMIDINote) / 12.0)
        let sourceStep = pitchRatio * sample.sampleRate / outputSampleRate
        let gain = Double(note.gain) * 0.45
        let pan = max(-1.0, min(1.0, Double(note.pan)))
        let angle = (pan + 1) * Double.pi / 4
        let leftGain = Float(cos(angle) * gain)
        let rightGain = Float(sin(angle) * gain)
        let fadeFrames = min(128, max(8, framesToRender / 16))

        for frameOffset in 0..<framesToRender {
            let outputIndex = startFrame + frameOffset
            guard outputIndex < totalFrames else {
                break
            }

            let sourcePosition = Double(frameOffset) * sourceStep
            guard let sampleValue = sampleValue(at: sourcePosition, sample: sample) else {
                break
            }

            let envelope = envelopeGain(
                frameOffset: frameOffset,
                totalFrames: framesToRender,
                fadeFrames: fadeFrames
            )
            left[outputIndex] += sampleValue * envelope * leftGain
            right[outputIndex] += sampleValue * envelope * rightGain
        }
    }

    func sampleValue(at position: Double, sample: RenderSample) -> Float? {
        let resolvedPosition = resolveSamplePosition(position, sample: sample)
        guard resolvedPosition >= 0 else {
            return nil
        }

        let lowerIndex = Int(floor(resolvedPosition))
        if lowerIndex >= sample.frames.count {
            return nil
        }

        let upperIndex = min(lowerIndex + 1, sample.frames.count - 1)
        let fraction = Float(resolvedPosition - Double(lowerIndex))
        let lower = sample.frames[lowerIndex]
        let upper = sample.frames[upperIndex]
        return lower + (upper - lower) * fraction
    }

    func resolveSamplePosition(_ position: Double, sample: RenderSample) -> Double {
        let sampleFrameCount = Double(sample.frames.count)
        guard sampleFrameCount > 1 else {
            return position
        }

        if position < sampleFrameCount {
            return position
        }

        guard
            let loopStartFrame = sample.loopStartFrame,
            let loopEndFrame = sample.loopEndFrame,
            loopEndFrame > loopStartFrame
        else {
            return -1
        }

        let loopStart = Double(loopStartFrame)
        let loopLength = Double(loopEndFrame - loopStartFrame)
        if position < loopStart {
            return position
        }
        return loopStart + (position - loopStart).truncatingRemainder(dividingBy: loopLength)
    }

    func envelopeGain(frameOffset: Int, totalFrames: Int, fadeFrames: Int) -> Float {
        guard fadeFrames > 0 else {
            return 1
        }

        let attack = min(1.0, Double(frameOffset + 1) / Double(fadeFrames))
        let release = min(1.0, Double(totalFrames - frameOffset) / Double(fadeFrames))
        return Float(min(attack, release))
    }

    func normalizeIfNeeded(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        var maxAmplitude: Float = 0
        for frameIndex in 0..<frameCount {
            maxAmplitude = max(maxAmplitude, abs(left[frameIndex]), abs(right[frameIndex]))
        }

        guard maxAmplitude > 0.95 else {
            return
        }

        let scale = 0.95 / maxAmplitude
        for frameIndex in 0..<frameCount {
            left[frameIndex] *= scale
            right[frameIndex] *= scale
        }
    }

    func parseWaveMetadata(url: URL) throws -> (rootMIDINote: Int?, loopStartFrame: Int?, loopEndFrame: Int?) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OfflineMusicTrackRendererError.unreadableSample(url.path)
        }

        guard data.count >= 12 else {
            return (nil, nil, nil)
        }

        var offset = 12
        var rootMIDINote: Int?
        var loopStartFrame: Int?
        var loopEndFrame: Int?

        while offset + 8 <= data.count {
            let tag = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let chunkSize = Int(readUInt32LE(data: data, offset: offset + 4))
            let chunkDataOffset = offset + 8
            guard chunkDataOffset + chunkSize <= data.count else {
                break
            }

            switch tag {
            case "inst":
                if chunkSize >= 1 {
                    rootMIDINote = Int(data[chunkDataOffset])
                }
            case "smpl":
                if chunkSize >= 60 {
                    rootMIDINote = rootMIDINote ?? Int(readUInt32LE(data: data, offset: chunkDataOffset + 12))
                    let loopCount = Int(readUInt32LE(data: data, offset: chunkDataOffset + 28))
                    if loopCount > 0 {
                        let firstLoopOffset = chunkDataOffset + 36
                        loopStartFrame = Int(readUInt32LE(data: data, offset: firstLoopOffset + 8))
                        loopEndFrame = Int(readUInt32LE(data: data, offset: firstLoopOffset + 12))
                    }
                }
            default:
                break
            }

            offset = chunkDataOffset + chunkSize + (chunkSize.isMultiple(of: 2) ? 0 : 1)
        }

        return (rootMIDINote, loopStartFrame, loopEndFrame)
    }

    func readUInt32LE(data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            return 0
        }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

private final class AudioConversionState: @unchecked Sendable {
    var didProvideInput = false
}
