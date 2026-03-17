import SwiftUI
import AppKit
import MetalKit

@MainActor
public protocol GameplayInputSyncing: AnyObject {
    func sync(frame: Int)
}

@MainActor
public protocol GameplayInputHandling: GameplayInputSyncing {
    func handleKeyDown(_ event: NSEvent) -> Bool
    func handleKeyUp(_ event: NSEvent) -> Bool
    func updateMovementReferenceYaw(_ yaw: Float?)
}

public struct MetalView: NSViewRepresentable {
    private let sceneIdentity: Int
    private let scene: OOTRenderScene
    private let timeOfDay: Double
    private let textureBindings: [UInt32: MTLTexture]
    private let renderSettings: RenderSettings
    private let inputHandler: (any GameplayInputHandling)?
    private let toggleAllXRayLayers: () -> Void
    private let gameplayCameraConfiguration: GameplayCameraConfiguration?
    private let frameStatsHandler: (SceneFrameStats) -> Void

    public init(
        sceneIdentity: Int,
        scene: OOTRenderScene,
        timeOfDay: Double,
        textureBindings: [UInt32: MTLTexture] = [:],
        renderSettings: RenderSettings = RenderSettings(),
        inputHandler: (any GameplayInputHandling)? = nil,
        toggleAllXRayLayers: @escaping () -> Void = {},
        gameplayCameraConfiguration: GameplayCameraConfiguration? = nil,
        frameStatsHandler: @escaping (SceneFrameStats) -> Void = { _ in }
    ) {
        self.sceneIdentity = sceneIdentity
        self.scene = scene
        self.timeOfDay = timeOfDay
        self.textureBindings = textureBindings
        self.renderSettings = renderSettings
        self.inputHandler = inputHandler
        self.toggleAllXRayLayers = toggleAllXRayLayers
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
                renderSettings: renderSettings,
                gameplayCameraConfiguration: gameplayCameraConfiguration,
                frameStatsHandler: frameStatsHandler
            )
        } catch {
            fatalError("Failed to initialize OOTRenderer: \(error)")
        }

        let view = OrbitInputMTKView(frame: .zero, device: renderer.device)
        view.inputRenderer = renderer
        view.gameplayInputHandler = inputHandler
        view.toggleAllXRayLayers = toggleAllXRayLayers
        renderer.setTimeOfDay(timeOfDay)
        renderer.configure(view)
        context.coordinator.renderer = renderer
        inputHandler?.updateMovementReferenceYaw(renderer.currentGameplayMovementYaw())
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.setFrameStatsHandler(frameStatsHandler)
        context.coordinator.renderer?.updateScene(scene, textureBindings: textureBindings)
        context.coordinator.renderer?.updateGameplayCameraConfiguration(gameplayCameraConfiguration)
        context.coordinator.renderer?.updateRenderSettings(renderSettings)
        context.coordinator.renderer?.refreshPresentationConfiguration(for: nsView)
        context.coordinator.renderer?.setTimeOfDay(timeOfDay)
        nsView.clearColor = context.coordinator.renderer?.clearColorForCurrentEnvironment() ?? nsView.clearColor
        if let nsView = nsView as? OrbitInputMTKView {
            nsView.gameplayInputHandler = inputHandler
            nsView.toggleAllXRayLayers = toggleAllXRayLayers
        }
        inputHandler?.updateMovementReferenceYaw(context.coordinator.renderer?.currentGameplayMovementYaw())
    }

    public final class Coordinator {
        fileprivate var renderer: OOTRenderer?

        public init() {}
    }
}

final class OrbitInputMTKView: MTKView {
    weak var inputRenderer: OOTRenderer?
    weak var gameplayInputHandler: (any GameplayInputHandling)?
    var toggleAllXRayLayers: (() -> Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updatePresentationObservers()
        inputRenderer?.refreshPresentationConfiguration(for: self)
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

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        inputRenderer?.refreshPresentationConfiguration(for: self)
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
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift]) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                inputRenderer?.toggleDebugCamera()
                return true
            case "x":
                toggleAllXRayLayers?()
                return true
            default:
                break
            }
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

    private func updatePresentationObservers() {
        NotificationCenter.default.removeObserver(self)

        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePresentationNotification(_:)),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePresentationNotification(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc
    private func handlePresentationNotification(_ notification: Notification) {
        inputRenderer?.refreshPresentationConfiguration(for: self)
    }
}
