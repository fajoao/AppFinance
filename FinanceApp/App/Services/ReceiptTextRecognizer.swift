import Foundation
#if canImport(Vision)
@preconcurrency import Vision
import ImageIO

/// Reconhece texto em foto de cupom, comprovante ou boleto com o Vision (no aparelho, sem enviar nada a servidores).
/// Devolve o texto em linhas, de cima para baixo; a interpretação (valor, data, estabelecimento) é do Core
/// (`ReceiptTextExtractor`). Não há correção de linguagem para não alterar dígitos de boletos.
enum ReceiptTextRecognizer {
    enum RecognitionError: Error, Equatable { case invalidImage, noText }

    static func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw RecognitionError.invalidImage }
        var orientation = CGImagePropertyOrientation.up
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let raw = props[kCGImagePropertyOrientation] as? UInt32, let o = CGImagePropertyOrientation(rawValue: raw) { orientation = o }
        return try await recognize(cgImage: image, orientation: orientation)
    }

    static func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Ordem de leitura: de cima para baixo (a origem do Vision é o canto inferior esquerdo), depois da esquerda para a direita.
                let sorted = observations.sorted {
                    abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.008 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                if lines.isEmpty { continuation.resume(throwing: RecognitionError.noText) }
                else { continuation.resume(returning: lines.joined(separator: "\n")) }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR"]
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
#endif
