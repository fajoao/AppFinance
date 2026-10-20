import Foundation

/// Comprovantes (fotos) ficam em `Application Support/FinanceApp/Attachments`. O lançamento guarda só o caminho
/// RELATIVO (`Transaction.attachmentPath`), então o backup/sincronização não depende do caminho do aparelho.
struct AttachmentStorage: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    static func standard(fileManager: FileManager = .default) -> AttachmentStorage {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return AttachmentStorage(directory: base.appendingPathComponent("FinanceApp", isDirectory: true))
    }

    private var folder: URL { directory.appendingPathComponent("Attachments", isDirectory: true) }

    /// Grava e devolve o caminho relativo ("Attachments/<uuid>.jpg").
    func save(_ data: Data, fileExtension: String = "jpg") throws -> String {
        let ext = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let name = "\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return "Attachments/\(name)"
    }

    /// nil se o caminho tenta sair da pasta de anexos (ex.: "../data.json" vindo de dados sincronizados).
    func url(for path: String) -> URL? {
        guard path.hasPrefix("Attachments/"), !path.contains(".."), !path.contains("\\") else { return nil }
        let name = String(path.dropFirst("Attachments/".count))
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return folder.appendingPathComponent(name)
    }

    func load(_ path: String) -> Data? { url(for: path).flatMap { try? Data(contentsOf: $0) } }

    func exists(_ path: String) -> Bool { url(for: path).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    /// Apaga todos os comprovantes (usado em "Apagar todos os dados").
    func removeAll() { try? FileManager.default.removeItem(at: folder) }

    func remove(_ path: String) {
        if let u = url(for: path) { try? FileManager.default.removeItem(at: u) }
    }
}
