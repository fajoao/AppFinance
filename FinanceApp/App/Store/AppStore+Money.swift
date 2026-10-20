import Foundation

// Dívidas, metas (edição/histórico/projeção), investimentos, patrimônio, fluxo de caixa, relatórios e IR.

extension AppStore {
    // MARK: Dívidas

    func saveDebt(_ draft: DebtDraft) throws {
        let existing = draft.editingId.flatMap { id in debts.first { $0.id == id } }
        try repository.save(try draft.build(existing: existing))
        reload()
    }

    func deleteDebt(id: UUID) throws {
        try repository.deleteTracked(Debt.self, id: id)
        reload()
    }

    var totalDebt: Decimal { debts.reduce(Decimal(0)) { $0 + max($1.balance, 0) } }

    func simulateDebts(monthlyBudget: Decimal) throws -> DebtComparison {
        try DebtSimulation.run(debts: debts, monthlyBudget: monthlyBudget)
    }

    // MARK: Metas

    func updateGoal(id: UUID, _ draft: GoalDraft) throws {
        guard let goal = goals.first(where: { $0.id == id }) else { throw StoreError.notFound }
        guard let target = draft.target else { throw StoreError.invalidLimit }
        try repository.save(try GoalEngine.edit(goal, name: draft.name, target: target, deadline: draft.effectiveDeadline))
        reload()
    }

    /// Exclui a meta e o histórico dela (os lançamentos de saída das contas permanecem: o dinheiro foi movimentado).
    func deleteGoal(id: UUID) throws {
        for e in goalContributions where e.goalId == id { try repository.deleteTracked(GoalContribution.self, id: e.id) }
        try repository.deleteTracked(Goal.self, id: id)
        reload()
    }

    func history(of goal: Goal) -> [GoalContribution] { GoalEngine.history(for: goal.id, in: goalContributions) }

    func projection(of goal: Goal) -> GoalProjection {
        GoalEngine.projection(goal: goal, contributions: goalContributions, asOf: today)
    }

    /// Desfaz um aporte: reduz a meta, apaga o registro e o lançamento de saída que o originou (se houver).
    func revertContribution(id: UUID) throws {
        guard let entry = goalContributions.first(where: { $0.id == id }),
              let goal = goals.first(where: { $0.id == entry.goalId }) else { throw StoreError.notFound }
        try repository.save(GoalEngine.revert(goal, entry: entry))
        if let linked = entry.transactionId { try repository.deleteTracked(Transaction.self, id: linked) }
        try repository.deleteTracked(GoalContribution.self, id: id)
        reload()
    }

    // MARK: Investimentos

    func saveInvestment(_ draft: InvestmentDraft) throws {
        let existing = draft.editingId.flatMap { id in investments.first { $0.id == id } }
        var inv = try draft.build(existing: existing, today: today)
        if existing == nil { inv.ownerId = viewerId; inv.memberId = viewerId }
        try repository.save(inv)
        reload()
    }

    func applyPositionChange(investmentId: UUID, _ change: PositionChangeDraft) throws {
        guard let inv = investments.first(where: { $0.id == investmentId }) else { throw StoreError.notFound }
        guard let q = change.quantity, let p = change.price else { throw FinanceError.invalidAmount }
        let updated = change.kind == .buy ? try InvestmentEngine.buy(inv, quantity: q, price: p) : try InvestmentEngine.sell(inv, quantity: q, price: p)
        try repository.save(updated)
        reload()
    }

    func updateQuote(investmentId: UUID, quoteText: String) throws {
        guard let inv = investments.first(where: { $0.id == investmentId }) else { throw StoreError.notFound }
        guard let q = Money.parse(quoteText, style: .comma) else { throw StoreError.invalidQuote }
        try repository.save(try InvestmentEngine.updateQuote(inv, quote: q, date: today))
        reload()
    }

    func deleteInvestment(id: UUID) throws {
        try repository.deleteTracked(Investment.self, id: id)
        reload()
    }

    /// Posições do perfil ativo (família: todas; individual: só as do membro).
    var visibleInvestments: [Investment] {
        guard hasHousehold, case .member(let m) = viewScope else { return investments }
        return investments.filter { $0.memberId == nil || $0.memberId == m }
    }

    var portfolio: PortfolioTotals { InvestmentEngine.totals(visibleInvestments) }
    var allocation: [AllocationSlice] { InvestmentEngine.allocation(visibleInvestments) }

    // MARK: Patrimônio

    var netWorth: NetWorth {
        NetWorthEngine.compute(accounts: scopedAccounts, transactions: transactions, investments: visibleInvestments,
                               debts: debts, creditCards: activeCards)
    }

    /// Registra (ou atualiza) o patrimônio do mês corrente. Só grava se mudou.
    @discardableResult
    func recordNetWorthSnapshot() throws -> NetWorthSnapshot {
        let nw = netWorth
        var snap = NetWorthEngine.snapshot(nw, month: currentMonth)
        snap.ownerId = viewerId
        if let existing = netWorthSnapshots.first(where: { $0.month == snap.month }),
           existing.assets == snap.assets, existing.liabilities == snap.liabilities { return existing }
        let result = NetWorthEngine.upsert(snap, into: netWorthSnapshots)
        try repository.save(result.saved)
        reload()
        return result.saved
    }

    func netWorthEvolution(months: Int = 12) -> [NetWorthPoint] {
        NetWorthEngine.evolution(netWorthSnapshots, months: months, endingAt: currentMonth)
    }

    // MARK: Fluxo de caixa projetado

    /// Faturas não pagas dos cartões ativos como saídas futuras (base do fluxo de caixa e dos insights).
    func invoiceDueItems() -> [CashFlowItem] {
        let names = Dictionary(uniqueKeysWithValues: creditCards.map { ($0.id, $0.name) })
        var summaries: [InvoiceSummary] = []
        for card in activeCards {
            summaries += CreditCardEngine.upcomingInvoices(card: card, transactions: transactions, storedInvoices: invoices, asOf: today, futureCount: 4)
        }
        return CashFlowEngine.invoiceDues(summaries: summaries, cardNames: names)
    }

    func cashFlow(days: Int) -> CashFlowProjection {
        CashFlowEngine.project(startingBalance: liquidBalance, from: today, days: days,
                               transactions: scopedTransactions, invoiceDues: invoiceDueItems())
    }

    // MARK: Relatórios e IR

    func report(period: ReportPeriod, custom: (from: Date, to: Date)? = nil, categoryIds: Set<UUID> = [],
                memberIds: Set<UUID> = [], accountIds: Set<UUID> = []) -> ReportResult {
        let range = period.range(today: today, custom: custom, month: viewedMonth)   // relatórios seguem o mês visualizado
        let filter = ReportFilter(from: range.from, to: range.to, categoryIds: categoryIds, memberIds: memberIds, accountIds: accountIds)
        return ReportEngine.run(filter, transactions: scopedTransactions, categories: categories)
    }

    func reportDocument(_ result: ReportResult, title: String = "Relatório financeiro") -> ReportDocument {
        ReportDocumentBuilder.build(result, title: title, names: lookup.reportNames, generatedOn: today)
    }

    func taxSummary(year: Int, memberId: UUID? = nil) -> TaxSummary {
        TaxEngine.summary(year: year, transactions: scopedTransactions, categories: categories, memberId: memberId)
    }

    func taxDocument(_ summary: TaxSummary, memberId: UUID? = nil) -> ReportDocument {
        TaxEngine.document(summary, names: lookup.reportNames, memberName: memberId.flatMap { lookup.members[$0]?.name }, generatedOn: today)
    }

    /// Grava o CSV do documento (BOM UTF-8, `;`) e devolve a URL temporária para compartilhar.
    func writeCSV(_ doc: ReportDocument, baseName: String, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let c = FinanceCalendar.components(today)
        let url = directory.appendingPathComponent(String(format: "%@-%04d-%02d-%02d.csv", baseName, c.year, c.month, c.day))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(("\u{FEFF}" + doc.csv()).utf8).write(to: url, options: .atomic)
        return url
    }
}
