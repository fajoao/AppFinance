import Foundation
import Observation

/// Estado da tela de Open Finance. Sem provedor (`provider == nil`) nada funciona: é o caso do app de produção,
/// porque nenhum provedor real está integrado (ver docs/open-finance.md). Com `MockBankProvider` serve a UI e os testes.
@MainActor @Observable
final class OpenFinanceModel {
    @ObservationIgnored var provider: (any BankConnectionProvider)?
    private(set) var institutions: [BankInstitution] = []
    private(set) var connection: BankConnection?
    private(set) var accounts: [BankAccount] = []
    private(set) var lastOutcome: BankSyncOutcome?
    private(set) var isWorking = false
    private(set) var errorText: String?

    init(provider: (any BankConnectionProvider)? = nil) { self.provider = provider }

    var isAvailable: Bool { provider != nil }

    private func run(_ body: () async throws -> Void) async {
        isWorking = true; errorText = nil
        defer { isWorking = false }
        do { try await body() }
        catch let e as BankProviderError { errorText = e.message }
        catch { errorText = "Algo deu errado: \(error.localizedDescription)" }
    }

    func loadInstitutions() async {
        guard let provider else { errorText = BankProviderError.notConfigured.message; return }
        await run { institutions = try await provider.institutions() }
    }

    func connect(institutionId: String, consent: ConsentRequest = ConsentRequest()) async {
        guard let provider else { errorText = BankProviderError.notConfigured.message; return }
        await run {
            let c = try await provider.beginConnection(institutionId: institutionId, consent: consent)
            connection = c
            if c.status == .active { accounts = try await provider.accounts(connectionId: c.id) }
        }
    }

    /// Importa as transações dos últimos `days` dias para contas locais (cria uma por conta do banco, se ainda não existir).
    /// Não duplica: o `externalId` impede reimportar o que já foi trazido.
    func syncNow(into store: AppStore, days: Int = 30) async {
        guard let provider, let conn = connection else { errorText = BankProviderError.consentRequired.message; return }
        await run {
            let remote = try await provider.accounts(connectionId: conn.id)
            accounts = remote
            var links: [String: UUID] = [:]
            for r in remote where r.kind == .checking || r.kind == .savings {
                let name = "\(conn.institutionName) · \(r.name)"
                if let existing = store.accounts.first(where: { $0.name == name && !$0.isArchived }) { links[r.id] = existing.id; continue }
                let type: AccountType = r.kind == .savings ? .savings : .checking
                try store.addAccount(name: name, type: type, balance: 0)
                if let created = store.accounts.first(where: { $0.name == name }) { links[r.id] = created.id }
            }
            let outcome = try await BankSyncService.sync(provider: provider, connection: conn, accountLinks: links, existing: store.transactions,
                                                         from: FinanceCalendar.addDays(store.today, -days), to: store.today, today: store.today,
                                                         suggester: store.suggester(for: .expense))
            try store.importProviderTransactions(outcome.imported)
            lastOutcome = outcome
        }
    }

    /// Revoga o consentimento no provedor. Os lançamentos já importados continuam no app.
    func revoke() async {
        guard let provider, let conn = connection else { return }
        await run {
            try await provider.revokeConsent(connectionId: conn.id)
            connection = try await provider.connection(id: conn.id)
            accounts = []
        }
    }

    func forgetConnection() { connection = nil; accounts = []; lastOutcome = nil; errorText = nil }
}
