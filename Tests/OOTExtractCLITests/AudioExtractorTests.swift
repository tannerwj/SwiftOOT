import Foundation
import XCTest
@testable import OOTDataModel
@testable import OOTExtractSupport

final class AudioExtractorTests: XCTestCase {
    func testExtractWritesScopedTrackBundlesAndManifest() throws {
        let harness = try AudioHarness()
        defer { harness.cleanup() }

        try harness.seedSceneTable()
        try harness.seedTrack(
            sequenceID: 60,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_60" Index="60"/>"#
        )
        try harness.seedTrack(
            sequenceID: 28,
            soundfontName: "Soundfont_4",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_28" Index="28"/>"#
        )
        try harness.seedTrack(
            sequenceID: 30,
            soundfontName: "Soundfont_6",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_30" Index="30"/>"#
        )
        try harness.seedTrack(
            sequenceID: 34,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_34" Index="34"/>"#
        )
        try harness.seedTrack(
            sequenceID: 36,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_36" Index="36"/>"#
        )
        try harness.seedTrack(
            sequenceID: 43,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_43" Index="43"/>"#
        )

        try harness.seedSoundfont(named: "Soundfont_15", sampleBankName: "SampleBank_0", sampleNames: ["SAMPLE_0_119"])
        try harness.seedSoundfont(named: "Soundfont_4", sampleBankName: "SampleBank_2", sampleNames: ["SAMPLE_2_0"])
        try harness.seedSoundfont(named: "Soundfont_6", sampleBankName: "SampleBank_0", sampleNames: ["SAMPLE_0_115"])
        try harness.seedSampleBank(named: "SampleBank_0", samples: [("SAMPLE_0_115", "Sample115"), ("SAMPLE_0_119", "Sample119")])
        try harness.seedSampleBank(named: "SampleBank_2", samples: [("SAMPLE_2_0", "Sample0")])
        try harness.seedSample(bankName: "SampleBank_0", fileName: "Sample115")
        try harness.seedSample(bankName: "SampleBank_0", fileName: "Sample119")
        try harness.seedSample(bankName: "SampleBank_2", fileName: "Sample0")

        try AudioExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        let catalog = try JSONDecoder().decode(
            AudioTrackCatalog.self,
            from: Data(contentsOf: harness.outputRoot.appendingPathComponent("Manifests/audio/bgm-tracks.json"))
        )

        XCTAssertEqual(catalog.version, 1)
        XCTAssertEqual(catalog.tracks.map(\.id), [
            "heart-get",
            "inside-deku-tree",
            "item-get",
            "kokiri-forest",
            "open-treasure-chest",
            "title-theme",
        ])
        XCTAssertEqual(
            catalog.sceneBindings,
            [
                AudioSceneBinding(
                    sceneName: "spot04",
                    sceneID: 0x55,
                    sequenceID: 60,
                    sequenceEnumName: "NA_BGM_KOKIRI",
                    trackID: "kokiri-forest"
                ),
                AudioSceneBinding(
                    sceneName: "ydan",
                    sceneID: 0x10,
                    sequenceID: 28,
                    sequenceEnumName: "NA_BGM_INSIDE_DEKU_TREE",
                    trackID: "inside-deku-tree"
                ),
            ]
        )

        let kokiriTrack = try XCTUnwrap(catalog.tracks.first(where: { $0.id == "kokiri-forest" }))
        XCTAssertEqual(kokiriTrack.assetDirectory, "Audio/BGM/kokiri-forest")
        XCTAssertEqual(kokiriTrack.sequencePath, "Audio/BGM/kokiri-forest/sequence.seq")
        XCTAssertEqual(kokiriTrack.sequenceMetadataPath, "Audio/BGM/kokiri-forest/sequence.xml")
        XCTAssertEqual(kokiriTrack.soundfontPaths, ["Audio/BGM/kokiri-forest/soundfonts/Soundfont_15.xml"])
        XCTAssertEqual(kokiriTrack.sampleBankPaths, ["Audio/BGM/kokiri-forest/samplebanks/SampleBank_0.xml"])
        XCTAssertEqual(kokiriTrack.samplePaths, ["Audio/BGM/kokiri-forest/samples/SampleBank_0/Sample119.wav"])

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Audio/BGM/title-theme/sequence.seq")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.outputRoot
                    .appendingPathComponent("Audio/BGM/inside-deku-tree/sequence.seq")
                    .path
            )
        )

        try AudioExtractor().verify(using: harness.verificationContext)
    }

    func testVerifyFailsWhenManifestReferencedSampleIsMissing() throws {
        let harness = try AudioHarness()
        defer { harness.cleanup() }

        try harness.seedSceneTable()
        try harness.seedTrack(
            sequenceID: 60,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_60" Index="60"/>"#
        )
        try harness.seedTrack(
            sequenceID: 28,
            soundfontName: "Soundfont_4",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_28" Index="28"/>"#
        )
        try harness.seedTrack(
            sequenceID: 30,
            soundfontName: "Soundfont_6",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_30" Index="30"/>"#
        )
        try harness.seedTrack(
            sequenceID: 34,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_34" Index="34"/>"#
        )
        try harness.seedTrack(
            sequenceID: 36,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_36" Index="36"/>"#
        )
        try harness.seedTrack(
            sequenceID: 43,
            soundfontName: "Soundfont_15",
            metadata: #"<!-- extracted --><Sequence Name="Sequence_43" Index="43"/>"#
        )

        try harness.seedSoundfont(named: "Soundfont_15", sampleBankName: "SampleBank_0", sampleNames: ["SAMPLE_0_119"])
        try harness.seedSoundfont(named: "Soundfont_4", sampleBankName: "SampleBank_2", sampleNames: ["SAMPLE_2_0"])
        try harness.seedSoundfont(named: "Soundfont_6", sampleBankName: "SampleBank_0", sampleNames: ["SAMPLE_0_115"])
        try harness.seedSampleBank(named: "SampleBank_0", samples: [("SAMPLE_0_115", "Sample115"), ("SAMPLE_0_119", "Sample119")])
        try harness.seedSampleBank(named: "SampleBank_2", samples: [("SAMPLE_2_0", "Sample0")])
        try harness.seedSample(bankName: "SampleBank_0", fileName: "Sample115")
        try harness.seedSample(bankName: "SampleBank_0", fileName: "Sample119")
        try harness.seedSample(bankName: "SampleBank_2", fileName: "Sample0")

        try AudioExtractor().extract(using: harness.extractionContext(sceneName: "spot04"))

        try FileManager.default.removeItem(
            at: harness.outputRoot.appendingPathComponent("Audio/BGM/kokiri-forest/samples/SampleBank_0/Sample119.wav")
        )

        XCTAssertThrowsError(try AudioExtractor().verify(using: harness.verificationContext)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Sample119.wav"),
                "Unexpected error: \(error.localizedDescription)"
            )
        }
    }
}

private struct AudioHarness {
    let root: URL
    let sourceRoot: URL
    let outputRoot: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("swiftoot-audio-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        self.root = root
        self.sourceRoot = sourceRoot
        self.outputRoot = outputRoot
    }

    var verificationContext: OOTVerificationContext {
        OOTVerificationContext(content: outputRoot)
    }

    func extractionContext(sceneName: String? = nil) -> OOTExtractionContext {
        OOTExtractionContext(source: sourceRoot, output: outputRoot, sceneName: sceneName)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func seedSceneTable() throws {
        try writeJSON(
            [
                SceneTableEntry(index: 0x55, segmentName: "spot04_scene", enumName: "SCENE_KOKIRI_FOREST"),
                SceneTableEntry(index: 0x10, segmentName: "ydan_scene", enumName: "SCENE_DEKU_TREE"),
            ],
            to: outputRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("scene-table.json")
        )
    }

    func seedTrack(sequenceID: Int, soundfontName: String, metadata: String) throws {
        try writeFile(
            at: sourceRoot
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("xml", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("sequences", isDirectory: true)
                .appendingPathComponent("seq_\(sequenceID).xml"),
            contents: metadata
        )
        try writeFile(
            at: sourceRoot
                .appendingPathComponent("extracted", isDirectory: true)
                .appendingPathComponent("ntsc-1.2", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("sequences", isDirectory: true)
                .appendingPathComponent("seq_\(sequenceID).seq"),
            contents: """
            #include "aseq.h"
            #include "\(soundfontName).h"

            .startseq Sequence_\(sequenceID)

            .sequence SEQ_0000
            /* 0x0000 [0xFF                    ] */ end
            """
        )
    }

    func seedSoundfont(named name: String, sampleBankName: String, sampleNames: [String]) throws {
        let samples = sampleNames
            .map { #"        <Sample Name="\#($0)"/>"# }
            .joined(separator: "\n")
        try writeFile(
            at: sourceRoot
                .appendingPathComponent("extracted", isDirectory: true)
                .appendingPathComponent("ntsc-1.2", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("soundfonts", isDirectory: true)
                .appendingPathComponent("\(name).xml"),
            contents: """
            <Soundfont Name="\(name)" Index="0" SampleBank="$(BUILD_DIR)/assets/audio/samplebanks/\(sampleBankName).xml">
                <Samples>
            \(samples)
                </Samples>
            </Soundfont>
            """
        )
    }

    func seedSampleBank(named name: String, samples: [(String, String)]) throws {
        let sampleRows = samples
            .map { sampleName, fileName in
                #"    <Sample Name="\#(sampleName)" FileName="\#(fileName)" SampleRate="16000" BaseNote="C4"/>"#
            }
            .joined(separator: "\n")

        try writeFile(
            at: sourceRoot
                .appendingPathComponent("extracted", isDirectory: true)
                .appendingPathComponent("ntsc-1.2", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("samplebanks", isDirectory: true)
                .appendingPathComponent("\(name).xml"),
            contents: """
            <SampleBank Name="\(name)" Index="0">
            \(sampleRows)
            </SampleBank>
            """
        )
    }

    func seedSample(bankName: String, fileName: String) throws {
        try writeFile(
            at: sourceRoot
                .appendingPathComponent("extracted", isDirectory: true)
                .appendingPathComponent("ntsc-1.2", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("samples", isDirectory: true)
                .appendingPathComponent(bankName, isDirectory: true)
                .appendingPathComponent("\(fileName).wav"),
            contents: "RIFF"
        )
    }

    private func writeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
