import Foundation
#if canImport(AVFoundation)
@preconcurrency import AVFoundation

/// Leitor de QR Code com a câmera (AVFoundation). Precisa de `NSCameraUsageDescription` no Info.plist.
/// A sessão roda numa fila própria; `onCode` é chamado na fila principal com o primeiro QR lido.
final class QRCaptureController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum SetupError: Error, Equatable { case noCamera, cannotConfigure }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "financeapp.qr-capture")
    private var configured = false
    private var delivered = false
    var onCode: (@Sendable (String) -> Void)?

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var isDenied: Bool { [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) }
    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { throw SetupError.noCamera }
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw SetupError.cannotConfigure }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
        configured = true
    }

    func start() {
        delivered = false
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue else { return }
        delivered = true
        onCode?(code)
    }
}
#endif
