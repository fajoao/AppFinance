import Foundation

// MARK: - Contrato de sincronização
//
// O app é local-first. A sincronização é opcional e vem DESLIGADA. O Core define o contrato (`SyncService`), a regra
// de conflito (último `updatedAt` vence, com tombstones para exclusões) e o coordenador. Os serviços reais ficam no
// App (`CloudKitSyncService`, atrás de `#if canImport(CloudKit)`); aqui há apenas um servidor em memória para testes.

enum SyncAccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, couldNotDetermine, temporarilyUnavailable

    var isAvailable: Bool { self == .available }

    var explanation: String {
        switch self {
        case .available: return "Conta iCloud disponível."
        case .noAccount: return "Entre na sua conta iCloud em Ajustes do iPhone para sincronizar."
        case .restricted: return "O iCloud está restrito neste aparelho."
        case .couldNotDetermine: return "Não foi possível verificar a conta iCloud."
        case .temporarilyUnavailable: return "O iCloud está temporariamente indisponível. Tente novamente."
        }
    }
}

enum SyncError: Error, Equatable, Sendable {
    case accountUnavailable(String)
    case network(String)
    case disabled
    case other(String)

    var message: String {
        switch self {
        case .accountUnavailable(let m), .network(let m), .other(let m): return m
        case .disabled: return "A sincronização está desligada."
        }
    }
}

/// Marcador opaco de "até onde já li" no servidor (equivale ao change token do CloudKit).
struct SyncToken: Codable, Sendable, Equatable { var value: String }

struct SyncPull: Sendable {
    var changes: FinanceSnapshot
    var token: SyncToken
}

protocol SyncService: Sendable {
    func accountStatus() async -> SyncAccountStatus
    /// Tudo o que mudou no servidor desde `token` (nil = tudo).
    func pull(since token: SyncToken?) async throws -> SyncPull
    /// Envia mudanças locais. O servidor aplica a mesma regra de conflito (último `updatedAt` vence).
    func push(_ changes: FinanceSnapshot) async throws
}

/// Estado persistido pelo app entre sincronizações.
struct SyncState: Codable, Sendable, Equatable {
    var token: SyncToken? = nil
    var lastSyncAt: Date? = nil
}

struct SyncReport: Sendable, Equatable {
    var pulled: Int
    var pushed: Int
    var conflictsKeptLocal: Int
    var deleted: Int
}

/// Estado exibido na tela de ajustes.
enum SyncStatus: Equatable, Sendable {
    case disabled
    case idle(lastSync: Date?)
    case syncing
    case failed(String)
}

// MARK: - Regra de conflito

struct MergeReport: Sendable, Equatable {
    /// Registros do remoto que entraram (novos ou mais recentes que o local).
    var applied = 0
    /// Conflitos em que o local era mais recente (ou igual) e foi mantido.
    var keptLocal = 0
    /// Registros removidos por tombstone.
    var deleted = 0
}

enum SyncEngine {
    private static func typeName<T: StoredEntity>(_ type: T.Type) -> String { String(describing: type) }

    private static func encoded<T: StoredEntity>(_ e: T) -> String {
        (try? String(decoding: JSONFileStore.encoder.encode(e), as: UTF8.self)) ?? ""
    }

    private static func mergeCollection<T: StoredEntity>(_ type: T.Type, local: [T], remote: [T], report: inout MergeReport) -> [T] {
        var result = local
        var index: [UUID: Int] = [:]
        for (i, e) in result.enumerated() { index[e.id] = i }
        for r in remote {
            guard let i = index[r.id] else {
                index[r.id] = result.count; result.append(r); report.applied += 1
                continue
            }
            let l = result[i]
            if r.updatedAt > l.updatedAt { result[i] = r; report.applied += 1 }
            else if r.updatedAt < l.updatedAt { report.keptLocal += 1 }
            else if r != l {
                // empate com conteúdo diferente: desempate determinístico para os dois dispositivos convergirem
                if encoded(r) > encoded(l) { result[i] = r; report.applied += 1 } else { report.keptLocal += 1 }
            }
        }
        return result
    }

    private static func applyTombstones<T: StoredEntity>(_ type: T.Type, to list: [T], tombstones: [Tombstone], report: inout MergeReport) -> [T] {
        let name = typeName(type)
        var deletedAt: [UUID: Date] = [:]
        for t in tombstones where t.entityType == name { deletedAt[t.entityId] = max(deletedAt[t.entityId] ?? .distantPast, t.deletedAt) }
        if deletedAt.isEmpty { return list }
        return list.filter { e in
            guard let when = deletedAt[e.id], when >= e.updatedAt else { return true }
            report.deleted += 1
            return false
        }
    }

    private static func process<T: StoredEntity>(_ type: T.Type, _ kp: WritableKeyPath<FinanceSnapshot, [T]>, local: FinanceSnapshot,
                                                 remote: FinanceSnapshot, tombstones: [Tombstone], into out: inout FinanceSnapshot, report: inout MergeReport) {
        let merged = mergeCollection(type, local: local[keyPath: kp], remote: remote[keyPath: kp], report: &report)
        out[keyPath: kp] = applyTombstones(type, to: merged, tombstones: tombstones, report: &report)
    }

    /// Une `remote` em `local`. Mesma regra nos dois sentidos: o `updatedAt` mais recente vence; exclusões
    /// (tombstones) vencem edições anteriores à exclusão. A comparação depende dos relógios dos aparelhos.
    static func merge(local: FinanceSnapshot, remote: FinanceSnapshot) -> (snapshot: FinanceSnapshot, report: MergeReport) {
        var report = MergeReport()
        var out = local
        out.version = max(local.version, remote.version)
        var ignored = MergeReport()
        var tombstones = mergeCollection(Tombstone.self, local: local.tombstones, remote: remote.tombstones, report: &ignored)
        tombstones.sort { $0.deletedAt < $1.deletedAt }
        out.tombstones = tombstones
        let ts = tombstones
        process(Account.self, \.accounts, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Category.self, \.categories, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Tag.self, \.tags, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Transaction.self, \.transactions, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(CreditCard.self, \.creditCards, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Invoice.self, \.invoices, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Budget.self, \.budgets, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Goal.self, \.goals, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Debt.self, \.debts, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Household.self, \.households, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(FamilyMember.self, \.familyMembers, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(GoalContribution.self, \.goalContributions, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Investment.self, \.investments, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(NetWorthSnapshot.self, \.netWorthSnapshots, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(ExpenseSplit.self, \.expenseSplits, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(SplitSettlement.self, \.splitSettlements, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(Allowance.self, \.allowances, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        process(ApprovalRequest.self, \.approvalRequests, local: local, remote: remote, tombstones: ts, into: &out, report: &report)
        return (out, report)
    }

    /// Só o que mudou depois de `since` (registros e tombstones). `since == nil` devolve tudo.
    static func changes(in snapshot: FinanceSnapshot, since: Date?) -> FinanceSnapshot {
        func newer<T: StoredEntity>(_ list: [T]) -> [T] { since.map { s in list.filter { $0.updatedAt > s } } ?? list }
        var c = FinanceSnapshot()
        c.version = snapshot.version
        c.accounts = newer(snapshot.accounts); c.categories = newer(snapshot.categories); c.tags = newer(snapshot.tags)
        c.transactions = newer(snapshot.transactions); c.creditCards = newer(snapshot.creditCards)
        c.invoices = newer(snapshot.invoices); c.budgets = newer(snapshot.budgets); c.goals = newer(snapshot.goals)
        c.debts = newer(snapshot.debts); c.households = newer(snapshot.households); c.familyMembers = newer(snapshot.familyMembers)
        c.goalContributions = newer(snapshot.goalContributions); c.investments = newer(snapshot.investments)
        c.netWorthSnapshots = newer(snapshot.netWorthSnapshots); c.expenseSplits = newer(snapshot.expenseSplits)
        c.splitSettlements = newer(snapshot.splitSettlements); c.allowances = newer(snapshot.allowances)
        c.approvalRequests = newer(snapshot.approvalRequests)
        c.tombstones = since.map { s in snapshot.tombstones.filter { $0.deletedAt > s } } ?? snapshot.tombstones
        return c
    }

    static func count(_ s: FinanceSnapshot) -> Int {
        s.accounts.count + s.categories.count + s.tags.count + s.transactions.count + s.creditCards.count + s.invoices.count
            + s.budgets.count + s.goals.count + s.debts.count + s.households.count + s.familyMembers.count
            + s.goalContributions.count + s.investments.count + s.netWorthSnapshots.count + s.expenseSplits.count
            + s.splitSettlements.count + s.allowances.count + s.approvalRequests.count + s.tombstones.count
    }
}

// MARK: - Exclusão rastreada

extension Repository {
    /// Apaga e registra um `Tombstone` (necessário para a exclusão se propagar na sincronização).
    @discardableResult
    func deleteTracked<T: StoredEntity>(_ type: T.Type, id: UUID, now: Date = Date()) throws -> Bool {
        guard try delete(type, id: id) else { return false }
        try save(Tombstone(entityType: String(describing: type), entityId: id, deletedAt: now, updatedAt: now))
        return true
    }
}

// MARK: - Coordenador

/// Orquestra uma rodada: verifica a conta, baixa mudanças, mescla no repositório local e envia as mudanças locais.
/// Em caso de falha nada é alterado localmente e o estado (token/data) não avança.
actor SyncCoordinator {
    private let repository: Repository
    private let service: SyncService
    private(set) var state: SyncState

    init(repository: Repository, service: SyncService, state: SyncState = SyncState()) {
        self.repository = repository
        self.service = service
        self.state = state
    }

    @discardableResult
    func sync(now: Date = Date()) async throws -> SyncReport {
        let status = await service.accountStatus()
        guard status.isAvailable else { throw SyncError.accountUnavailable(status.explanation) }

        let pull = try await service.pull(since: state.token)
        // Daqui até o `restore` não há `await`: a mesclagem acontece sobre uma foto local recente.
        let local = try repository.snapshot()
        let merged = SyncEngine.merge(local: local, remote: pull.changes)
        let outgoing = SyncEngine.changes(in: merged.snapshot, since: state.lastSyncAt)
        if merged.snapshot != local { try repository.restore(merged.snapshot) }

        try await service.push(outgoing)

        state = SyncState(token: pull.token, lastSyncAt: now)
        return SyncReport(pulled: merged.report.applied, pushed: SyncEngine.count(outgoing),
                          conflictsKeptLocal: merged.report.keptLocal, deleted: merged.report.deleted)
    }
}

// MARK: - Servidor em memória (testes e prévias)

/// Simula o servidor com versões incrementais (como os change tokens do CloudKit).
final class InMemorySyncService: SyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var server = FinanceSnapshot()
    private var version = 0
    private var versions: [String: Int] = [:]      // "Tipo|uuid" -> versão da última gravação
    private var statusValue: SyncAccountStatus = .available
    private var failure: SyncError?
    var status: SyncAccountStatus {
        get { lock.withLock { statusValue } }
        set { lock.withLock { statusValue = newValue } }
    }
    /// Se definido, a próxima chamada (pull ou push) lança este erro e limpa o valor.
    var failNext: SyncError? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    init() {}

    private func consumeFailure() -> SyncError? {
        lock.withLock { let e = failure; failure = nil; return e }
    }

    func accountStatus() async -> SyncAccountStatus { status }

    func pull(since token: SyncToken?) async throws -> SyncPull {
        if let e = consumeFailure() { throw e }
        return pullLocked(since: token)
    }

    private func pullLocked(since token: SyncToken?) -> SyncPull {
        lock.lock(); defer { lock.unlock() }
        let since = token.flatMap { Int($0.value) } ?? 0
        func newer<T: StoredEntity>(_ list: [T]) -> [T] {
            list.filter { (versions["\(String(describing: T.self))|\($0.id.uuidString)"] ?? 0) > since }
        }
        var c = FinanceSnapshot()
        c.accounts = newer(server.accounts); c.categories = newer(server.categories); c.tags = newer(server.tags)
        c.transactions = newer(server.transactions); c.creditCards = newer(server.creditCards); c.invoices = newer(server.invoices)
        c.budgets = newer(server.budgets); c.goals = newer(server.goals); c.debts = newer(server.debts)
        c.households = newer(server.households); c.familyMembers = newer(server.familyMembers)
        c.goalContributions = newer(server.goalContributions); c.investments = newer(server.investments)
        c.netWorthSnapshots = newer(server.netWorthSnapshots); c.expenseSplits = newer(server.expenseSplits)
        c.splitSettlements = newer(server.splitSettlements); c.allowances = newer(server.allowances)
        c.approvalRequests = newer(server.approvalRequests); c.tombstones = newer(server.tombstones)
        return SyncPull(changes: c, token: SyncToken(value: String(version)))
    }

    func push(_ changes: FinanceSnapshot) async throws {
        if let e = consumeFailure() { throw e }
        pushLocked(changes)
    }

    private func pushLocked(_ changes: FinanceSnapshot) {
        lock.lock(); defer { lock.unlock() }
        let before = server
        server = SyncEngine.merge(local: server, remote: changes).snapshot
        version += 1
        func mark<T: StoredEntity>(_ old: [T], _ new: [T]) {
            let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for e in new where oldById[e.id] != e { versions["\(String(describing: T.self))|\(e.id.uuidString)"] = version }
        }
        mark(before.accounts, server.accounts); mark(before.categories, server.categories); mark(before.tags, server.tags)
        mark(before.transactions, server.transactions); mark(before.creditCards, server.creditCards); mark(before.invoices, server.invoices)
        mark(before.budgets, server.budgets); mark(before.goals, server.goals); mark(before.debts, server.debts)
        mark(before.households, server.households); mark(before.familyMembers, server.familyMembers)
        mark(before.goalContributions, server.goalContributions); mark(before.investments, server.investments)
        mark(before.netWorthSnapshots, server.netWorthSnapshots); mark(before.expenseSplits, server.expenseSplits)
        mark(before.splitSettlements, server.splitSettlements); mark(before.allowances, server.allowances)
        mark(before.approvalRequests, server.approvalRequests); mark(before.tombstones, server.tombstones)
    }
}
