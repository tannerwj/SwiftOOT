import SwiftUI
import AppKit
import MetalKit

public enum MetalViewInput: Sendable, Equatable {
    case confirm
    case cancel
    case moveSelection(Int)
}

public struct MetalView: NSViewRepresentable {
    private let sceneIdentity: Int
    private let scene: OOTRenderScene
    private let textureBindings: [UInt32: MTLTexture]
    private let frameStatsHandler: (SceneFrameStats) -> Void
    private let frameTickHandler: @MainActor () -> Void
    private let inputHandler: @MainActor (MetalViewInput) -> Bool

    public init(
        sceneIdentity: Int,
        scene: OOTRenderScene,
        textureBindings: [UInt32: MTLTexture] = [:],
        frameTickHandler: @escaping @MainActor () -> Void = {},
        inputHandler: @escaping @MainActor (MetalViewInput) -> Bool = { _ in false },
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) {
        self.sceneIdentity = sceneIdentity
        self.scene = scene
        self.textureBindings = textureBindings
        self.frameTickHandler = frameTickHandler
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
                frameStatsHandler: frameStatsHandler,
                frameTickHandler: frameTickHandler
            )
        } catch {
            fatalError("Failed to initialize OOTRenderer: \(error)")
        }

        let view = OrbitInputMTKView(frame: .zero, device: renderer.device)
        view.inputRenderer = renderer
        view.inputHandler = inputHandler
        renderer.configure(view)
        context.coordinator.renderer = renderer
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.setFrameStatsHandler(frameStatsHandler)
        context.coordinator.renderer?.setFrameTickHandler(frameTickHandler)
        (nsView as? OrbitInputMTKView)?.inputHandler = inputHandler
    }

    public final class Coordinator {
        fileprivate var renderer: OOTRenderer?

        public init() {}
    }
}

final class OrbitInputMTKView: MTKView {
    weak var inputRenderer: OOTRenderer?
    var inputHandler: @MainActor (MetalViewInput) -> Bool = { _ in false }

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
        switch event.keyCode {
        case 123, 126:
            if MainActor.assumeIsolated({ inputHandler(.moveSelection(-1)) }) {
                return true
            }
        case 124, 125:
            if MainActor.assumeIsolated({ inputHandler(.moveSelection(1)) }) {
                return true
            }
        case 36, 49:
            if MainActor.assumeIsolated({ inputHandler(.confirm) }) {
                return true
            }
        case 53:
            if MainActor.assumeIsolated({ inputHandler(.cancel) }) {
                return true
            }
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        var handled = false
        for character in characters {
            switch character {
            case "a":
                if MainActor.assumeIsolated({ inputHandler(.confirm) }) {
                    return true
                }
                inputRenderer?.orbitCameraController.pan(direction: .left)
                handled = true
            case "w":
                inputRenderer?.orbitCameraController.pan(direction: .up)
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
