import AppKit
import Foundation
import OOTCore
import OOTRender

struct DeveloperHarnessStateCapture: Codable, Sendable, Equatable {
    struct RenderSnapshot: Codable, Sendable, Equatable {
        var width: Int
        var height: Int
        var roomCount: Int
        var vertexCount: Int
        var triangleCount: Int
        var drawCallCount: Int

        init(width: Int, height: Int, frameStats: SceneFrameStats) {
            self.width = width
            self.height = height
            roomCount = frameStats.roomCount
            vertexCount = frameStats.vertexCount
            triangleCount = frameStats.triangleCount
            drawCallCount = frameStats.drawCallCount
        }
    }

    var runtime: DeveloperRuntimeStateSnapshot
    var render: RenderSnapshot?
}

enum DeveloperHarnessCaptureError: LocalizedError {
    case invalidImageData
    case invalidRuntimeState(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Failed to encode the rendered frame as PNG."
        case .invalidRuntimeState(let message):
            return message
        }
    }
}

enum DeveloperHarnessCaptureWriter {
    static func writeFrameCapture(
        _ capture: RenderedSceneCapture,
        to url: URL
    ) throws {
        try ensureParentDirectory(for: url)

        let imageData = Data(capture.pixelsBGRA)
        guard
            let provider = CGDataProvider(data: imageData as CFData),
            let image = CGImage(
                width: capture.width,
                height: capture.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: capture.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw DeveloperHarnessCaptureError.invalidImageData
        }

        let representation = NSBitmapImageRep(cgImage: image)
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw DeveloperHarnessCaptureError.invalidImageData
        }

        try pngData.write(to: url, options: .atomic)
    }

    static func writeStateCapture(
        runtimeSnapshot: DeveloperRuntimeStateSnapshot,
        renderCapture: RenderedSceneCapture?,
        to url: URL
    ) throws {
        try ensureParentDirectory(for: url)

        let stateCapture = DeveloperHarnessStateCapture(
            runtime: runtimeSnapshot,
            render: renderCapture.map {
                .init(
                    width: $0.width,
                    height: $0.height,
                    frameStats: $0.frameStats
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stateCapture)
        try data.write(to: url, options: .atomic)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
