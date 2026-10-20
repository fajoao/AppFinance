import Foundation

/// Persistência síncrona e genérica por tipo de entidade. Implementações: InMemoryStore e JSONFileStore.
/// `save` é "upsert" por `id`. Quem chama atualiza `updatedAt` (use `touch`) antes de salvar.
protocol Repository: Sendable {
    func all<T: StoredEntity>(_ type: T.Type) throws -> [T]
    func get<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> T?
    func save<T: StoredEntity>(_ entity: T) throws
    func saveAll<T: StoredEntity>(_ entities: [T]) throws
    /// Remove e retorna true se existia.
    @discardableResult func delete<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> Bool
    /// Cópia completa (backup).
    func snapshot() throws -> FinanceSnapshot
    /// Substitui tudo (restauração).
    func restore(_ snapshot: FinanceSnapshot) throws
}

extension Repository {
    func save<T: StoredEntity>(touching entity: T, now: Date = Date()) throws {
        var e = entity
        e.updatedAt = now
        try save(e)
    }
}

final class InMemoryStore: Repository, @unchecked Sendable {
    private var data: FinanceSnapshot
    private let lock = NSLock()

    init(_ initial: FinanceSnapshot = FinanceSnapshot()) { data = initial }

    private func locked<R>(_ body: () throws -> R) rethrows -> R { lock.lock(); defer { lock.unlock() }; return try body() }

    func all<T: StoredEntity>(_ type: T.Type) throws -> [T] { locked { data[keyPath: T.storage] } }

    func get<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> T? { locked { data[keyPath: T.storage].first { $0.id == id } } }

    func save<T: StoredEntity>(_ entity: T) throws { try saveAll([entity]) }

    func saveAll<T: StoredEntity>(_ entities: [T]) throws {
        locked {
            for e in entities {
                if let i = data[keyPath: T.storage].firstIndex(where: { $0.id == e.id }) { data[keyPath: T.storage][i] = e }
                else { data[keyPath: T.storage].append(e) }
            }
        }
    }

    @discardableResult func delete<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> Bool {
        locked {
            guard let i = data[keyPath: T.storage].firstIndex(where: { $0.id == id }) else { return false }
            data[keyPath: T.storage].remove(at: i)
            return true
        }
    }

    func snapshot() throws -> FinanceSnapshot { locked { data } }
    func restore(_ snapshot: FinanceSnapshot) throws { locked { data = snapshot } }
}

/// Armazena tudo em um arquivo JSON. Escritas atômicas (arquivo temporário + rename);
/// se a escrita falhar, o estado em memória é revertido e o erro é propagado.
final class JSONFileStore: Repository, @unchecked Sendable {
    let url: URL
    private let memory: InMemoryStore
    private let writeLock = NSLock()

    /// Carrega o arquivo se existir (erro se estiver corrompido); cria vazio se não existir.
    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let snap = try Self.decoder.decode(FinanceSnapshot.self, from: data)
            memory = InMemoryStore(snap)
        } else {
            memory = InMemoryStore()
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .deferredToDate // segundos desde 2001 (Double): round-trip exato
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }

    private func mutate(_ body: () throws -> Void) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        let before = try memory.snapshot()
        try body()
        do { try persist(try memory.snapshot()) }
        catch { try? memory.restore(before); throw error }
    }

    private func persist(_ snap: FinanceSnapshot) throws {
        let data = try Self.encoder.encode(snap)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func all<T: StoredEntity>(_ type: T.Type) throws -> [T] { try memory.all(type) }
    func get<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> T? { try memory.get(type, id: id) }
    func save<T: StoredEntity>(_ entity: T) throws { try mutate { try memory.save(entity) } }
    func saveAll<T: StoredEntity>(_ entities: [T]) throws { try mutate { try memory.saveAll(entities) } }

    @discardableResult func delete<T: StoredEntity>(_ type: T.Type, id: UUID) throws -> Bool {
        var removed = false
        try mutate { removed = try memory.delete(type, id: id) }
        return removed
    }

    func snapshot() throws -> FinanceSnapshot { try memory.snapshot() }
    func restore(_ snapshot: FinanceSnapshot) throws { try mutate { try memory.restore(snapshot) } }
}
