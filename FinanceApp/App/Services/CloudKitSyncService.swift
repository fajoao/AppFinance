import Foundation
#if canImport(CloudKit)
import CloudKit

// ============================================================================================================
// STATUS: IMPLEMENTAÇÃO PREPARADA, NÃO VERIFICADA EM UM CONTAINER REAL.
// Compila (typecheck) contra o SDK, mas nunca falou com o iCloud: o ambiente de desenvolvimento não tem Xcode,
// conta de desenvolvedor nem container. O compartilhamento por CKShare (convite de membros) é só um ESBOÇO.
// Para ligar: docs/cloudkit-setup.md (capability iCloud/CloudKit, container, entitlements e a flag CLOUDKIT_ENABLED).
// ============================================================================================================

enum CloudKitConfig {
    /// Troque pelo seu container (Signing & Capabilities > iCloud > Containers).
    static let containerID = "iCloud.com.example.financas"
    static let zoneName = "FinanceZone"
}

/// Cada entidade vira um `CKRecord` (tipo = nome do tipo Swift, nome = UUID) com o JSON do modelo em `payload` e
/// `updatedAt` em campo próprio. A regra de conflito é a do Core (`SyncEngine`): último `updatedAt` vence.
/// Usa a zona personalizada "FinanceZone" no banco privado e o token de mudanças do CloudKit como `SyncToken`.
actor CloudKitSyncService: SyncService {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var zoneReady = false

    init(containerID: String = CloudKitConfig.containerID) {
        container = CKContainer(identifier: containerID)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: SyncService

    func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .couldNotDetermine
            @unknown default: return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    func pull(since token: SyncToken?) async throws -> SyncPull {
        try await ensureZone()
        var serverToken = token.flatMap(Self.decodeToken)
        var records: [CKRecord] = []
        var more = true
        do {
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: serverToken)
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let m) = result { records.append(m.record) }
                }
                serverToken = changes.changeToken
                more = changes.moreComing
            }
        } catch {
            throw Self.map(error)
        }
        guard let finalToken = serverToken, let encoded = Self.encodeToken(finalToken) else {
            throw SyncError.other("O iCloud não devolveu o marcador de sincronização.")
        }
        return SyncPull(changes: try Self.snapshot(from: records), token: encoded)
    }

    func push(_ changes: FinanceSnapshot) async throws {
        try await ensureZone()
        let records = try Self.records(from: changes, zoneID: zoneID)
        var index = 0
        while index < records.count {
            let batch = Array(records[index..<min(index + 300, records.count)])   // limite de 400 por operação
            index += 300
            do {
                let result = try await database.modifyRecords(saving: batch, deleting: [], savePolicy: .ifServerRecordUnchanged)
                for (_, r) in result.saveResults {
                    if case .failure(let e) = r, (e as? CKError)?.code != .serverRecordChanged { throw Self.map(e) }
                    // serverRecordChanged: outro aparelho gravou antes; o próximo pull traz a versão dele e o merge decide.
                }
            } catch let e as SyncError { throw e } catch { throw Self.map(error) }
        }
    }

    // MARK: Convite de membros (ESBOÇO)

    /// Cria um compartilhamento da zona inteira para convidar outra pessoa por link/Mensagens. Para usar:
    /// apresente `UICloudSharingController(share:container:)` com o retorno. LIMITAÇÕES: (1) a pessoa convidada
    /// precisa aceitar via `CKAcceptSharesOperation` (SceneDelegate `userDidAcceptCloudKitShareWith`) e ler a zona
    /// de `container.sharedCloudDatabase`; esse segundo caminho de leitura/escrita NÃO está implementado;
    /// (2) a zona precisa ter a capacidade de compartilhamento de zona inteira. Nada disto foi testado.
    func makeHouseholdShare(title: String) async throws -> (share: CKShare, container: CKContainer) {
        try await ensureZone()
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none
        do {
            _ = try await database.modifyRecords(saving: [share], deleting: [])
        } catch {
            throw Self.map(error)
        }
        return (share, container)
    }

    // MARK: Internos

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        do { _ = try await database.save(CKRecordZone(zoneID: zoneID)) } catch { throw Self.map(error) }
        zoneReady = true
    }

    private static func map(_ error: Error) -> SyncError {
        if let e = error as? SyncError { return e }
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .network("Sem conexão com o iCloud agora. Tente novamente em instantes.")
        case .notAuthenticated:
            return .accountUnavailable(SyncAccountStatus.noAccount.explanation)
        case .quotaExceeded:
            return .other("O armazenamento do iCloud está cheio.")
        default:
            return .other("Erro do iCloud (\(ck.code.rawValue)): \(ck.localizedDescription)")
        }
    }

    private static func encodeToken(_ t: CKServerChangeToken) -> SyncToken? {
        (try? NSKeyedArchiver.archivedData(withRootObject: t, requiringSecureCoding: true)).map { SyncToken(value: $0.base64EncodedString()) }
    }

    private static func decodeToken(_ t: SyncToken) -> CKServerChangeToken? {
        Data(base64Encoded: t.value).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
    }

    // MARK: Conversão entidade <-> CKRecord

    private static func record<T: StoredEntity>(_ e: T, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let type = String(describing: T.self)
        let r = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: "\(type)-\(e.id.uuidString)", zoneID: zoneID))
        r["payload"] = try JSONFileStore.encoder.encode(e) as CKRecordValue
        r["updatedAt"] = e.updatedAt as CKRecordValue
        return r
    }

    private static func records(from s: FinanceSnapshot, zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        var out: [CKRecord] = []
        func add<T: StoredEntity>(_ list: [T]) throws { for e in list { out.append(try record(e, zoneID: zoneID)) } }
        try add(s.accounts); try add(s.categories); try add(s.tags); try add(s.transactions); try add(s.creditCards)
        try add(s.invoices); try add(s.budgets); try add(s.goals); try add(s.debts); try add(s.households)
        try add(s.familyMembers); try add(s.goalContributions); try add(s.investments); try add(s.netWorthSnapshots)
        try add(s.expenseSplits); try add(s.splitSettlements); try add(s.allowances); try add(s.approvalRequests)
        try add(s.tombstones)
        return out
    }

    private static func snapshot(from records: [CKRecord]) throws -> FinanceSnapshot {
        var s = FinanceSnapshot()
        func decode<T: StoredEntity>(_ type: T.Type, _ r: CKRecord) throws -> T? {
            guard r.recordType == String(describing: type), let data = r["payload"] as? Data else { return nil }
            return try JSONFileStore.decoder.decode(type, from: data)
        }
        for r in records {
            if let v = try decode(Account.self, r) { s.accounts.append(v) }
            else if let v = try decode(Category.self, r) { s.categories.append(v) }
            else if let v = try decode(Tag.self, r) { s.tags.append(v) }
            else if let v = try decode(Transaction.self, r) { s.transactions.append(v) }
            else if let v = try decode(CreditCard.self, r) { s.creditCards.append(v) }
            else if let v = try decode(Invoice.self, r) { s.invoices.append(v) }
            else if let v = try decode(Budget.self, r) { s.budgets.append(v) }
            else if let v = try decode(Goal.self, r) { s.goals.append(v) }
            else if let v = try decode(Debt.self, r) { s.debts.append(v) }
            else if let v = try decode(Household.self, r) { s.households.append(v) }
            else if let v = try decode(FamilyMember.self, r) { s.familyMembers.append(v) }
            else if let v = try decode(GoalContribution.self, r) { s.goalContributions.append(v) }
            else if let v = try decode(Investment.self, r) { s.investments.append(v) }
            else if let v = try decode(NetWorthSnapshot.self, r) { s.netWorthSnapshots.append(v) }
            else if let v = try decode(ExpenseSplit.self, r) { s.expenseSplits.append(v) }
            else if let v = try decode(SplitSettlement.self, r) { s.splitSettlements.append(v) }
            else if let v = try decode(Allowance.self, r) { s.allowances.append(v) }
            else if let v = try decode(ApprovalRequest.self, r) { s.approvalRequests.append(v) }
            else if let v = try decode(Tombstone.self, r) { s.tombstones.append(v) }
        }
        return s
    }
}
#endif

/// Cria o serviço de sincronização do build. Retorna nil (sincronização indisponível) a menos que o projeto defina
/// a condição de compilação `CLOUDKIT_ENABLED` depois de configurar a capability (ver docs/cloudkit-setup.md):
/// instanciar `CKContainer` sem o entitlement derruba o app.
func makeSyncService() -> SyncService? {
    #if CLOUDKIT_ENABLED && canImport(CloudKit)
    return CloudKitSyncService()
    #else
    return nil
    #endif
}
