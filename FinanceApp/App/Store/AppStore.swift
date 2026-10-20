import Foundation
import Observation

struct ToastMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
    var isWarning = false
}

struct AccountGroup: Identifiable, Equatable, Sendable {
    var type: AccountType
    var accounts: [Account]
    var subtotal: Decimal
    var id: AccountType { type }
}

struct CardOverview: Identifiable, Equatable, Sendable {
    var card: CreditCard
    var current: InvoiceSummary
    var previous: InvoiceSummary
    var available: Decimal
    var used: Decimal
    /// Parcelas e compras de faturas depois da atual.
    var futureCharges: Decimal
    var id: UUID { card.id }
    /// Fração do limite usada (0...1), para a barra.
    var usedFraction: Double {
        guard card.limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: used / card.limit).doubleValue, 0), 1)
    }
}

struct BudgetAlertEvent: Equatable, Sendable {
    var categoryName: String
    var alert: BudgetAlert
    var message: String
}

enum StoreError: Error, Equatable {
    case emptyName, invalidDay, invalidLimit, notFound, cannotDeleteInvoicePayment
    case noHousehold, invalidPercent, invalidQuote, pinInvalid, syncUnavailable, cannotEditInvoicePayment, householdExists
    var message: String {
        switch self {
        case .emptyName: return "Informe um nome."
        case .invalidDay: return "Dia inválido. Use de 1 a 31."
        case .invalidLimit: return "Informe um valor maior que zero."
        case .notFound: return "Registro não encontrado."
        case .cannotDeleteInvoicePayment: return "Pagamentos de fatura não podem ser excluídos nesta versão."
        case .cannotEditInvoicePayment: return "Pagamentos de fatura não podem ser editados. Use Pagar fatura."
        case .householdExists: return "O grupo familiar já foi criado."
        case .noHousehold: return "Crie o grupo familiar primeiro."
        case .invalidPercent: return "Percentual inválido. Use de 0 a 100."
        case .invalidQuote: return "Informe uma cotação válida."
        case .pinInvalid: return "O código deve ter de 4 a 6 números."
        case .syncUnavailable: return "A sincronização com o iCloud ainda não está configurada neste build."
        }
    }
}

/// Fonte única de verdade da UI. Persiste via `Repository` (Core) e expõe consultas derivadas calculadas
/// pelos motores do Core. Não importa SwiftUI: é testável com swiftc.
@MainActor @Observable
final class AppStore {
    // MARK: Dependências
    @ObservationIgnored let repository: Repository
    @ObservationIgnored private let preferencesStore: PreferencesStoring
    @ObservationIgnored let reminders: ReminderScheduling
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored let widgets: WidgetPublishing
    @ObservationIgnored let secrets: SecretStoring
    @ObservationIgnored let attachments: AttachmentStorage
    @ObservationIgnored let syncService: SyncService?
    @ObservationIgnored var syncCoordinator: SyncCoordinator?
    /// Open Finance (Fase 3): sem provedor por padrão. Ver `OpenFinanceModel`.
    @ObservationIgnored let openFinance = OpenFinanceModel()

    // MARK: Estado (somente leitura para as Views)
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    private(set) var tags: [Tag] = []
    private(set) var transactions: [Transaction] = []
    private(set) var creditCards: [CreditCard] = []
    private(set) var invoices: [Invoice] = []
    private(set) var budgets: [Budget] = []
    private(set) var goals: [Goal] = []
    // Fase 2
    private(set) var debts: [Debt] = []
    private(set) var goalContributions: [GoalContribution] = []
    private(set) var investments: [Investment] = []
    private(set) var netWorthSnapshots: [NetWorthSnapshot] = []
    private(set) var households: [Household] = []
    private(set) var members: [FamilyMember] = []
    private(set) var splits: [ExpenseSplit] = []
    private(set) var settlements: [SplitSettlement] = []
    private(set) var allowances: [Allowance] = []
    private(set) var approvals: [ApprovalRequest] = []
    var syncStatus: SyncStatus = .disabled
    private(set) var lookup = FinanceLookup()
    private(set) var preferences: AppPreferences
    /// Dia civil de hoje (UTC meio-dia). Congelável com `-fixedToday`.
    private(set) var today: Date
    private(set) var isLocked = false
    /// true com `-uiTesting`: sem prompt de biometria (o desbloqueio é imediato).
    var isUITesting = false

    var toast: ToastMessage?
    /// true enquanto `refresh()` roda (botão de atualizar gira e fica desabilitado; evita execuções simultâneas).
    var isRefreshing = false   // escrito só por `refresh()` (AppStore+Refresh.swift)
    @ObservationIgnored var lastRefreshToastAt: Date?
    /// Última atualização manual concluída com sucesso (lida pelo botão de atualizar, para o VoiceOver e testes).
    var lastRefreshAt: Date?
    @ObservationIgnored private var suggestExpense = CategorySuggester()
    @ObservationIgnored private var suggestIncome = CategorySuggester()
    @ObservationIgnored private var backgroundedAt: Date?

    init(repository: Repository, preferences: PreferencesStoring = InMemoryPreferences(),
         reminders: ReminderScheduling = NoopReminderScheduler(), clock: @escaping () -> Date = { FinanceCalendar.normalize(Date()) },
         widgets: WidgetPublishing = NoopWidgetPublisher(), secrets: SecretStoring = InMemorySecrets(),
         attachments: AttachmentStorage? = nil, syncService: SyncService? = nil) {
        self.repository = repository
        self.preferencesStore = preferences
        self.reminders = reminders
        self.clock = clock
        self.widgets = widgets
        self.secrets = secrets
        self.syncService = syncService
        self.attachments = attachments ?? AttachmentStorage(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("financeapp-attachments-\(UUID().uuidString)", isDirectory: true))
        self.preferences = preferences.load()
        let now = clock()
        self.today = now
        self.viewedMonth = YearMonth(now)
        reload()
    }

    // MARK: Carga

    func reload() {
        today = clock()
        do {
            let s = try repository.snapshot()
            accounts = s.accounts.sorted { $0.createdAt < $1.createdAt }
            categories = s.categories
            tags = s.tags.sorted { $0.name < $1.name }
            transactions = s.transactions
            creditCards = s.creditCards.sorted { $0.createdAt < $1.createdAt }
            invoices = s.invoices
            budgets = s.budgets
            goals = s.goals.sorted { $0.createdAt < $1.createdAt }
            debts = s.debts.sorted { $0.createdAt < $1.createdAt }
            goalContributions = s.goalContributions
            investments = s.investments.sorted { $0.createdAt < $1.createdAt }
            netWorthSnapshots = s.netWorthSnapshots.sorted { $0.month < $1.month }
            households = s.households
            members = s.familyMembers.sorted { $0.createdAt < $1.createdAt }
            splits = s.expenseSplits.sorted { $0.date > $1.date }
            settlements = s.splitSettlements
            allowances = s.allowances
            approvals = s.approvalRequests.sorted { $0.createdAt > $1.createdAt }
            widgets.publish(WidgetDataBuilder.make(snapshot: s, today: today, hideValues: preferences.hideValues))
        } catch {
            show("Não foi possível ler os dados: \(error)", warning: true)
        }
        lookup = FinanceLookup(accounts: accounts, categories: categories, tags: tags, cards: creditCards, members: members)
        suggestExpense = CategorySuggester(history: transactions, keywords: DefaultCategories.keywords(for: categories, kind: .expense))
        suggestIncome = CategorySuggester(history: transactions, keywords: DefaultCategories.keywords(for: categories, kind: .income))
    }

    func updatePreferences(_ change: (inout AppPreferences) -> Void) {
        change(&preferences)
        preferencesStore.save(preferences)
    }

    /// Texto monetário respeitando "ocultar valores".
    func money(_ value: Decimal, sign: AmountSign = .natural) -> String {
        MoneyDisplay.text(value, sign: sign, hidden: preferences.hideValues)
    }

    func show(_ text: String, warning: Bool = false) { toast = ToastMessage(text: text, isWarning: warning) }

    /// Executa um comando e mostra o erro em toast. Retorna true se deu certo.
    @discardableResult
    func attempt(_ body: () throws -> Void) -> Bool {
        do { try body(); return true }
        catch let e as DraftError { show(e.message, warning: true) }
        catch let e as StoreError { show(e.message, warning: true) }
        catch let e as FinanceError { show(e.description, warning: true) }
        catch { show("Algo deu errado: \(error.localizedDescription)", warning: true) }
        return false
    }

    /// Mês REAL de hoje. Use para lógica de "agora" (snapshot de patrimônio, início de mesada, alertas de orçamento,
    /// mês padrão de novos lançamentos). Telas de visualização usam `viewedMonth`.
    var currentMonth: YearMonth { YearMonth(today) }
    /// Mês exibido nas telas de visualização (Início, Orçamento, Lançamentos, A pagar, Faturas, Relatórios).
    /// Não é persistido: ao reabrir o app volta para o mês atual.
    private(set) var viewedMonth: YearMonth
    var isViewingCurrentMonth: Bool { viewedMonth == currentMonth }
    func setViewedMonth(_ month: YearMonth) { viewedMonth = PeriodSelection.clamp(month) }
    func stepViewedMonth(by months: Int) { viewedMonth = PeriodSelection.moved(viewedMonth, by: months) }
    func resetViewedMonth() { viewedMonth = currentMonth }
    /// Contas que o perfil ativo pode usar nos formulários (compartilhadas + as próprias).
    var activeAccounts: [Account] { usableAccounts.filter { !$0.isArchived } }
    var activeCards: [CreditCard] { creditCards.filter { !$0.isArchived } }
    var expenseCategories: [Category] { selectableCategories.filter { $0.kind == .expense && $0.parentId == nil } }
    var incomeCategories: [Category] { selectableCategories.filter { $0.kind == .income && $0.parentId == nil } }

    // MARK: Saldos (Core: BalanceEngine)

    func balance(of account: Account) -> Decimal { BalanceEngine.balance(of: account, transactions: transactions) }

    /// Saldo em contas do Início: corrente + poupança + carteira (investimentos ficam de fora).
    var liquidBalance: Decimal {
        BalanceEngine.totalBalance(accounts: scopedAccounts, transactions: transactions, types: [.checking, .savings, .wallet])
    }

    /// Patrimônio total da tela Contas (inclui investimentos).
    var totalWealth: Decimal { BalanceEngine.totalBalance(accounts: scopedAccounts, transactions: transactions) }

    var accountGroups: [AccountGroup] {
        AccountType.allCases.compactMap { type in
            let list = scopedAccounts.filter { !$0.isArchived && $0.type == type }
            guard !list.isEmpty else { return nil }
            return AccountGroup(type: type, accounts: list, subtotal: list.reduce(0) { $0 + balance(of: $1) })
        }
    }

    // MARK: Resumos (Core: SummaryEngine, BudgetEngine)

    func summary(for month: YearMonth) -> MonthlySummary { SummaryEngine.summary(month: month, transactions: scopedTransactions) }

    func budgetStatuses(for month: YearMonth) -> [BudgetStatus] {
        BudgetEngine.statuses(month: month, budgets: budgets, transactions: transactions, categories: categories)
            .sorted { lookup.categoryName($0.budget.categoryId) < lookup.categoryName($1.budget.categoryId) }
    }

    /// Soma dos limites e dos gastos dos orçamentos do mês.
    func budgetTotals(for month: YearMonth) -> (limit: Decimal, spent: Decimal) {
        let list = budgetStatuses(for: month)
        return (list.reduce(0) { $0 + $1.limit }, list.reduce(0) { $0 + $1.spent })
    }

    var billItems: [BillItem] {
        BillsModel.items(transactions: transactions, cards: activeCards, invoices: invoices, today: today)
    }

    func upcomingBills(limit: Int = 3) -> [BillItem] {
        billItems.filter { !$0.isPaid }.prefix(limit).map { $0 }
    }

    // MARK: Cartões (Core: CreditCardEngine)

    func cardOverview(_ card: CreditCard) -> CardOverview {
        let month = CreditCardEngine.currentInvoiceMonth(card: card, asOf: today)
        let current = CreditCardEngine.summary(card: card, month: month, transactions: transactions, storedInvoices: invoices, asOf: today)
        let previous = CreditCardEngine.summary(card: card, month: month.previous, transactions: transactions, storedInvoices: invoices, asOf: today)
        let future = transactions
            .filter { $0.creditCardId == card.id && $0.isCardPurchase && CreditCardEngine.invoiceMonth(forPurchaseOn: $0.date, card: card) > month }
            .reduce(Decimal(0)) { $0 + ($1.type == .income ? -$1.amount : $1.amount) }
        return CardOverview(card: card, current: current, previous: previous,
                            available: CreditCardEngine.availableLimit(card: card, transactions: transactions),
                            used: CreditCardEngine.usedLimit(card: card, transactions: transactions), futureCharges: future)
    }

    var cardOverviews: [CardOverview] { activeCards.map(cardOverview) }

    /// Mês da fatura aberta: no mês atual é a fatura vigente do cartão (que pode já ser a do mês seguinte, depois do
    /// fechamento); em outro mês visualizado, a fatura daquele mês.
    func openInvoiceMonth(for card: CreditCard) -> YearMonth {
        isViewingCurrentMonth ? CreditCardEngine.currentInvoiceMonth(card: card, asOf: today) : viewedMonth
    }

    /// Abas da fatura: anterior, a do mês visualizado (índice 1) e as 2 seguintes.
    func invoiceTabs(for card: CreditCard) -> [InvoiceSummary] {
        let base = openInvoiceMonth(for: card)
        return (-1...2).map { offset in
            CreditCardEngine.summary(card: card, month: base.adding(months: offset), transactions: transactions, storedInvoices: invoices, asOf: today)
        }
    }

    func invoiceSummary(cardId: UUID, month: YearMonth) -> InvoiceSummary? {
        guard let card = creditCards.first(where: { $0.id == cardId }) else { return nil }
        return CreditCardEngine.summary(card: card, month: month, transactions: transactions, storedInvoices: invoices, asOf: today)
    }

    func payInvoice(cardId: UUID, month: YearMonth, amount: Decimal?, from accountId: UUID) throws {
        guard let card = creditCards.first(where: { $0.id == cardId }),
              let summary = invoiceSummary(cardId: cardId, month: month) else { throw StoreError.notFound }
        let result = try CreditCardEngine.pay(summary, card: card, amount: amount, from: accountId, on: today)
        try repository.save(result.invoice)
        try repository.save(result.payment)
        reload()
        Task { await rescheduleReminders() }
    }

    // MARK: Lançamentos

    func suggestCategory(for title: String, type: TransactionType) -> UUID? {
        let id = (type == .income ? suggestIncome : suggestExpense).suggest(for: title, type: type)
        guard let id, let c = lookup.categories[id], c.kind == (type == .income ? .income : .expense) else { return nil }
        return id
    }

    func suggester(for type: TransactionType) -> CategorySuggester { type == .income ? suggestIncome : suggestExpense }

    func makeDraft(type: TransactionType = .expense, date: Date? = nil) -> TransactionDraft {
        var draft = TransactionDraft(date: date ?? today, type: type, defaultAccountId: activeAccounts.first?.id)
        draft.memberId = viewerId
        return draft
    }

    @discardableResult
    func save(_ draft: TransactionDraft) throws -> [BudgetAlertEvent] {
        var list = try draft.makeTransactions(cards: creditCards, today: today)
        let member = draft.memberId ?? viewerId
        for i in list.indices { list[i].memberId = member; list[i].attachmentPath = draft.attachmentPath }
        if list.count == 1, let ext = draft.externalId { list[0].externalId = ext }
        try repository.saveAll(list)
        try materializeRecurrences()
        reload()
        let events = evaluateBudgetAlerts()
        Task { await rescheduleReminders() }
        return events
    }

    func deleteTransaction(id: UUID) throws {
        guard let tx = transactions.first(where: { $0.id == id }) else { throw StoreError.notFound }
        if tx.isInvoicePayment { throw StoreError.cannotDeleteInvoicePayment }
        try repository.deleteTracked(Transaction.self, id: id, now: Date())
        removeAttachmentIfOrphan(tx.attachmentPath, excluding: [id])
        reload()
        Task { await rescheduleReminders() }
    }

    func markPaid(transactionId: UUID) throws {
        guard var tx = transactions.first(where: { $0.id == transactionId }) else { throw StoreError.notFound }
        tx.status = .paid
        try repository.save(touching: tx)
        reload()
        Task { await rescheduleReminders() }
    }

    /// Gera as próximas ocorrências (pendentes) dos lançamentos recorrentes, até ~4 meses à frente.
    func materializeRecurrences(horizonDays: Int = 120) throws {
        let end = FinanceCalendar.addDays(today, horizonDays)
        var generated: [Transaction] = []
        var known = transactions
        // inclui o que acabou de ser salvo (o array em memória só atualiza em reload)
        if let fresh = try? repository.all(Transaction.self) { known = fresh }
        for tpl in known where tpl.recurrence != nil {
            generated += RecurrenceEngine.generate(from: tpl, from: tpl.date, to: end, existing: known)
        }
        if !generated.isEmpty { try repository.saveAll(generated) }
    }

    func createTag(named name: String) throws -> Tag {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw StoreError.emptyName }
        if let existing = tags.first(where: { TextDecoding.normalize($0.name) == TextDecoding.normalize(n) }) { return existing }
        let tag = Tag(name: n)
        try repository.save(tag)
        reload()
        return tag
    }

    // MARK: Orçamento

    func setBudget(categoryId: UUID, limit: Decimal, month: YearMonth? = nil) throws {
        guard limit > 0 else { throw StoreError.invalidLimit }
        let m = month ?? viewedMonth   // orçamento é editado no mês que está na tela
        if var existing = budgets.first(where: { $0.categoryId == categoryId && $0.month == m }) {
            existing.limit = limit
            try repository.save(touching: existing)
        } else {
            try repository.save(Budget(categoryId: categoryId, month: m, limit: limit))
        }
        reload()
    }

    func removeBudget(id: UUID) throws { try repository.deleteTracked(Budget.self, id: id); reload() }

    /// Copia os orçamentos do mês anterior ao visualizado que ainda não existem nele. Retorna quantos foram copiados.
    @discardableResult
    func copyBudgetsFromPreviousMonth() throws -> Int {
        let m = viewedMonth
        let existing = Set(budgets.filter { $0.month == m }.map(\.categoryId))
        let copies = BudgetEngine.copy(budgets: budgets, from: m.previous, to: m).filter { !existing.contains($0.categoryId) }
        try repository.saveAll(copies)
        reload()
        return copies.count
    }

    /// Verifica 80% e 100% e avisa uma vez por categoria/mês (toast + notificação local).
    @discardableResult
    func evaluateBudgetAlerts() -> [BudgetAlertEvent] {
        let month = currentMonth   // alerta é "agora": sempre o mês real, mesmo com outro mês na tela
        var events: [BudgetAlertEvent] = []
        var sent = preferences.budgetAlertsSent
        for status in BudgetEngine.alerts(month: month, budgets: budgets, transactions: transactions, categories: categories) {
            let base = "\(status.budget.categoryId.uuidString)|\(month.label)"
            let name = lookup.categoryName(status.budget.categoryId)
            if status.alert == .exceeded, !sent.contains(base + "|exceeded") {
                sent.insert(base + "|exceeded"); sent.insert(base + "|warning")
                let over = MoneyDisplay.text(-status.remaining)
                events.append(BudgetAlertEvent(categoryName: name, alert: .exceeded, message: "\(name): estourou o orçamento em \(over)."))
            } else if status.alert == .warning, !sent.contains(base + "|warning") {
                sent.insert(base + "|warning")
                events.append(BudgetAlertEvent(categoryName: name, alert: .warning, message: "\(name): \(percentText(status.percentUsed)) do orçamento usado."))
            }
        }
        if sent != preferences.budgetAlertsSent { updatePreferences { $0.budgetAlertsSent = sent } }
        if let first = events.first { show(first.message, warning: true) }
        for e in events {
            let id = "budget-\(e.categoryName)-\(month.label)-\(e.alert.rawValue)"
            Task { await reminders.notifyNow(id: id, title: "Orçamento", body: e.message) }
        }
        return events
    }

    func percentText(_ p: Decimal) -> String { "\(NSDecimalNumber(decimal: p.rounded(scale: 0)).intValue)%" }

    // MARK: Metas (Core: GoalEngine)

    func progress(of goal: Goal) -> GoalProgress { GoalEngine.progress(goal: goal, asOf: today) }

    func addGoal(name: String, target: Decimal, deadline: Date?, saved: Decimal = 0, memberId: UUID? = nil) throws {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw StoreError.emptyName }
        guard target > 0 else { throw StoreError.invalidLimit }
        try repository.save(Goal(name: n, targetAmount: target, currentAmount: saved, deadline: deadline, memberId: memberId))
        reload()
    }

    /// Guarda dinheiro na meta. O valor sai da conta de origem como transferência sem destino
    /// (não conta como despesa, mas reduz o saldo) e fica registrado no histórico de aportes.
    func contribute(goalId: UUID, amount: Decimal, from accountId: UUID) throws {
        guard let goal = goals.first(where: { $0.id == goalId }) else { throw StoreError.notFound }
        let recorded = try GoalEngine.record(goal, amount: amount, date: today, accountId: accountId)
        var outflow = Transaction(type: .transfer, amount: amount, date: today, title: "Guardado em \(goal.name)", status: .paid, accountId: accountId)
        outflow.memberId = goal.memberId ?? viewerId
        var entry = recorded.entry
        entry.transactionId = outflow.id          // liga o aporte ao lançamento de saída
        try repository.save(recorded.goal)
        try repository.save(entry)
        try repository.save(outflow)
        reload()
    }

    // MARK: Contas e cartões

    func addAccount(name: String, type: AccountType, balance: Decimal, visibility: Visibility = .shared) throws {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw StoreError.emptyName }
        try repository.save(Account(name: n, type: type, initialBalance: balance, visibility: visibility, ownerId: viewerId))
        reload()
    }

    func archiveAccount(id: UUID) throws {
        guard var a = accounts.first(where: { $0.id == id }) else { throw StoreError.notFound }
        a.isArchived = true
        try repository.save(touching: a)
        reload()
    }

    func addCard(name: String, limit: Decimal, closingDay: Int, dueDay: Int, paymentAccountId: UUID?) throws {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw StoreError.emptyName }
        guard limit > 0 else { throw StoreError.invalidLimit }
        guard (1...31).contains(closingDay), (1...31).contains(dueDay) else { throw StoreError.invalidDay }
        try repository.save(CreditCard(name: n, limit: limit, closingDay: closingDay, dueDay: dueDay, paymentAccountId: paymentAccountId))
        reload()
    }

    func reconciliationDifference(account: Account, statementBalance: Decimal) -> Decimal {
        BalanceEngine.reconciliationDifference(account: account, statementBalance: statementBalance, transactions: transactions)
    }

    /// Cria o lançamento de ajuste que iguala o saldo ao extrato. Retorna false se já estava conciliado.
    @discardableResult
    func reconcile(account: Account, statementBalance: Decimal) throws -> Bool {
        guard let adjustment = BalanceEngine.reconciliationAdjustment(account: account, statementBalance: statementBalance,
                                                                       transactions: transactions, date: today) else { return false }
        try repository.save(adjustment)
        reload()
        return true
    }

    // MARK: Importação e exportação

    func prepareImport(fileName: String, data: Data, accountId: UUID?) -> ImportPreview {
        ImportPreview.make(fileName: fileName, data: data, accountId: accountId, existing: transactions,
                           suggestExpense: suggestExpense, suggestIncome: suggestIncome)
    }

    /// Grava as candidatas novas (repetidas são ignoradas). Retorna quantas foram gravadas.
    @discardableResult
    func commitImport(_ preview: ImportPreview, accountId: UUID) throws -> Int {
        let list = preview.newCandidates.map { $0.toTransaction(accountId: accountId) }
        try repository.saveAll(list)
        reload()
        return list.count
    }

    /// CSV com `;`, vírgula decimal e BOM UTF-8 (abre direto no Excel pt-BR).
    func csvText(for list: [Transaction]? = nil) -> String {
        "\u{FEFF}" + CSVExporter.export(transactions: list ?? transactions, accounts: accounts, categories: categories, tags: tags)
    }

    func writeCSVExport(for list: [Transaction]? = nil, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let c = FinanceCalendar.components(today)
        let url = directory.appendingPathComponent(String(format: "lancamentos-%04d-%02d-%02d.csv", c.year, c.month, c.day))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(csvText(for: list).utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: Lembretes

    var reminderPlan: [PlannedReminder] {
        guard preferences.remindersEnabled else { return [] }
        return ReminderPlanner.plan(bills: billItems, today: today, daysBefore: preferences.reminderDaysBefore)
    }

    func rescheduleReminders() async {
        await reminders.replaceAll(with: reminderPlan)
    }

    // MARK: Bloqueio

    /// Bloqueio ligado: biometria e/ou PIN próprio.
    var appLockEnabled: Bool { preferences.faceIDEnabled || preferences.pinEnabled }

    func lockNow() { isLocked = true }
    func unlock() { isLocked = false }

    /// Chamar quando o app vai para segundo plano / volta.
    func sceneBackgrounded(at now: Date = Date()) { backgroundedAt = now }

    func sceneActivated(at now: Date = Date()) {
        defer { backgroundedAt = nil }
        guard appLockEnabled, preferences.onboardingDone, let since = backgroundedAt else { return }
        let elapsed = now.timeIntervalSince(since)
        if elapsed >= Double(preferences.lockDelay.rawValue) * 60 { isLocked = true }
    }

    // MARK: Ciclo de vida dos dados

    func completeOnboarding(_ draft: OnboardingDraft) throws {
        guard draft.isValid, let balance = draft.balance else { throw StoreError.emptyName }
        try repository.saveAll(DefaultCategories.make())
        try repository.save(Account(name: draft.trimmedName, type: draft.accountType, initialBalance: balance))
        updatePreferences {
            $0.onboardingDone = true
            $0.faceIDEnabled = draft.faceID
            $0.remindersEnabled = draft.reminders
        }
        reload()
    }

    func loadDemoData(family: Bool = false) throws {
        try repository.restore(family ? DemoSeed.makeFamily(today: today) : DemoSeed.make(today: today))
        updatePreferences { $0.onboardingDone = true; $0.budgetAlertsSent = []; $0.activeMemberId = nil; $0.viewScope = .family }
        reload()
        try materializeRecurrences()
        reload()
    }

    func eraseAllData() throws {
        try repository.restore(FinanceSnapshot())
        secrets.set(nil, for: PinLock.keychainKey)
        attachments.removeAll()
        syncCoordinator = nil
        syncStatus = .disabled
        updatePreferences { $0 = AppPreferences() }
        reload()
    }

    /// Cópia dos dados em JSON (backup).
    func backupData() throws -> Data { try JSONFileStore.encoder.encode(repository.snapshot()) }
}
