import Foundation

// Open Finance Brasil: CONTRATO e mapeamento. NÃO há integração real aqui.
//
// Um provedor real (agregador regulado ou instituição transmissora de dados) exige contrato, credenciais e um backend:
// o `client_secret` e os tokens de acesso nunca podem ficar no app. O desenho recomendado está em docs/open-finance.md.
// Este arquivo define o que o app espera de QUALQUER provedor (`BankConnectionProvider`), converte as transações do
// provedor em `Transaction` sem duplicar (por `externalId`) e traz um `MockBankProvider` com dados FICTÍCIOS para a UI e os testes.

// MARK: - Modelos do provedor

struct BankInstitution: Identifiable, Sendable, Equatable {
    var id: String
    var name: String
}

/// O que a pessoa autoriza. Peça só o necessário (princípio da minimização da LGPD).
enum ConsentScope: String, Codable, Sendable, CaseIterable {
    case accountsRead, balancesRead, transactionsRead

    var displayName: String {
        switch self {
        case .accountsRead: return "Ver suas contas (nome e tipo)"
        case .balancesRead: return "Ver saldos"
        case .transactionsRead: return "Ver transações (extrato)"
        }
    }
}

struct ConsentRequest: Sendable, Equatable {
    /// Os consentimentos do Open Finance valem no máximo 12 meses.
    static let maxDurationDays = 365

    var scopes: Set<ConsentScope>
    var durationDays: Int
    var purpose: String

    init(scopes: Set<ConsentScope> = [.accountsRead, .balancesRead, .transactionsRead], durationDays: Int = 90,
         purpose: String = "Importar contas e transações para o seu controle financeiro pessoal") {
        self.scopes = scopes
        self.durationDays = min(max(durationDays, 1), Self.maxDurationDays)
        self.purpose = purpose
    }
}

enum ConnectionStatus: String, Codable, Sendable, Equatable {
    case pending, active, expired, revoked
    var displayName: String {
        switch self {
        case .pending: return "Aguardando autorização"
        case .active: return "Ativa"
        case .expired: return "Expirada"
        case .revoked: return "Revogada"
        }
    }
}

struct BankConnection: Identifiable, Sendable, Equatable {
    var id: String
    var institutionId: String
    var institutionName: String
    var status: ConnectionStatus
    var grantedScopes: Set<ConsentScope>
    var createdAt: Date
    var expiresAt: Date
    /// Em provedores reais o consentimento é dado no app/site do banco: o app abre esta URL e depois consulta `connection(id:)`.
    var authorizationURL: URL?

    func isUsable(on date: Date) -> Bool { status == .active && !FinanceCalendar.isBeforeDay(expiresAt, date) }
}

enum BankAccountKind: String, Codable, Sendable, Equatable { case checking, savings, creditCard, investment }

struct BankAccount: Identifiable, Sendable, Equatable {
    var id: String
    var connectionId: String
    var name: String
    var kind: BankAccountKind
    var currency: String
    /// Saldo informado pelo banco (referência; o app não substitui seus cálculos por ele).
    var balance: Decimal?
}

/// Transação como o provedor entrega. O valor vem COM SINAL (saída negativa) e em `Decimal`: nunca `Double`.
struct ProviderTransaction: Sendable, Equatable {
    var id: String
    var accountId: String
    var postedAt: Date
    var description: String
    var amount: Decimal
    var currency: String = "BRL"
    /// Ainda não efetivada. O app não importa pendentes (podem mudar de valor ou sumir).
    var isPending: Bool = false
}

enum BankProviderError: Error, Equatable, Sendable {
    case notConfigured       // nenhum provedor neste build
    case consentRequired     // conexão ainda não autorizada
    case consentRevoked
    case consentExpired
    case notFound
    case unavailable         // banco ou provedor fora do ar

    var message: String {
        switch self {
        case .notConfigured: return "Nenhum provedor de Open Finance está configurado neste app."
        case .consentRequired: return "A autorização no banco ainda não foi concluída."
        case .consentRevoked: return "O consentimento foi revogado. Conecte o banco de novo para importar."
        case .consentExpired: return "O consentimento expirou. Renove a autorização no banco."
        case .notFound: return "Conexão ou conta não encontrada."
        case .unavailable: return "O banco ou o provedor está indisponível agora. Tente mais tarde."
        }
    }
}

// MARK: - Contrato

/// O que o app espera de um provedor de Open Finance. A implementação real fala com o SEU backend (que guarda as
/// credenciais e os tokens), nunca direto com o provedor. Todas as chamadas são assíncronas e podem falhar.
protocol BankConnectionProvider: Sendable {
    /// Identificador curto e estável do provedor (entra no `externalId` das transações).
    var providerId: String { get }
    var displayName: String { get }

    func institutions() async throws -> [BankInstitution]
    /// Inicia o consentimento. Pode devolver `.pending` com `authorizationURL`; o app acompanha com `connection(id:)`.
    func beginConnection(institutionId: String, consent: ConsentRequest) async throws -> BankConnection
    func connection(id: String) async throws -> BankConnection
    func accounts(connectionId: String) async throws -> [BankAccount]
    func transactions(connectionId: String, accountId: String, from: Date, to: Date) async throws -> [ProviderTransaction]
    /// Revoga o consentimento no provedor. Depois disso nenhuma consulta pode funcionar.
    func revokeConsent(connectionId: String) async throws
}

// MARK: - Mapeamento para Transaction

struct SkippedProviderTransaction: Sendable, Equatable {
    enum Reason: String, Sendable, Equatable { case pending, foreignCurrency, zeroAmount, missingId }
    var transaction: ProviderTransaction
    var reason: Reason
}

struct BankMappingResult: Sendable, Equatable {
    /// Novos lançamentos prontos para salvar.
    var imported: [Transaction] = []
    /// Já importados antes (mesmo `externalId`) ou repetidos no mesmo lote.
    var duplicates: [ProviderTransaction] = []
    /// Parecem um lançamento manual existente (mesmo dia, valor e descrição parecida). NÃO são importados: a pessoa decide.
    var probableDuplicates: [ProviderTransaction] = []
    var skipped: [SkippedProviderTransaction] = []
}

enum BankTransactionMapper {
    /// Fuso das datas dos bancos brasileiros.
    static let bankTimeZone = TimeZone(identifier: "America/Sao_Paulo")!

    static func externalId(providerId: String, transactionId: String) -> String { "of:\(providerId):\(transactionId)" }

    static func isOpenFinanceId(_ externalId: String?) -> Bool { externalId?.hasPrefix("of:") == true }

    /// Converte transações do provedor em lançamentos. Deduplica por `externalId` (contra o que já existe e dentro do lote).
    /// Importa só o que está efetivado, em reais e com valor diferente de zero.
    static func map(_ list: [ProviderTransaction], providerId: String, accountId: UUID, existing: [Transaction],
                    suggester: CategorySuggester? = nil, now: Date = Date()) -> BankMappingResult {
        var result = BankMappingResult()
        var seen = Set(existing.compactMap(\.externalId))
        var fresh: [(provider: ProviderTransaction, tx: Transaction)] = []
        for p in list {
            let trimmedId = p.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty else { result.skipped.append(.init(transaction: p, reason: .missingId)); continue }
            guard !p.isPending else { result.skipped.append(.init(transaction: p, reason: .pending)); continue }
            guard p.currency.uppercased() == "BRL" else { result.skipped.append(.init(transaction: p, reason: .foreignCurrency)); continue }
            guard p.amount != 0 else { result.skipped.append(.init(transaction: p, reason: .zeroAmount)); continue }
            let ext = externalId(providerId: providerId, transactionId: trimmedId)
            if seen.contains(ext) { result.duplicates.append(p); continue }
            seen.insert(ext)
            let type: TransactionType = p.amount < 0 ? .expense : .income
            let title = p.description.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            var tx = Transaction(type: type, amount: p.amount.magnitude, date: FinanceCalendar.normalize(p.postedAt, in: bankTimeZone),
                                 title: title.isEmpty ? "Sem descrição" : title, status: .paid, accountId: accountId,
                                 categoryId: suggester?.suggest(for: title, type: type), externalId: ext)
            tx.createdAt = now; tx.updatedAt = now
            fresh.append((p, tx))
        }
        // Heurística contra lançamentos manuais (sem externalId do Open Finance): vira "provável duplicata", não é importado.
        let candidates = fresh.map { CandidateTransaction(date: $0.tx.date, title: $0.tx.title, amount: $0.provider.amount, externalId: nil) }
        let manual = existing.filter { !isOpenFinanceId($0.externalId) }
        let marked = DuplicateDetector.mark(candidates, existing: manual, accountId: accountId)
        for (i, item) in fresh.enumerated() {
            if marked[i].isDuplicate { result.probableDuplicates.append(item.provider) } else { result.imported.append(item.tx) }
        }
        return result
    }
}

// MARK: - Sincronização

struct BankSyncOutcome: Sendable, Equatable {
    var imported: [Transaction] = []
    var duplicateCount = 0
    var probableDuplicates: [ProviderTransaction] = []
    var skippedCount = 0
    /// Contas do provedor que não têm conta local vinculada (nada foi importado delas).
    var unlinkedAccountIds: [String] = []
}

enum BankSyncService {
    /// Busca as transações das contas vinculadas e as converte. Não grava nada: quem chama salva `imported`.
    /// `accountLinks`: id da conta no provedor -> id da conta local.
    static func sync(provider: any BankConnectionProvider, connection: BankConnection, accountLinks: [String: UUID],
                     existing: [Transaction], from: Date, to: Date, today: Date, suggester: CategorySuggester? = nil) async throws -> BankSyncOutcome {
        switch connection.status {
        case .pending: throw BankProviderError.consentRequired
        case .revoked: throw BankProviderError.consentRevoked
        case .expired: throw BankProviderError.consentExpired
        case .active: break
        }
        guard connection.isUsable(on: today) else { throw BankProviderError.consentExpired }
        guard connection.grantedScopes.contains(.transactionsRead) else { throw BankProviderError.consentRequired }

        var outcome = BankSyncOutcome()
        var known = existing
        let accounts = try await provider.accounts(connectionId: connection.id)
        for account in accounts {
            guard let local = accountLinks[account.id] else { outcome.unlinkedAccountIds.append(account.id); continue }
            let list = try await provider.transactions(connectionId: connection.id, accountId: account.id, from: from, to: to)
            let mapped = BankTransactionMapper.map(list, providerId: provider.providerId, accountId: local, existing: known, suggester: suggester, now: today)
            outcome.imported += mapped.imported
            outcome.duplicateCount += mapped.duplicates.count
            outcome.probableDuplicates += mapped.probableDuplicates
            outcome.skippedCount += mapped.skipped.count
            known += mapped.imported
        }
        return outcome
    }
}

// MARK: - Provedor de demonstração

/// Provedor FICTÍCIO para a UI, prévias e testes. Os bancos, contas e transações são inventados e determinísticos.
/// Nunca use em produção: não representa nenhum banco real.
actor MockBankProvider: BankConnectionProvider {
    nonisolated let providerId = "mock"
    nonisolated let displayName = "Banco de demonstração (dados fictícios)"

    private let anchor: Date
    private var connections: [String: BankConnection] = [:]
    private var failure: BankProviderError?
    private var autoApprove: Bool
    private var counter = 0

    /// `anchor`: dia de referência ("hoje") das transações fictícias. `autoApprove == false` deixa a conexão `.pending`
    /// até `approve(connectionId:)`, para simular o consentimento no app do banco.
    init(anchor: Date, autoApprove: Bool = true) {
        self.anchor = anchor
        self.autoApprove = autoApprove
    }

    /// Faz a PRÓXIMA chamada falhar com `error` (uma vez).
    func failNext(with error: BankProviderError?) { failure = error }

    func approve(connectionId: String) {
        guard var c = connections[connectionId], c.status == .pending else { return }
        c.status = .active; c.authorizationURL = nil
        connections[connectionId] = c
    }

    /// Simula o fim da validade do consentimento.
    func expire(connectionId: String) {
        guard var c = connections[connectionId] else { return }
        c.status = .expired
        connections[connectionId] = c
    }

    private func throwIfFailing() throws {
        if let f = failure { failure = nil; throw f }
    }

    private func usable(_ id: String) throws -> BankConnection {
        guard let c = connections[id] else { throw BankProviderError.notFound }
        switch c.status {
        case .pending: throw BankProviderError.consentRequired
        case .revoked: throw BankProviderError.consentRevoked
        case .expired: throw BankProviderError.consentExpired
        case .active: return c
        }
    }

    func institutions() async throws -> [BankInstitution] {
        try throwIfFailing()
        return [BankInstitution(id: "mock-azul", name: "Banco Azul (fictício)"), BankInstitution(id: "mock-verde", name: "Banco Verde (fictício)")]
    }

    func beginConnection(institutionId: String, consent: ConsentRequest) async throws -> BankConnection {
        try throwIfFailing()
        guard let inst = try await institutions().first(where: { $0.id == institutionId }) else { throw BankProviderError.notFound }
        counter += 1
        let c = BankConnection(id: "mock-conn-\(counter)", institutionId: inst.id, institutionName: inst.name,
                               status: autoApprove ? .active : .pending, grantedScopes: consent.scopes, createdAt: anchor,
                               expiresAt: FinanceCalendar.addDays(anchor, consent.durationDays),
                               authorizationURL: autoApprove ? nil : URL(string: "https://example.invalid/mock-consent/\(counter)"))
        connections[c.id] = c
        return c
    }

    func connection(id: String) async throws -> BankConnection {
        try throwIfFailing()
        guard let c = connections[id] else { throw BankProviderError.notFound }
        return c
    }

    func accounts(connectionId: String) async throws -> [BankAccount] {
        try throwIfFailing()
        let c = try usable(connectionId)
        guard c.grantedScopes.contains(.accountsRead) else { throw BankProviderError.consentRequired }
        return [BankAccount(id: "\(connectionId)-cc", connectionId: connectionId, name: "Conta corrente", kind: .checking, currency: "BRL",
                            balance: c.grantedScopes.contains(.balancesRead) ? dec("2350.40") : nil),
                BankAccount(id: "\(connectionId)-poup", connectionId: connectionId, name: "Poupança", kind: .savings, currency: "BRL",
                            balance: c.grantedScopes.contains(.balancesRead) ? dec("5000.00") : nil)]
    }

    func transactions(connectionId: String, accountId: String, from: Date, to: Date) async throws -> [ProviderTransaction] {
        try throwIfFailing()
        let c = try usable(connectionId)
        guard c.grantedScopes.contains(.transactionsRead) else { throw BankProviderError.consentRequired }
        func ago(_ days: Int) -> Date { FinanceCalendar.addDays(anchor, -days) }
        let all: [ProviderTransaction]
        if accountId.hasSuffix("-cc") {
            all = [
                ProviderTransaction(id: "T-1001", accountId: accountId, postedAt: ago(14), description: "SALARIO EMPRESA XPTO", amount: dec("6200.00")),
                ProviderTransaction(id: "T-1002", accountId: accountId, postedAt: ago(10), description: "PIX ENVIADO  PADARIA   CENTRAL", amount: dec("-18.50")),
                ProviderTransaction(id: "T-1003", accountId: accountId, postedAt: ago(7), description: "SUPERMERCADO BOM PRECO", amount: dec("-412.37")),
                ProviderTransaction(id: "T-1004", accountId: accountId, postedAt: ago(3), description: "UBER *TRIP", amount: dec("-23.90")),
                ProviderTransaction(id: "T-1005", accountId: accountId, postedAt: ago(1), description: "COMPRA INTERNACIONAL", amount: dec("-10.00"), currency: "USD"),
                ProviderTransaction(id: "T-1006", accountId: accountId, postedAt: anchor, description: "ACADEMIA FIT (EM PROCESSAMENTO)", amount: dec("-99.90"), isPending: true),
                // mesmo id duas vezes no lote: o provedor às vezes repete
                ProviderTransaction(id: "T-1004", accountId: accountId, postedAt: ago(3), description: "UBER *TRIP", amount: dec("-23.90")),
            ]
        } else {
            all = [ProviderTransaction(id: "P-2001", accountId: accountId, postedAt: ago(20), description: "RENDIMENTO POUPANCA", amount: dec("31.12"))]
        }
        return all.filter { !FinanceCalendar.isBeforeDay($0.postedAt, from) && !FinanceCalendar.isBeforeDay(to, $0.postedAt) }
    }

    func revokeConsent(connectionId: String) async throws {
        try throwIfFailing()
        guard var c = connections[connectionId] else { throw BankProviderError.notFound }
        c.status = .revoked; c.authorizationURL = nil
        connections[connectionId] = c
    }
}
