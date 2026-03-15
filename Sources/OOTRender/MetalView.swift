import SwiftUI
import AppKit
import MetalKit

public struct MetalView: NSViewRepresentable {
    private let sceneIdentity: Int
    private let scene: OOTRenderScene
    private let textureBindings: [UInt32: MTLTexture]
    private let frameStatsHandler: (SceneFrameStats) -> Void

    public init(
        sceneIdentity: Int,
        scene: OOTRenderScene,
        textureBindings: [UInt32: MTLTexture] = [:],
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) {
        self.sceneIdentity = sceneIdentity
        self.scene = scene
        self.textureBindings = textureBindings
        self.frameStatsHandler = frameStatsHandler
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        let renderer: OOTRenderer

        do {
            renderer = try OOTRenderer(
                scene: scene,
                textureBindings: textureBindings,
                frameStatsHandler: frameStatsHandler
            )
        } catch {
            fatalError("Failed to initialize OOTRenderer: \(error)")
        }

        let view = OrbitInputMTKView(frame: .zero, device: renderer.device)
        view.inputRenderer = renderer
        renderer.configure(view)
        context.coordinator.renderer = renderer
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.setFrameStatsHandler(frameStatsHandler)
    }

    public final class Coordinator {
        fileprivate var renderer: OOTRenderer?

        public init() {}
    }
}

final class OrbitInputMTKView: MTKView {
    weak var inputRenderer: OOTRenderer?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        inputRenderer?.orbitCameraController.orbit(
            deltaX: event.deltaX,
            deltaY: event.deltaY
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func rightMouseDragged(with event: NSEvent) {
        inputRenderer?.orbitCameraController.pan(
            deltaX: event.deltaX,
            deltaY: event.deltaY
        )
    }

    override func scrollWheel(with event: NSEvent) {
        inputRenderer?.orbitCameraController.zoom(
            scrollDeltaY: event.scrollingDeltaY
        )
    }

    override func keyDown(with event: NSEvent) {
        guard handleKeyEvent(event) == false else {
            return
        }

        super.keyDown(with: event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        var handled = false
        for character in characters {
            switch character {
            case "w":
                inputRenderer?.orbitCameraController.pan(direction: .up)
                handled = true
            case "a":
                inputRenderer?.orbitCameraController.pan(direction: .left)
                handled = true
            case "s":
                inputRenderer?.orbitCameraController.pan(direction: .down)
                handled = true
            case "d":
                inputRenderer?.orbitCameraController.pan(direction: .right)
                handled = true
            default:
                continue
            }
        }

        return handled
    }
}
