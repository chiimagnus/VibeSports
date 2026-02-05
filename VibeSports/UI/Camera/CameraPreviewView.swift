import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.videoPreviewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.videoPreviewLayer.session = session
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
