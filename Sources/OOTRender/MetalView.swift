import SwiftUI
import AppKit
import MetalKit

@MainActor
public protocol GameplayInputHandling: AnyObject {
    func handleKeyDown(_ event: NSEvent) -> Bool
    func handleKeyUp(_ event: NSEvent) -> Bool
}

public struct MetalView: NSViewRepresentable {
    private let sceneIdentity: Int
    private let scene: OOTRenderScene
    private let textureBindings: [UInt32: MTLTexture]
    private let inputHandler: (any GameplayInputHandling)?
    private let frameStatsHandler: (SceneFrameStats) -> Void

    public init(
        sceneIdentity: Int,
        scene: OOTRenderScene,
        textureBindings: [UInt32: MTLTexture] = [:],
        inputHandler: (any GameplayInputHandling)? = nil,
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) {
        self.sceneIdentity = sceneIdentity
        self.scene = scene
        self.textureBindings = textureBindings
        self.inputHandler = inputHandler
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
        view.gameplayInputHandler = inputHandler
        renderer.configure(view)
        context.coordinator.renderer = renderer
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.setFrameStatsHandler(frameStatsHandler)
        context.coordinator.renderer?.updateScene(scene, textureBindings: textureBindings)
        if let nsView = nsView as? OrbitInputMTKView {
            nsView.gameplayInputHandler = inputHandler
        }
    }

    public final class Coordinator {
        fileprivate var renderer: OOTRenderer?

        public init() {}
    }
}

final class OrbitInputMTKView: MTKView {
    weak var inputRenderer: OOTRenderer?
    weak var gameplayInputHandler: (any GameplayInputHandling)?

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
        guard gameplayInputHandler?.handleKeyDown(event) != true else {
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard gameplayInputHandler?.handleKeyUp(event) != true else {
            return
        }

        super.keyUp(with: event)
    }
}
