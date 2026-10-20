import SwiftUI
#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// Pré-visualização da câmera para ler o QR Code. Só iOS; no macOS (typecheck) esta View não existe.
struct QRCameraView: UIViewRepresentable {
    let controller: QRCaptureController

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
#endif
