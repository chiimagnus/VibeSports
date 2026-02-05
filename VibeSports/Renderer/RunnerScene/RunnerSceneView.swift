import SceneKit
import SwiftUI

struct RunnerSceneView: NSViewRepresentable {
    @ObservedObject var renderer: RunnerSceneRenderer

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(white: 0.05, alpha: 1)
        view.allowsCameraControl = false
        view.rendersContinuously = true
        renderer.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        renderer.attach(to: nsView)
    }
}

