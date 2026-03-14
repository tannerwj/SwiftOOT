import ArgumentParser
import Foundation
import OOTExtractSupport

@main
struct OOTExtractCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ootextractcli",
        abstract: "Build-time content extraction tools for SwiftOOT.",
        subcommands: [
            Extract.self,
            Verify.self,
        ]
    )
}
extension OOTExtractCLI {
    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Extracts content from a zeldaret/oot checkout into SwiftOOT content output."
        )

        @Option(help: "Path to the extracted zeldaret/oot source checkout.")
        var source: String

        @Option(help: "Path where extracted SwiftOOT content should be written.")
        var output: String

        @Option(help: "Optional scene name to limit extraction to.")
        var scene: String?

        func run() throws {
            let extractor = OOTContentExtractor()
            try extractor.extract(
                from: URL(fileURLWithPath: source),
                to: URL(fileURLWithPath: output),
                scene: scene
            )
        }
    }

    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Verifies previously extracted SwiftOOT content."
        )

        @Option(help: "Path to the extracted SwiftOOT content directory.")
        var content: String

        func run() throws {
            let extractor = OOTContentExtractor()
            try extractor.verify(contentAt: URL(fileURLWithPath: content))
        }
    }
}
