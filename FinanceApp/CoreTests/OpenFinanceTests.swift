import Foundation

private final class ResultBox<T: Sendable>: @unchecked Sendable { var result: Result<T, Error>? }

/// Executa uma operação assíncrona e espera o resultado (o runner é síncrono). A tarefa roda fora da thread principal.
private func waitFor<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await op()) } catch { box.result = .failure(error) }
        done.signal()
    }
    guard done.wait(timeout: .now() + 10) == .success, let r = box.result else { throw BankProviderError.unavailable }
    return try r.get()
}

private func providerError(_ op: @escaping @Sendable () async throws -> Void) -> BankProviderError? {
    do { try waitFor(op); return nil } catch let e as BankProviderError { return e } catch { return nil }
}

private let today = D(2026, 10, 19)
private let acc = UUID()

private func p(_ id: String, _ amount: String, _ desc: String = "COMPRA", day: Int = 10, currency: String = "BRL", pending: Bool = false) -> ProviderTransaction {
    ProviderTransaction(id: id, accountId: "a1", postedAt: D(2026, 10, day), description: desc, amount: dec(amount), currency: currency, isPending: pending)
}

func openFinanceTests() -> [TestCase] {
    [
        TestCase("mapeamento: sinal vira tipo, valor é magnitude em Decimal, descrição é limpa e o externalId leva o provedor") { t in
            let r = BankTransactionMapper.map([p("A1", "-18.50", "PIX ENVIADO  PADARIA   CENTRAL"), p("A2", "6200.00", "SALARIO")],
                                              providerId: "mock", accountId: acc, existing: [])
            t.equal(r.imported.count, 2)
            let a = r.imported[0], b = r.imported[1]
            t.equal(a.type, .expense); t.equal(a.amount, dec("18.50")); t.equal(a.title, "PIX ENVIADO PADARIA CENTRAL")
            t.equal(a.externalId, "of:mock:A1"); t.equal(a.accountId, acc); t.equal(a.status, .paid)
            t.equal(b.type, .income); t.equal(b.amount, 6200)
        },
        TestCase("mapeamento: data usa o dia civil de Brasília (UTC 02:00 ainda é o dia anterior no Brasil)") { t in
            var late = p("L1", "-10.00")
            late.postedAt = Date(timeIntervalSince1970: D(2026, 10, 12).timeIntervalSince1970 - 10 * 3600)   // 12/10 02:00 UTC
            let r = BankTransactionMapper.map([late], providerId: "mock", accountId: acc, existing: [])
            t.equal(ymd(r.imported[0].date), "2026-10-11")
        },
        TestCase("mapeamento: ignora pendentes, moeda estrangeira, valor zero e id vazio") { t in
            let r = BankTransactionMapper.map([p("P1", "-5.00", pending: true), p("U1", "-9.00", currency: "USD"), p("Z1", "0"), p("  ", "-1.00"), p("OK", "-2.00")],
                                              providerId: "mock", accountId: acc, existing: [])
            t.equal(r.imported.map(\.externalId), ["of:mock:OK"])
            t.equal(r.skipped.map(\.reason), [.pending, .foreignCurrency, .zeroAmount, .missingId])
        },
        TestCase("deduplicação por externalId: contra o que já existe, dentro do lote e ao repetir a sincronização") { t in
            let first = BankTransactionMapper.map([p("A1", "-10.00", "Uber"), p("A2", "-20.00", "Mercado"), p("A1", "-10.00", "Uber")],
                                                  providerId: "mock", accountId: acc, existing: [])
            t.equal(first.imported.count, 2); t.equal(first.duplicates.count, 1)
            let again = BankTransactionMapper.map([p("A1", "-10.00", "Uber"), p("A2", "-20.00", "Mercado"), p("A3", "-30.00", "Farmácia")],
                                                  providerId: "mock", accountId: acc, existing: first.imported)
            t.equal(again.imported.map(\.externalId), ["of:mock:A3"]); t.equal(again.duplicates.count, 2)
            // outro provedor com o mesmo id não colide
            let other = BankTransactionMapper.map([p("A1", "-10.00", "Uber")], providerId: "outro", accountId: acc, existing: first.imported)
            t.equal(other.imported.count, 1)
        },
        TestCase("lançamento manual igual (mesmo dia, valor e descrição) vira provável duplicata e não é importado") { t in
            let manual = Transaction(type: .expense, amount: dec("23.90"), date: D(2026, 10, 10), title: "Uber", accountId: acc)
            let r = BankTransactionMapper.map([p("U9", "-23.90", "UBER *TRIP"), p("U10", "-50.00", "Outra coisa")],
                                              providerId: "mock", accountId: acc, existing: [manual])
            t.equal(r.probableDuplicates.map(\.id), ["U9"]); t.equal(r.imported.map(\.externalId), ["of:mock:U10"])
        },
        TestCase("sugestão de categoria é aplicada quando há suggester") { t in
            let cat = UUID()
            let s = CategorySuggester(history: [Transaction(type: .expense, amount: 10, date: today, title: "Uber", categoryId: cat)])
            let r = BankTransactionMapper.map([p("U1", "-23.90", "Uber")], providerId: "mock", accountId: acc, existing: [], suggester: s)
            t.equal(r.imported[0].categoryId, cat)
        },
        TestCase("consentimento: duração limitada a 12 meses e escopos padrão") { t in
            t.equal(ConsentRequest(durationDays: 9999).durationDays, 365)
            t.equal(ConsentRequest(durationDays: 0).durationDays, 1)
            t.equal(ConsentRequest().scopes, Set(ConsentScope.allCases))
        },
        TestCase("MockBankProvider + BankSyncService: conecta, lista contas e importa só o efetivado, sem duplicar") { t in
            let provider = MockBankProvider(anchor: today)
            let outcome: BankSyncOutcome = try waitFor {
                let inst = try await provider.institutions()
                let conn = try await provider.beginConnection(institutionId: inst[0].id, consent: ConsentRequest())
                let accounts = try await provider.accounts(connectionId: conn.id)
                return try await BankSyncService.sync(provider: provider, connection: conn, accountLinks: [accounts[0].id: acc], existing: [],
                                                      from: FinanceCalendar.addDays(today, -30), to: today, today: today)
            }
            // T-1001..T-1004 importadas; T-1005 em USD e T-1006 pendente ignoradas; T-1004 repetida é duplicata; poupança sem vínculo
            t.equal(outcome.imported.map(\.externalId), ["of:mock:T-1001", "of:mock:T-1002", "of:mock:T-1003", "of:mock:T-1004"])
            t.equal(outcome.duplicateCount, 1); t.equal(outcome.skippedCount, 2); t.equal(outcome.unlinkedAccountIds.count, 1)
            t.equal(outcome.imported.reduce(Decimal(0)) { $0 + $1.signedAmount }, dec("5745.23"))
            // segunda sincronização com o que já foi salvo: nada novo
            let saved = outcome.imported
            let second: BankSyncOutcome = try waitFor {
                let conn = try await provider.connection(id: "mock-conn-1")
                let accounts = try await provider.accounts(connectionId: conn.id)
                return try await BankSyncService.sync(provider: provider, connection: conn, accountLinks: [accounts[0].id: acc, accounts[1].id: acc],
                                                      existing: saved, from: FinanceCalendar.addDays(today, -30), to: today, today: today)
            }
            t.equal(second.imported.map(\.externalId), ["of:mock:P-2001"], "só a poupança, agora vinculada, traz algo novo")
        },
        TestCase("janela de datas: só entram transações dentro de from...to") { t in
            let provider = MockBankProvider(anchor: today)
            let list: [ProviderTransaction] = try waitFor {
                let conn = try await provider.beginConnection(institutionId: "mock-azul", consent: ConsentRequest())
                return try await provider.transactions(connectionId: conn.id, accountId: "\(conn.id)-cc", from: FinanceCalendar.addDays(today, -8), to: today)
            }
            t.equal(Set(list.map(\.id)), ["T-1003", "T-1004", "T-1005", "T-1006"])
        },
        TestCase("consentimento pendente, revogado, expirado ou sem escopo bloqueia a sincronização") { t in
            let provider = MockBankProvider(anchor: today, autoApprove: false)
            let conn: BankConnection = try waitFor { try await provider.beginConnection(institutionId: "mock-azul", consent: ConsentRequest()) }
            t.equal(conn.status, .pending); t.check(conn.authorizationURL != nil)
            func syncError(_ c: BankConnection) -> BankProviderError? {
                providerError { _ = try await BankSyncService.sync(provider: provider, connection: c, accountLinks: [:], existing: [], from: today, to: today, today: today) }
            }
            t.equal(syncError(conn), .consentRequired)
            t.equal(providerError { _ = try await provider.accounts(connectionId: conn.id) }, .consentRequired)

            let active: BankConnection = try waitFor { await provider.approve(connectionId: conn.id); return try await provider.connection(id: conn.id) }
            t.equal(active.status, .active); t.isNil(active.authorizationURL)
            t.isNil(syncError(active))

            var noTx = active; noTx.grantedScopes = [.accountsRead]
            t.equal(syncError(noTx), .consentRequired, "sem o escopo de transações")
            var old = active; old.expiresAt = D(2026, 10, 1)
            t.equal(syncError(old), .consentExpired, "validade vencida")

            let expired: BankConnection = try waitFor { await provider.expire(connectionId: conn.id); return try await provider.connection(id: conn.id) }
            t.equal(syncError(expired), .consentExpired)
            t.equal(providerError { _ = try await provider.accounts(connectionId: conn.id) }, .consentExpired)
        },
        TestCase("revogação: o provedor passa a recusar tudo e o app para de importar") { t in
            let provider = MockBankProvider(anchor: today)
            let conn: BankConnection = try waitFor { try await provider.beginConnection(institutionId: "mock-verde", consent: ConsentRequest()) }
            try waitFor { try await provider.revokeConsent(connectionId: conn.id) }
            let after: BankConnection = try waitFor { try await provider.connection(id: conn.id) }
            t.equal(after.status, .revoked)
            t.equal(providerError { _ = try await provider.accounts(connectionId: conn.id) }, .consentRevoked)
            t.equal(providerError { _ = try await provider.transactions(connectionId: conn.id, accountId: "x", from: today, to: today) }, .consentRevoked)
            t.equal(providerError { _ = try await BankSyncService.sync(provider: provider, connection: after, accountLinks: [:], existing: [], from: today, to: today, today: today) }, .consentRevoked)
            t.equal(providerError { try await provider.revokeConsent(connectionId: "inexistente") }, .notFound)
        },
        TestCase("falhas do provedor chegam como erros tipados (uma vez) e instituição desconhecida não conecta") { t in
            let provider = MockBankProvider(anchor: today)
            try waitFor { await provider.failNext(with: .unavailable) }
            t.equal(providerError { _ = try await provider.institutions() }, .unavailable)
            t.check(providerError { _ = try await provider.institutions() } == nil, "a falha injetada vale uma vez")
            t.equal(providerError { _ = try await provider.beginConnection(institutionId: "nao-existe", consent: ConsentRequest()) }, .notFound)
            t.check(!BankProviderError.unavailable.message.isEmpty)
        },
        TestCase("sem escopo de saldo, a conta não traz saldo (minimização de dados)") { t in
            let provider = MockBankProvider(anchor: today)
            let accounts: [BankAccount] = try waitFor {
                let c = try await provider.beginConnection(institutionId: "mock-azul", consent: ConsentRequest(scopes: [.accountsRead, .transactionsRead]))
                return try await provider.accounts(connectionId: c.id)
            }
            t.check(accounts.allSatisfy { $0.balance == nil })
        },
    ]
}
