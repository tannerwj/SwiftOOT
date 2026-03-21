import AVFoundation
import XCTest
import OOTDataModel
@testable import OOTUI

@MainActor
final class AVFoundationMusicPlaybackControllerTests: XCTestCase {
    func testResolvePlaybackRendersSequenceTimingInsteadOfReturningPreviewSampleDuration() throws {
        let fixture = try MusicPlaybackControllerFixture()
        defer { fixture.cleanup() }

        let controller = AVFoundationMusicPlaybackController(contentRoot: fixture.contentRoot)
        let rendered = try controller.resolvePlayback(for: fixture.track)
        let previewSampleDuration = try fixture.previewSampleDuration()

        XCTAssertGreaterThan(rendered.duration, 0.95)
        XCTAssertLessThan(previewSampleDuration, 0.2)
        XCTAssertGreaterThan(rendered.duration, previewSampleDuration * 5)
    }
}

private struct MusicPlaybackControllerFixture {
    let root: URL
    let contentRoot: URL
    let track: AudioTrackManifest
    let sampleURL: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("MusicPlaybackControllerFixture-\(UUID().uuidString)", isDirectory: true)
        contentRoot = root

        let trackDirectory = contentRoot
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("BGM", isDirectory: true)
            .appendingPathComponent("test-track", isDirectory: true)
        try fileManager.createDirectory(at: trackDirectory, withIntermediateDirectories: true)

        try Self.write(
            """
            #include "aseq.h"
            #include "Soundfont_0.h"

            .startseq Sequence_Test

            .sequence SEQ_0000
            /* 0x0000 [0xDD 0x78               ] */ tempo       120
            /* 0x0002 [0x90 0x00 0x10          ] */ ldchan      0, CHAN_MAIN
            /* 0x0005 [0xFD 0x60               ] */ delay       96
            /* 0x0007 [0xFB 0x00 0x00          ] */ jump        SEQ_0000

            .channel CHAN_MAIN
            /* 0x0010 [0xDF 0x7F               ] */ vol         127
            /* 0x0012 [0xDD 0x40               ] */ pan         64
            /* 0x0014 [0xC1 0x00               ] */ instr       SF0_INST_0
            /* 0x0016 [0x88 0x00 0x20          ] */ ldlayer     0, LAYER_MAIN
            /* 0x0019 [0xFF                    ] */ end

            .layer LAYER_MAIN
            /* 0x0020 [0xC0 0x18               ] */ ldelay      24
            /* 0x0022 [0x2D 0x18 0x7F 0xFF     ] */ notedvg     PITCH_C4, 24, 127, 255
            /* 0x0026 [0x31 0x7F 0x80          ] */ notevg      PITCH_E4, 127, 128
            /* 0x0029 [0x34 0x30 0x60          ] */ notedv      PITCH_G4, 48, 96
            /* 0x002C [0xFF                    ] */ end
            """,
            to: trackDirectory.appendingPathComponent("sequence.seq")
        )

        try Self.write(
            #"<Sequence Name="Sequence_Test" Index="999"/>"#,
            to: trackDirectory.appendingPathComponent("sequence.xml")
        )

        try Self.write(
            """
            <Soundfont Name="Soundfont_0" Index="0" SampleBank="$(BUILD_DIR)/assets/audio/samplebanks/SampleBank_0.xml">
                <Instruments>
                    <Instrument ProgramNumber="0" Name="INST_0" Sample="SAMPLE_0_0"/>
                </Instruments>
            </Soundfont>
            """,
            to: trackDirectory
                .appendingPathComponent("soundfonts", isDirectory: true)
                .appendingPathComponent("Soundfont_0.xml")
        )

        try Self.write(
            """
            <SampleBank Name="SampleBank_0" Index="0">
                <Sample Name="SAMPLE_0_0" Path="$(BUILD_DIR)/assets/audio/samples/SampleBank_0/Sample000.aifc"/>
            </SampleBank>
            """,
            to: trackDirectory
                .appendingPathComponent("samplebanks", isDirectory: true)
                .appendingPathComponent("SampleBank_0.xml")
        )

        sampleURL = trackDirectory
            .appendingPathComponent("samples", isDirectory: true)
            .appendingPathComponent("SampleBank_0", isDirectory: true)
            .appendingPathComponent("Sample000.wav")
        try Self.writeWave(to: sampleURL, frameCount: 1_024)

        track = AudioTrackManifest(
            id: "test-track",
            title: "Test Track",
            kind: .fanfare,
            sequenceID: 999,
            sequenceEnumName: "NA_BGM_TEST",
            assetDirectory: "Audio/BGM/test-track",
            sequencePath: "Audio/BGM/test-track/sequence.seq",
            sequenceMetadataPath: "Audio/BGM/test-track/sequence.xml",
            soundfontPaths: ["Audio/BGM/test-track/soundfonts/Soundfont_0.xml"],
            sampleBankPaths: ["Audio/BGM/test-track/samplebanks/SampleBank_0.xml"],
            samplePaths: ["Audio/BGM/test-track/samples/SampleBank_0/Sample000.wav"]
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func previewSampleDuration() throws -> TimeInterval {
        let file = try AVAudioFile(forReading: sampleURL)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeWave(to url: URL, frameCount: AVAudioFrameCount) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

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
            throw NSError(domain: "MusicPlaybackControllerFixture", code: 1)
        }

        buffer.frameLength = frameCount
        for sampleIndex in 0..<Int(frameCount) {
            let phase = Double(sampleIndex) / 12.0
            channelData[sampleIndex] = Int16(sin(phase) * Double(Int16.max / 3))
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try file.write(from: buffer)
    }
}
