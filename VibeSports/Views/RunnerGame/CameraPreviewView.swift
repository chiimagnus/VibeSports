import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var isMirroredHorizontally: Bool = false

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.videoPreviewLayer.session = session
        applyMirroring(to: view.videoPreviewLayer)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.videoPreviewLayer.session = session
        applyMirroring(to: nsView.videoPreviewLayer)
    }

    private func applyMirroring(to layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection else { return }
        guard connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirroredHorizontally
    }
}

final class PreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        previewLayer
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        previewLayer
    }

    override func updateLayer() {
        super.updateLayer()
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
}
