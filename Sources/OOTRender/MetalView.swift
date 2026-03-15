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
    private let timeOfDay: Double
    private let textureBindings: [UInt32: MTLTexture]
    private let inputHandler: (any GameplayInputHandling)?
    private let gameplayCameraConfiguration: GameplayCameraConfiguration?
    private let frameStatsHandler: (SceneFrameStats) -> Void

    public init(
        sceneIdentity: Int,
        scene: OOTRenderScene,
        timeOfDay: Double,
        textureBindings: [UInt32: MTLTexture] = [:],
        inputHandler: (any GameplayInputHandling)? = nil,
        gameplayCameraConfiguration: GameplayCameraConfiguration? = nil,
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) {
        self.sceneIdentity = sceneIdentity
        self.scene = scene
        self.timeOfDay = timeOfDay
        self.textureBindings = textureBindings
        self.inputHandler = inputHandler
        self.gameplayCameraConfiguration = gameplayCameraConfiguration
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
                gameplayCameraConfiguration: gameplayCameraConfiguration,
                frameStatsHandler: frameStatsHandler
            )
        } catch {
            fatalError("Failed to initialize OOTRenderer: \(error)")
        }

        let view = OrbitInputMTKView(frame: .zero, device: renderer.device)
        view.inputRenderer = renderer
        view.gameplayInputHandler = inputHandler
        renderer.setTimeOfDay(timeOfDay)
        renderer.configure(view)
        context.coordinator.renderer = renderer
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.setFrameStatsHandler(frameStatsHandler)
        context.coordinator.renderer?.updateScene(scene, textureBindings: textureBindings)
        context.coordinator.renderer?.updateGameplayCameraConfiguration(gameplayCameraConfiguration)
        context.coordinator.renderer?.setTimeOfDay(timeOfDay)
        nsView.clearColor = context.coordinator.renderer?.clearColorForCurrentEnvironment() ?? nsView.clearColor
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
        inputRenderer?.handlePrimaryDrag(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func rightMouseDragged(with event: NSEvent) {
        inputRenderer?.handleSecondaryDrag(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    override func scrollWheel(with event: NSEvent) {
        inputRenderer?.handleScroll(scrollDeltaY: event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        guard gameplayInputHandler?.handleKeyDown(event) != true else {
            return
        }

        guard handleCameraKeyEvent(event) == false else {
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

    private func handleCameraKeyEvent(_ event: NSEvent) -> Bool {
        if
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift]),
            event.charactersIgnoringModifiers?.lowercased() == "c"
        {
            inputRenderer?.toggleDebugCamera()
            return true
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        var handled = false
        for character in characters {
            switch character {
            case "z":
                inputRenderer?.snapGameplayCameraBehindPlayer()
                handled = true
            default:
                continue
            }
        }

        return handled
    }
}
