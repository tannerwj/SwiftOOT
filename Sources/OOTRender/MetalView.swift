import SwiftUI
import MetalKit

public struct MetalView: NSViewRepresentable {
    public init() {}

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        let renderer: OOTRenderer

        do {
            renderer = try OOTRenderer()
        } catch {
            fatalError("Failed to initialize OOTRenderer: \(error)")
        }

        let view = MTKView(frame: .zero, device: renderer.device)
        renderer.configure(view)
        context.coordinator.renderer = renderer
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {}

    public final class Coordinator {
        fileprivate var renderer: OOTRenderer?

        public init() {}
    }
}
