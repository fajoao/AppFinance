import Foundation

// MARK: - Orçamento

enum BudgetAlert: String, Sendable, Equatable { case none, warning, exceeded }

struct BudgetStatus: Sendable, Equatable {
    var budget: Budget
    var spent: Decimal
    var limit: Decimal { budget.limit }
    var remaining: Decimal { budget.limit - spent }
    /// Percentual consumido (82,5 = 82,5%), 2 casas.
    var percentUsed: Decimal
    var alert: BudgetAlert
}

enum BudgetEngine {
    static let warningThreshold: Decimal = 80
    static let exceededThreshold: Decimal = 100

    /// Ids da categoria + subcategorias.
    static func categoryFamily(_ categoryId: UUID, categories: [Category]) -> Set<UUID> {
        var ids: Set<UUID> = [categoryId]
        var changed = true
        while changed {
            changed = false
            for c in categories where c.parentId != nil && ids.contains(c.parentId!) && !ids.contains(c.id) {
                ids.insert(c.id); changed = true
            }
        }
        return ids
    }

    /// Gasto (despesas, inclui compras de cartão e subcategorias; transferências ignoradas).
    static func spent(categoryId: UUID, month: YearMonth, transactions: [Transaction], categories: [Category] = [], onlyPaid: Bool = false) -> Decimal {
        let family = categoryFamily(categoryId, categories: categories)
        return transactions.reduce(0) { acc, tx in
            guard tx.type == .expense, !tx.isInvoicePayment, let cat = tx.categoryId, family.contains(cat),
                  month.contains(tx.date), !onlyPaid || tx.status == .paid else { return acc }
            return acc + tx.amount
        }
    }

    static func alert(spent: Decimal, limit: Decimal) -> BudgetAlert {
        if limit <= 0 { return spent > 0 ? .exceeded : .none }
        if spent * 100 >= limit * exceededThreshold { return .exceeded }
        if spent * 100 >= limit * warningThreshold { return .warning }
        return .none
    }

    static func status(budget: Budget, transactions: [Transaction], categories: [Category] = [], onlyPaid: Bool = false) -> BudgetStatus {
        let s = spent(categoryId: budget.categoryId, month: budget.month, transactions: transactions, categories: categories, onlyPaid: onlyPaid)
        let pct: Decimal = budget.limit > 0 ? (s * 100 / budget.limit).rounded(scale: 2) : (s > 0 ? 100 : 0)
        return BudgetStatus(budget: budget, spent: s, percentUsed: pct, alert: alert(spent: s, limit: budget.limit))
    }

    static func statuses(month: YearMonth, budgets: [Budget], transactions: [Transaction], categories: [Category] = []) -> [BudgetStatus] {
        budgets.filter { $0.month == month }.map { status(budget: $0, transactions: transactions, categories: categories) }
    }

    /// Orçamentos em alerta (80%+), do mais consumido para o menos.
    static func alerts(month: YearMonth, budgets: [Budget], transactions: [Transaction], categories: [Category] = []) -> [BudgetStatus] {
        statuses(month: month, budgets: budgets, transactions: transactions, categories: categories)
            .filter { $0.alert != .none }.sorted { $0.percentUsed > $1.percentUsed }
    }

    /// Copia os orçamentos de um mês para outro (ids novos).
    static func copy(budgets: [Budget], from: YearMonth, to: YearMonth) -> [Budget] {
        budgets.filter { $0.month == from }.map { Budget(categoryId: $0.categoryId, month: to, limit: $0.limit, ownerId: $0.ownerId) }
    }
}

// MARK: - Resumo mensal

struct CategoryTotal: Sendable, Equatable {
    var categoryId: UUID?     // nil = sem categoria
    var amount: Decimal
    var percentOfTotal: Decimal
}

struct MonthComparison: Sendable, Equatable {
    var previousIncome: Decimal
    var previousExpense: Decimal
    var incomeDelta: Decimal
    var expenseDelta: Decimal
    /// nil quando o mês anterior é zero.
    var incomeChangePercent: Decimal?
    var expenseChangePercent: Decimal?
}

struct MonthlySummary: Sendable, Equatable {
    var month: YearMonth
    var income: Decimal
    var expense: Decimal
    var balance: Decimal { income - expense }
    var expensesByCategory: [CategoryTotal]
    var incomeByCategory: [CategoryTotal]
    var comparison: MonthComparison
}

enum SummaryEngine {
    private static func counts(_ tx: Transaction, onlyPaid: Bool) -> Bool {
        tx.type != .transfer && !tx.isInvoicePayment && (!onlyPaid || tx.status == .paid)
    }

    static func totals(month: YearMonth, transactions: [Transaction], onlyPaid: Bool = false) -> (income: Decimal, expense: Decimal) {
        var inc: Decimal = 0, exp: Decimal = 0
        for tx in transactions where month.contains(tx.date) && counts(tx, onlyPaid: onlyPaid) {
            if tx.type == .income { inc += tx.amount } else { exp += tx.amount }
        }
        return (inc, exp)
    }

    private static func grouped(_ type: TransactionType, month: YearMonth, transactions: [Transaction], total: Decimal, onlyPaid: Bool) -> [CategoryTotal] {
        var map: [UUID?: Decimal] = [:]
        for tx in transactions where tx.type == type && month.contains(tx.date) && counts(tx, onlyPaid: onlyPaid) {
            map[tx.categoryId, default: 0] += tx.amount
        }
        return map.map { CategoryTotal(categoryId: $0.key, amount: $0.value,
                                       percentOfTotal: total == 0 ? 0 : ($0.value * 100 / total).rounded(scale: 2)) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.categoryId?.uuidString ?? "") < ($1.categoryId?.uuidString ?? "") }
    }

    private static func change(_ now: Decimal, _ before: Decimal) -> Decimal? {
        before == 0 ? nil : ((now - before) * 100 / before.magnitude).rounded(scale: 2)
    }

    static func summary(month: YearMonth, transactions: [Transaction], onlyPaid: Bool = false) -> MonthlySummary {
        let cur = totals(month: month, transactions: transactions, onlyPaid: onlyPaid)
        let prev = totals(month: month.previous, transactions: transactions, onlyPaid: onlyPaid)
        let comparison = MonthComparison(previousIncome: prev.income, previousExpense: prev.expense,
                                         incomeDelta: cur.income - prev.income, expenseDelta: cur.expense - prev.expense,
                                         incomeChangePercent: change(cur.income, prev.income),
                                         expenseChangePercent: change(cur.expense, prev.expense))
        return MonthlySummary(month: month, income: cur.income, expense: cur.expense,
                              expensesByCategory: grouped(.expense, month: month, transactions: transactions, total: cur.expense, onlyPaid: onlyPaid),
                              incomeByCategory: grouped(.income, month: month, transactions: transactions, total: cur.income, onlyPaid: onlyPaid),
                              comparison: comparison)
    }
}

// MARK: - Fluxo de caixa projetado

struct CashFlowItem: Sendable, Equatable {
    var date: Date
    /// Positivo = entrada, negativo = saída.
    var amount: Decimal
    var label: String
}

struct CashFlowPoint: Sendable, Equatable {
    var date: Date
    var change: Decimal
    var balance: Decimal
}

struct CashFlowProjection: Sendable, Equatable {
    var days: Int
    var startingBalance: Decimal
    var points: [CashFlowPoint]          // um por dia (do dia seguinte a `from` até from+days)
    var items: [CashFlowItem]
    var endingBalance: Decimal
    var lowestBalance: Decimal
    var lowestBalanceDate: Date?
    var totalIn: Decimal
    var totalOut: Decimal
    var goesNegative: Bool { lowestBalance < 0 }
}

enum CashFlowEngine {
    /// Efeito de um lançamento no caixa total: transferência entre contas = 0; pagamento de fatura = saída.
    static func cashEffect(_ tx: Transaction) -> Decimal {
        switch tx.type {
        case .income: return tx.amount
        case .expense: return tx.isCardPurchase ? 0 : -tx.amount     // compra de cartão sai no pagamento da fatura
        case .transfer: return tx.destinationAccountId == nil ? -tx.amount : 0
        }
    }

    /// Itens futuros: lançamentos pendentes (exceto compras de cartão), ocorrências de modelos recorrentes e faturas.
    static func items(from: Date, days: Int, transactions: [Transaction], invoiceDues: [CashFlowItem] = []) -> [CashFlowItem] {
        let end = FinanceCalendar.addDays(from, days)
        let start = FinanceCalendar.addDays(from, 1)
        var result: [CashFlowItem] = []
        for tx in transactions where tx.status == .pending {
            let d = FinanceCalendar.startOfDay(tx.date)
            if d >= FinanceCalendar.startOfDay(start) && d <= FinanceCalendar.startOfDay(end), cashEffect(tx) != 0 {
                result.append(CashFlowItem(date: tx.date, amount: cashEffect(tx), label: tx.title))
            }
        }
        for tpl in transactions where tpl.recurrence != nil {
            for occ in RecurrenceEngine.generate(from: tpl, from: start, to: end, existing: transactions) {
                let eff = cashEffect(occ)
                if eff != 0 { result.append(CashFlowItem(date: occ.date, amount: eff, label: occ.title)) }
            }
            // a própria data do modelo, caso esteja no futuro e paga (modelo já realizado não entra)
        }
        for due in invoiceDues where FinanceCalendar.startOfDay(due.date) >= FinanceCalendar.startOfDay(start)
            && FinanceCalendar.startOfDay(due.date) <= FinanceCalendar.startOfDay(end) {
            result.append(due)
        }
        return result.sorted { $0.date < $1.date }
    }

    static func project(startingBalance: Decimal, from: Date, days: Int, transactions: [Transaction], invoiceDues: [CashFlowItem] = []) -> CashFlowProjection {
        let list = items(from: from, days: days, transactions: transactions, invoiceDues: invoiceDues)
        var points: [CashFlowPoint] = []
        var balance = startingBalance
        var lowest = startingBalance
        var lowestDate: Date? = nil
        var totalIn: Decimal = 0, totalOut: Decimal = 0
        for offset in 1...max(days, 1) where offset <= days {
            let day = FinanceCalendar.addDays(from, offset)
            let delta = list.filter { FinanceCalendar.isSameDay($0.date, day) }.reduce(0) { $0 + $1.amount }
            balance += delta
            points.append(CashFlowPoint(date: day, change: delta, balance: balance))
            if balance < lowest { lowest = balance; lowestDate = day }
        }
        for i in list { if i.amount > 0 { totalIn += i.amount } else { totalOut += -i.amount } }
        return CashFlowProjection(days: days, startingBalance: startingBalance, points: points, items: list,
                                  endingBalance: balance, lowestBalance: lowest, lowestBalanceDate: lowestDate,
                                  totalIn: totalIn, totalOut: totalOut)
    }

    /// Projeções de 30, 60 e 90 dias.
    static func standardProjections(startingBalance: Decimal, from: Date, transactions: [Transaction], invoiceDues: [CashFlowItem] = []) -> [Int: CashFlowProjection] {
        Dictionary(uniqueKeysWithValues: [30, 60, 90].map { ($0, project(startingBalance: startingBalance, from: from, days: $0, transactions: transactions, invoiceDues: invoiceDues)) })
    }

    /// Faturas não pagas viram saídas no vencimento.
    static func invoiceDues(summaries: [InvoiceSummary], cardNames: [UUID: String] = [:]) -> [CashFlowItem] {
        summaries.filter { $0.remaining > 0 }.map {
            CashFlowItem(date: $0.invoice.dueDate, amount: -$0.remaining,
                         label: "Fatura \(cardNames[$0.invoice.cardId] ?? "cartão") \($0.invoice.month.label)")
        }
    }
}

// MARK: - Dívidas

enum PayoffStrategy: String, Sendable, CaseIterable { case avalanche, snowball }

struct PayoffResult: Sendable, Equatable {
    var strategy: PayoffStrategy
    var months: Int
    var totalInterest: Decimal
    var totalPaid: Decimal
    /// Ids na ordem em que foram quitadas.
    var payoffOrder: [UUID]
    /// Mês (1-based) de quitação de cada dívida.
    var payoffMonth: [UUID: Int]
    /// false se não quita em 100 anos (juros maiores que o pagamento).
    var feasible: Bool
    /// Saldo devedor total ao fim de cada mês (índice 0 = fim do mês 1). Alimenta o gráfico de comparação.
    var monthlyBalances: [Decimal] = []
}

enum DebtEngine {
    static let maxMonths = 1200

    static func simulate(debts: [Debt], monthlyBudget: Decimal, strategy: PayoffStrategy) throws -> PayoffResult {
        var active = debts.filter { $0.balance > 0 }.map { (id: $0.id, rate: $0.monthlyInterestRate, min: $0.minimumPayment, bal: $0.balance.rounded(scale: 2)) }
        let required = active.reduce(Decimal(0)) { $0 + $1.min }
        // O orçamento precisa cobrir ao menos os mínimos (limitados ao saldo).
        if monthlyBudget < required && !active.isEmpty { throw FinanceError.budgetBelowMinimums(required: required) }
        var month = 0
        var interestTotal: Decimal = 0, paidTotal: Decimal = 0
        var order: [UUID] = [], payoff: [UUID: Int] = [:]
        var series: [Decimal] = []
        while !active.isEmpty && month < maxMonths {
            month += 1
            let totalBefore = active.reduce(Decimal(0)) { $0 + $1.bal }
            for i in active.indices {
                let interest = (active[i].bal * active[i].rate).rounded(scale: 2)
                active[i].bal += interest; interestTotal += interest
            }
            var pool = monthlyBudget
            for i in active.indices {
                let pay = min(active[i].min, active[i].bal, pool)
                active[i].bal -= pay; pool -= pay; paidTotal += pay
            }
            // extra para a prioridade
            let priority = active.indices.filter { active[$0].bal > 0 }.sorted { a, b in
                let x = active[a], y = active[b]
                switch strategy {
                case .avalanche: return x.rate != y.rate ? x.rate > y.rate : x.bal < y.bal
                case .snowball: return x.bal != y.bal ? x.bal < y.bal : x.rate > y.rate
                }
            }
            for i in priority where pool > 0 {
                let pay = min(active[i].bal, pool)
                active[i].bal -= pay; pool -= pay; paidTotal += pay
            }
            for d in active where d.bal <= 0 { order.append(d.id); payoff[d.id] = month }
            active.removeAll { $0.bal <= 0 }
            series.append(active.reduce(Decimal(0)) { $0 + $1.bal })
            // saldo não diminuiu: os juros superam o pagamento e a dívida só cresce (evita estouro numérico)
            if !active.isEmpty && active.reduce(Decimal(0), { $0 + $1.bal }) >= totalBefore { break }
        }
        return PayoffResult(strategy: strategy, months: month, totalInterest: interestTotal, totalPaid: paidTotal,
                            payoffOrder: order, payoffMonth: payoff, feasible: active.isEmpty, monthlyBalances: series)
    }

    /// Compara as duas estratégias.
    static func compare(debts: [Debt], monthlyBudget: Decimal) throws -> (avalanche: PayoffResult, snowball: PayoffResult, interestSavedByAvalanche: Decimal) {
        let a = try simulate(debts: debts, monthlyBudget: monthlyBudget, strategy: .avalanche)
        let s = try simulate(debts: debts, monthlyBudget: monthlyBudget, strategy: .snowball)
        return (a, s, s.totalInterest - a.totalInterest)
    }
}

// MARK: - Metas

struct GoalProgress: Sendable, Equatable {
    var fraction: Decimal        // 0...1
    var percent: Decimal         // 0...100 (limitado), 2 casas
    var remaining: Decimal       // >= 0
    var isComplete: Bool
    /// Meses inteiros restantes até o prazo (nil sem prazo; 0 se vencido).
    var monthsRemaining: Int?
    /// Aporte mensal necessário (arredondado para cima em centavos). nil sem prazo; = restante se prazo vencido/no mês.
    var monthlyContributionNeeded: Decimal?
}

enum GoalEngine {
    static func progress(goal: Goal, asOf: Date) -> GoalProgress {
        let target = goal.targetAmount
        let remaining = max(target - goal.currentAmount, 0)
        let fraction: Decimal = target > 0 ? min(max(goal.currentAmount / target, 0), 1) : (goal.currentAmount > 0 ? 1 : 0)
        let complete = target > 0 ? goal.currentAmount >= target : true
        var months: Int? = nil
        var needed: Decimal? = nil
        if let deadline = goal.deadline {
            let m = YearMonth(asOf).months(to: YearMonth(deadline))
            // se o dia do prazo já passou no mês corrente e é o mesmo mês, conta 0 meses
            let n = FinanceCalendar.startOfDay(deadline) <= FinanceCalendar.startOfDay(asOf) ? 0 : max(m, 1)
            months = n
            needed = complete ? 0 : (n <= 1 ? remaining : (remaining / Decimal(n)).rounded(scale: 2, mode: .up))
        }
        return GoalProgress(fraction: fraction, percent: (fraction * 100).rounded(scale: 2), remaining: remaining,
                            isComplete: complete, monthsRemaining: months, monthlyContributionNeeded: needed)
    }

    static func contribute(_ goal: Goal, amount: Decimal) throws -> Goal {
        guard amount != 0 else { throw FinanceError.invalidAmount }
        var g = goal
        g.currentAmount = max(g.currentAmount + amount, 0)
        g.updatedAt = Date()
        return g
    }
}

// MARK: - Metas: edição, histórico e projeção

struct GoalProjection: Sendable, Equatable {
    /// Média mensal de aportes líquidos na janela considerada.
    var averageMonthlyContribution: Decimal
    /// Meses (arredondados para cima) até atingir a meta no ritmo atual. nil se o ritmo é zero/negativo.
    var monthsToComplete: Int?
    var projectedCompletion: Date?
    /// nil quando a meta não tem prazo.
    var onTrack: Bool?
    /// Quanto falta por mês, além do ritmo atual, para cumprir o prazo (0 se já está no caminho; nil sem prazo).
    var extraPerMonthNeeded: Decimal?
}

extension GoalEngine {
    /// Edita nome, valor-alvo e prazo (valida como na criação).
    static func edit(_ goal: Goal, name: String, target: Decimal, deadline: Date?) throws -> Goal {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw FinanceError.invalidState("Informe um nome.") }
        guard target > 0 else { throw FinanceError.invalidAmount }
        var g = goal
        g.name = n; g.targetAmount = target; g.deadline = deadline
        g.updatedAt = Date()
        return g
    }

    /// Aporte (ou retirada) com registro no histórico. A retirada não deixa o saldo da meta negativo.
    static func record(_ goal: Goal, amount: Decimal, date: Date, accountId: UUID? = nil, note: String? = nil) throws -> (goal: Goal, entry: GoalContribution) {
        let updated = try contribute(goal, amount: amount)
        let applied = updated.currentAmount - goal.currentAmount
        let entry = GoalContribution(goalId: goal.id, amount: applied, date: date, accountId: accountId, note: note, ownerId: goal.ownerId)
        return (updated, entry)
    }

    /// Desfaz um aporte do histórico (ex.: lançado por engano).
    static func revert(_ goal: Goal, entry: GoalContribution) -> Goal {
        var g = goal
        g.currentAmount = max(g.currentAmount - entry.amount, 0)
        g.updatedAt = Date()
        return g
    }

    static func history(for goalId: UUID, in entries: [GoalContribution]) -> [GoalContribution] {
        entries.filter { $0.goalId == goalId }.sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
    }

    /// Projeção pelo ritmo dos últimos `lookbackMonths` meses (inclui o mês corrente). Se o primeiro aporte é mais
    /// recente que a janela, divide só pelos meses desde ele (mínimo 1).
    static func projection(goal: Goal, contributions: [GoalContribution], asOf: Date, lookbackMonths: Int = 3) -> GoalProjection {
        let mine = contributions.filter { $0.goalId == goal.id && !FinanceCalendar.isBeforeDay(asOf, $0.date) }
        let window = max(lookbackMonths, 1)
        let current = YearMonth(asOf)
        let firstMonth = current.adding(months: -(window - 1))
        let inWindow = mine.filter { YearMonth($0.date) >= firstMonth }
        let net = inWindow.reduce(Decimal(0)) { $0 + $1.amount }
        var divisor = window
        if let earliest = mine.map({ YearMonth($0.date) }).min() {
            divisor = min(window, max(earliest.months(to: current) + 1, 1))
        }
        let average = (net / Decimal(divisor)).rounded(scale: 2)
        let remaining = max(goal.targetAmount - goal.currentAmount, 0)

        var months: Int? = nil
        var completion: Date? = nil
        if remaining == 0 { months = 0; completion = asOf }
        else if average > 0 {
            let n = NSDecimalNumber(decimal: (remaining / average).rounded(scale: 0, mode: .up)).intValue
            months = max(n, 1)
            completion = FinanceCalendar.addMonths(asOf, months!)
        }

        var onTrack: Bool? = nil
        var extra: Decimal? = nil
        if let deadline = goal.deadline {
            if remaining == 0 { onTrack = true; extra = 0 }
            else {
                onTrack = completion.map { !FinanceCalendar.isBeforeDay(deadline, $0) } ?? false
                let needed = GoalEngine.progress(goal: goal, asOf: asOf).monthlyContributionNeeded ?? remaining
                extra = onTrack == true ? 0 : max(needed - max(average, 0), 0)
            }
        }
        return GoalProjection(averageMonthlyContribution: average, monthsToComplete: months, projectedCompletion: completion,
                              onTrack: onTrack, extraPerMonthNeeded: extra)
    }

    static func goals(for memberId: UUID?, in goals: [Goal]) -> [Goal] { goals.filter { $0.memberId == memberId } }
}
