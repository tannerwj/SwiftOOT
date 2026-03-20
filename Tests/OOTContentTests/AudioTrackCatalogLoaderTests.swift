import Foundation
import XCTest
import OOTContent
import OOTDataModel

final class AudioTrackCatalogLoaderTests: XCTestCase {
    func testAudioTrackCatalogLoaderReadsManifestFromAudioDirectory() throws {
        let fixture = try AudioTrackCatalogFixture()
        defer { fixture.cleanup() }

        let catalog = try AudioTrackCatalogLoader(contentRoot: fixture.contentRoot).loadAudioTrackCatalog()

        XCTAssertEqual(catalog.tracks.map(\.id), ["kokiri-forest", "title-theme"])
        XCTAssertEqual(catalog.sceneBindings.map(\.trackID), ["kokiri-forest"])
    }
}

private struct AudioTrackCatalogFixture {
    let contentRoot: URL
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioTrackCatalogFixture-\(UUID().uuidString)", isDirectory: true)
        contentRoot = root

        let manifestURL = contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("bgm-tracks.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let catalog = AudioTrackCatalog(
            tracks: [
                AudioTrackManifest(
                    id: "kokiri-forest",
                    title: "Kokiri Forest",
                    kind: .bgm,
                    sequenceID: 60,
                    sequenceEnumName: "NA_BGM_KOKIRI",
                    assetDirectory: "Audio/BGM/kokiri-forest",
                    sequencePath: "Audio/BGM/kokiri-forest/sequence.seq",
                    sequenceMetadataPath: "Audio/BGM/kokiri-forest/sequence.xml",
                    soundfontPaths: ["Audio/BGM/kokiri-forest/soundfonts/Soundfont_15.xml"],
                    sampleBankPaths: ["Audio/BGM/kokiri-forest/samplebanks/SampleBank_0.xml"],
                    samplePaths: ["Audio/BGM/kokiri-forest/samples/Sample119.wav"]
                ),
                AudioTrackManifest(
                    id: "title-theme",
                    title: "Title Theme",
                    kind: .bgm,
                    sequenceID: 30,
                    sequenceEnumName: "NA_BGM_TITLE",
                    assetDirectory: "Audio/BGM/title-theme",
                    sequencePath: "Audio/BGM/title-theme/sequence.seq",
                    sequenceMetadataPath: "Audio/BGM/title-theme/sequence.xml",
                    soundfontPaths: ["Audio/BGM/title-theme/soundfonts/Soundfont_15.xml"],
                    sampleBankPaths: ["Audio/BGM/title-theme/samplebanks/SampleBank_0.xml"],
                    samplePaths: ["Audio/BGM/title-theme/samples/Sample119.wav"]
                ),
            ],
            sceneBindings: [
                AudioSceneBinding(
                    sceneName: "spot04",
                    sceneID: 0x55,
                    sequenceID: 60,
                    sequenceEnumName: "NA_BGM_KOKIRI",
                    trackID: "kokiri-forest"
                ),
            ]
        )

        try JSONEncoder().encode(catalog).write(to: manifestURL, options: .atomic)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
