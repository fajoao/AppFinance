import Foundation

// Insights locais e explicáveis. NENHUM serviço externo e nenhum modelo de IA: só estatística simples e determinística
// sobre os lançamentos do próprio aparelho (mediana, desvio absoluto mediano, médias e regras de calendário).
// Cada insight carrega `explanation`: os passos do cálculo com os números, para a pessoa poder conferir.
//
// Limites honestos: poucos meses de histórico dão resultados fracos (por isso há mínimos e um nível de confiança);
// as previsões não conhecem receitas que ainda não foram agendadas nem gastos fora do padrão; sazonalidade
// (13º, IPVA, férias) não é modelada.

// MARK: - Modelo

enum InsightKind: String, Sendable, Equatable { case negativeRisk, forecast, anomaly, subscription, saving }

enum InsightSeverity: Int, Sendable, Equatable, Comparable {
    case info = 0, warning = 1, critical = 2
    static func < (l: InsightSeverity, r: InsightSeverity) -> Bool { l.rawValue < r.rawValue }
}

struct Insight: Identifiable, Sendable, Equatable {
    /// Estável entre execuções com os mesmos dados (serve para identificadores de acessibilidade e para dispensar um insight).
    var id: String
    var kind: InsightKind
    var severity: InsightSeverity
    var title: String
    var message: String
    /// Passos do cálculo, um por linha.
    var explanation: [String]
    /// Valor principal do insight (economia, saldo previsto, gasto atípico...).
    var amount: Decimal?
}

enum Confidence: String, Sendable, Equatable {
    case low, medium, high
    var displayName: String {
        switch self {
        case .low: return "baixa"
        case .medium: return "média"
        case .high: return "alta"
        }
    }
}

// MARK: - Estatística robusta

enum RobustStats {
    static func median(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    /// Desvio absoluto mediano (MAD): mediana dos desvios em relação à mediana.
    static func mad(_ values: [Decimal]) -> Decimal {
        let m = median(values)
        return median(values.map { ($0 - m).magnitude })
    }

    /// Escore z modificado (Iglewicz e Hoaglin): 0,6745 × (x − mediana) ÷ MAD. Valores acima de 3,5 indicam atipicidade.
    static let zFactor = dec("0.6745")
    static func modifiedZ(_ x: Decimal, median: Decimal, mad: Decimal) -> Decimal {
        guard mad > 0 else { return 0 }
        return zFactor * (x - median) / mad
    }
}

private func money(_ v: Decimal) -> String { Money.format(v) }
private func day(_ d: Date) -> String { ReportDocumentBuilder.dateText(d) }
private func pct(_ v: Decimal, scale: Int = 0) -> String { "\(v.rounded(scale: scale))".replacingOccurrences(of: ".", with: ",") + "%" }
private func num(_ v: Decimal, scale: Int = 1) -> String { "\(v.rounded(scale: scale))".replacingOccurrences(of: ".", with: ",") }

/// Categoria raiz (subcategorias contam na categoria pai).
private func rootCategory(_ id: UUID?, _ byId: [UUID: Category]) -> UUID? {
    guard var cur = id else { return nil }
    var hops = 0
    while let parent = byId[cur]?.parentId, hops < 5 { cur = parent; hops += 1 }
    return cur
}

private func categoryName(_ id: UUID?, _ byId: [UUID: Category]) -> String { id.flatMap { byId[$0]?.name } ?? "Sem categoria" }

/// Despesa que conta no resultado do mês (mesma regra do `SummaryEngine`: sem transferências nem pagamento de fatura).
private func isCountedExpense(_ t: Transaction) -> Bool { t.type == .expense && !t.isInvoicePayment }

// MARK: - Gastos atípicos

struct CategoryAnomaly: Sendable, Equatable {
    var categoryId: UUID?
    var categoryName: String
    var month: YearMonth
    var amount: Decimal
    var median: Decimal
    /// Desvio usado na conta (MAD com piso de 10% da mediana e de R$ 1).
    var spread: Decimal
    var score: Decimal
    var history: [(month: YearMonth, amount: Decimal)]

    static func == (l: CategoryAnomaly, r: CategoryAnomaly) -> Bool {
        l.categoryId == r.categoryId && l.month == r.month && l.amount == r.amount && l.median == r.median && l.spread == r.spread && l.score == r.score
    }

    var increase: Decimal { amount - median }
    var percentAbove: Decimal? { median > 0 ? (increase * 100 / median).rounded(scale: 0) : nil }
}

struct TransactionAnomaly: Sendable, Equatable {
    var transactionId: UUID
    var title: String
    var categoryName: String
    var amount: Decimal
    var median: Decimal
    var score: Decimal
    var sampleCount: Int
}

enum AnomalyDetector {
    static let lookbackMonths = 6
    static let minHistoryMonths = 3
    static let threshold = dec("3.5")
    static let minIncrease = dec("50")
    static let minTransactionSamples = 8

    /// Total gasto por categoria raiz e mês (despesas que contam no resultado).
    static func monthlyTotals(transactions: [Transaction], categories: [Category]) -> [UUID?: [YearMonth: Decimal]] {
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var map: [UUID?: [YearMonth: Decimal]] = [:]
        for t in transactions where isCountedExpense(t) {
            map[rootCategory(t.categoryId, byId), default: [:]][YearMonth(t.date), default: 0] += t.amount
        }
        return map
    }

    /// Categorias cujo gasto do mês atual está muito acima do que é normal para elas.
    /// Compara o mês corrente (até agora) com a mediana dos até 6 meses anteriores; exige 3 meses de histórico.
    static func categoryAnomalies(transactions: [Transaction], categories: [Category], today: Date) -> [CategoryAnomaly] {
        let current = YearMonth(today)
        guard let first = transactions.map({ YearMonth($0.date) }).min(), first < current else { return [] }
        let start = max(first, current.adding(months: -lookbackMonths))
        let historyMonths = (0..<max(start.months(to: current), 0)).map { start.adding(months: $0) }
        guard historyMonths.count >= minHistoryMonths else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var result: [CategoryAnomaly] = []
        for (cat, months) in monthlyTotals(transactions: transactions, categories: categories) {
            guard let now = months[current], now > 0 else { continue }
            let history = historyMonths.map { (month: $0, amount: months[$0] ?? 0) }
            let values = history.map(\.amount)
            let med = RobustStats.median(values)
            let spread = max(RobustStats.mad(values), med * dec("0.10"), 1)
            let increase = now - med
            let score = RobustStats.modifiedZ(now, median: med, mad: spread)
            guard increase >= minIncrease, score >= threshold else { continue }
            result.append(CategoryAnomaly(categoryId: cat, categoryName: categoryName(cat, byId), month: current, amount: now, median: med,
                                          spread: spread, score: score.rounded(scale: 1), history: history))
        }
        return result.sorted { $0.increase != $1.increase ? $0.increase > $1.increase : $0.categoryName < $1.categoryName }
    }

    /// Compras individuais do mês muito acima do valor típico da categoria (exige 8 compras anteriores na categoria).
    static func transactionAnomalies(transactions: [Transaction], categories: [Category], today: Date) -> [TransactionAnomaly] {
        let current = YearMonth(today)
        let windowStart = current.adding(months: -lookbackMonths)
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var past: [UUID?: [Decimal]] = [:]
        for t in transactions where isCountedExpense(t) && YearMonth(t.date) < current && YearMonth(t.date) >= windowStart {
            past[rootCategory(t.categoryId, byId), default: []].append(t.amount)
        }
        var out: [TransactionAnomaly] = []
        for t in transactions where isCountedExpense(t) && current.contains(t.date) && !FinanceCalendar.isBeforeDay(today, t.date) {
            let cat = rootCategory(t.categoryId, byId)
            guard let samples = past[cat], samples.count >= minTransactionSamples else { continue }
            let med = RobustStats.median(samples)
            let spread = max(RobustStats.mad(samples), med * dec("0.10"), 1)
            let score = RobustStats.modifiedZ(t.amount, median: med, mad: spread)
            guard score >= threshold, t.amount >= med * 2, t.amount - med >= minIncrease else { continue }
            out.append(TransactionAnomaly(transactionId: t.id, title: t.title, categoryName: categoryName(cat, byId), amount: t.amount,
                                          median: med, score: score.rounded(scale: 1), sampleCount: samples.count))
        }
        return out.sorted { $0.amount > $1.amount }
    }

    static func explanation(for a: CategoryAnomaly) -> [String] {
        let monthsText = a.history.map { "\($0.month.label): \(money($0.amount))" }.joined(separator: "; ")
        return [
            "Total lançado em \(a.categoryName) em \(a.month.label): \(money(a.amount)) (inclui contas já agendadas para o mês).",
            "Meses anteriores (\(a.history.count)): \(monthsText).",
            "Mediana desses meses: \(money(a.median)). Desvio usado: \(money(a.spread)) (desvio absoluto mediano, com piso de 10% da mediana).",
            "Pontuação = 0,6745 × (\(money(a.amount)) − \(money(a.median))) ÷ \(money(a.spread)) = \(num(a.score)). Consideramos atípico acima de 3,5 e com aumento de ao menos \(money(minIncrease)).",
        ]
    }
}

// MARK: - Previsão de saldo

struct BalanceForecast: Sendable, Equatable {
    var asOf: Date
    var endDate: Date
    var days: Int
    var startingBalance: Decimal
    var committedIn: Decimal
    var committedOut: Decimal
    var committedItemCount: Int
    var variableDailyAverage: Decimal
    var variableTotal: Decimal
    var historyDays: Int
    var projectedBalance: Decimal
    var lowestBalance: Decimal
    var lowestDate: Date?
    var firstNegativeDate: Date?
    var confidence: Confidence

    var goesNegative: Bool { firstNegativeDate != nil }
}

enum BalanceForecaster {
    static let lookbackDays = 60
    /// Abaixo deste saldo o app avisa que a reserva está curta.
    static let lowBalanceThreshold: Decimal = 100

    /// Média diária de gastos "variáveis" nos últimos `lookbackDays` dias: despesas pagas, sem recorrência, parcela nem
    /// compra no cartão (essas entram pelas recorrências, pelas parcelas já agendadas e pelo pagamento da fatura).
    static func variableDailyAverage(transactions: [Transaction], today: Date) -> (average: Decimal, days: Int) {
        guard let firstDate = transactions.map(\.date).min() else { return (0, 0) }
        let windowStart = max(FinanceCalendar.addDays(today, -lookbackDays), FinanceCalendar.startOfDay(firstDate))
        let days = max(FinanceCalendar.daysBetween(windowStart, today), 0)
        guard days > 0 else { return (0, 0) }
        var total: Decimal = 0
        for t in transactions where t.type == .expense && t.status == .paid && !t.isCardPurchase && !t.isInvoicePayment
            && t.recurrence == nil && t.recurrenceParentId == nil && t.installment == nil
            && !FinanceCalendar.isBeforeDay(t.date, windowStart) && FinanceCalendar.isBeforeDay(t.date, today) {
            total += t.amount
        }
        return ((total / Decimal(days)).rounded(scale: 2), days)
    }

    /// Projeta o saldo por `days` dias: saldo de hoje + compromissos já conhecidos (pendentes, recorrências, faturas)
    /// − gasto variável médio por dia.
    static func forecast(startingBalance: Decimal, transactions: [Transaction], invoiceDues: [CashFlowItem] = [],
                         today: Date, days: Int) -> BalanceForecast {
        let horizon = max(days, 0)
        let known = CashFlowEngine.project(startingBalance: startingBalance, from: today, days: horizon,
                                           transactions: transactions, invoiceDues: invoiceDues)
        let variable = variableDailyAverage(transactions: transactions, today: today)
        var lowest = startingBalance
        var lowestDate: Date?
        var firstNegative: Date?
        for (i, p) in known.points.enumerated() {
            let balance = p.balance - variable.average * Decimal(i + 1)
            if balance < lowest { lowest = balance; lowestDate = p.date }
            if balance < 0, firstNegative == nil { firstNegative = p.date }
        }
        let variableTotal = variable.average * Decimal(horizon)
        let confidence: Confidence = variable.days < 14 ? .low : (variable.days < 45 ? .medium : .high)
        return BalanceForecast(asOf: today, endDate: FinanceCalendar.addDays(today, horizon), days: horizon, startingBalance: startingBalance,
                               committedIn: known.totalIn, committedOut: known.totalOut, committedItemCount: known.items.count,
                               variableDailyAverage: variable.average, variableTotal: variableTotal, historyDays: variable.days,
                               projectedBalance: known.endingBalance - variableTotal, lowestBalance: lowest, lowestDate: lowestDate,
                               firstNegativeDate: firstNegative, confidence: confidence)
    }

    /// Dias que faltam até o último dia do mês de `today`.
    static func daysLeftInMonth(_ today: Date) -> Int { FinanceCalendar.daysBetween(today, YearMonth(today).lastDay) }

    static func explanation(for f: BalanceForecast) -> [String] {
        var lines = [
            "Saldo em contas em \(day(f.asOf)): \(money(f.startingBalance)).",
            "+ Entradas já previstas até \(day(f.endDate)): \(money(f.committedIn)).",
            "− Saídas já previstas (contas a pagar, recorrências e faturas): \(money(f.committedOut)) em \(f.committedItemCount) lançamentos no total.",
            "− Gastos variáveis estimados: \(money(f.variableTotal)) = \(money(f.variableDailyAverage)) por dia × \(f.days) dias. A média vem dos últimos \(f.historyDays) dias, sem recorrências, parcelas nem compras no cartão (estas entram pelo pagamento da fatura).",
            "= Saldo previsto em \(day(f.endDate)): \(money(f.projectedBalance)).",
        ]
        if f.confidence != .high {
            lines.append("Confiança \(f.confidence.displayName): há só \(f.historyDays) dias de histórico para estimar o gasto diário.")
        }
        lines.append("A previsão não inclui receitas ainda não agendadas nem gastos fora do padrão.")
        return lines
    }
}

// MARK: - Assinaturas e recorrências detectadas

struct DetectedRecurrence: Identifiable, Sendable, Equatable {
    var id: String                      // chave normalizada do título
    var title: String
    var frequency: RecurrenceFrequency
    var typicalAmount: Decimal          // mediana dos valores
    var lastAmount: Decimal
    var occurrences: Int
    var lastDate: Date
    var nextExpectedDate: Date
    var amountIsStable: Bool
    /// O lançamento já está marcado como recorrente no app.
    var isDeclared: Bool
    var categoryId: UUID?
    /// Aumento (em %) do último valor sobre a mediana dos anteriores, quando ≥ 3%.
    var priceIncreasePercent: Decimal?
    /// Mediana dos valores anteriores ao último (base do aumento).
    var previousAmount: Decimal?

    /// Custo mensal equivalente.
    var monthlyCost: Decimal {
        switch frequency {
        case .monthly: return typicalAmount
        case .weekly: return (typicalAmount * 52 / 12).rounded(scale: 2)
        case .yearly: return (typicalAmount / 12).rounded(scale: 2)
        }
    }
    var annualCost: Decimal { monthlyCost * 12 }
    /// Valor fixo e periodicidade mensal/anual: típico de assinatura (streaming, plano, seguro).
    var isSubscriptionLike: Bool { amountIsStable && frequency != .weekly }
}

enum RecurrenceDetector {
    static func key(for title: String) -> String {
        let folded = TextDecoding.normalize(title)
        let cleaned = folded.map { $0.isLetter || $0 == " " ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Procura despesas que se repetem em intervalo regular: mensal (3+ vezes), semanal (4+) ou anual (2+),
    /// ainda ativas (a última ocorrência é recente). Parcelas e pagamentos de fatura ficam de fora.
    static func detect(transactions: [Transaction], today: Date) -> [DetectedRecurrence] {
        var groups: [String: [Transaction]] = [:]
        for t in transactions where t.type == .expense && t.status == .paid && !t.isInvoicePayment && t.installment == nil
            && !FinanceCalendar.isBeforeDay(today, t.date) {
            let k = key(for: t.title)
            if !k.isEmpty { groups[k, default: []].append(t) }
        }
        var found: [DetectedRecurrence] = []
        for (k, list) in groups {
            // um lançamento por dia (duas compras no mesmo dia viram uma)
            var byDay: [Date: Transaction] = [:]
            for t in list { byDay[FinanceCalendar.startOfDay(t.date)] = t }
            let sorted = byDay.values.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { continue }
            let gaps = zip(sorted, sorted.dropFirst()).map { FinanceCalendar.daysBetween($0.date, $1.date) }
            let medianGap = Int(NSDecimalNumber(decimal: RobustStats.median(gaps.map { Decimal($0) })).intValue)
            let frequency: RecurrenceFrequency, tolerance: Int, minCount: Int
            switch medianGap {
            case 26...35: frequency = .monthly; tolerance = 5; minCount = 3
            case 6...8: frequency = .weekly; tolerance = 1; minCount = 4
            case 350...380: frequency = .yearly; tolerance = 10; minCount = 2
            default: continue
            }
            guard sorted.count >= minCount else { continue }
            let regular = gaps.filter { abs($0 - medianGap) <= tolerance }.count
            guard regular * 4 >= gaps.count * 3 else { continue }   // ao menos 75% dos intervalos regulares
            let last = sorted[sorted.count - 1]
            // ainda ativa: a última ocorrência foi há menos de 1,5 período
            let periodDays = frequency == .monthly ? 31 : (frequency == .weekly ? 7 : 366)
            guard FinanceCalendar.daysBetween(last.date, today) <= periodDays * 3 / 2 else { continue }

            let amounts = sorted.map(\.amount)
            let typical = RobustStats.median(amounts)
            // Valor fixo: os lançamentos anteriores ao último variam no máximo 10% (o último pode ter sido reajustado).
            let basis = amounts.count >= 3 ? Array(amounts.dropLast()) : amounts
            let spreadOK = (basis.max()! - basis.min()!) <= max(RobustStats.median(basis) * dec("0.10"), 2)
            var increase: Decimal?
            let previous = RobustStats.median(Array(amounts.dropLast()))
            if previous > 0 {
                let p = (last.amount - previous) * 100 / previous
                if p >= 3 { increase = p.rounded(scale: 0) }
            }
            let next: Date
            switch frequency {
            case .monthly: next = FinanceCalendar.addMonths(last.date, 1)
            case .weekly: next = FinanceCalendar.addDays(last.date, 7)
            case .yearly: next = FinanceCalendar.addYears(last.date, 1)
            }
            let declared = list.contains { $0.recurrence != nil || $0.recurrenceParentId != nil }
            found.append(DetectedRecurrence(id: k, title: last.title, frequency: frequency, typicalAmount: typical, lastAmount: last.amount,
                                            occurrences: sorted.count, lastDate: last.date, nextExpectedDate: next, amountIsStable: spreadOK,
                                            isDeclared: declared, categoryId: last.categoryId, priceIncreasePercent: increase,
                                            previousAmount: previous))
        }
        return found.sorted { $0.monthlyCost != $1.monthlyCost ? $0.monthlyCost > $1.monthlyCost : $0.title < $1.title }
    }
}

// MARK: - Sugestões de economia

struct SavingSuggestion: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var message: String
    var monthlySaving: Decimal
    var annualSaving: Decimal { monthlySaving * 12 }
    var explanation: [String]
}

enum SavingsAdvisor {
    static let reductionPercent: Decimal = 10
    static let minCategoryAverage: Decimal = 100
    static let maxCategorySuggestions = 3

    static func suggestions(transactions: [Transaction], categories: [Category], recurrences: [DetectedRecurrence], today: Date) -> [SavingSuggestion] {
        var out: [SavingSuggestion] = []

        // 1) Assinaturas: quanto custam e quanto se economiza revisando a mais cara.
        let subs = recurrences.filter(\.isSubscriptionLike)
        if subs.count >= 2 {
            let monthly = subs.reduce(Decimal(0)) { $0 + $1.monthlyCost }
            let top = subs[0]
            let list = subs.prefix(5).map { "\($0.title): \(money($0.monthlyCost))/mês" }.joined(separator: "; ")
            out.append(SavingSuggestion(
                id: "save:subscriptions", title: "Revise suas assinaturas",
                message: "Você tem \(subs.count) assinaturas que somam \(money(monthly)) por mês. Cancelar \(top.title) economizaria \(money(top.annualCost)) por ano.",
                monthlySaving: top.monthlyCost,
                explanation: ["Assinaturas detectadas (valor fixo, mensais ou anuais): \(list).",
                              "Soma: \(money(monthly)) por mês, ou \(money(monthly * 12)) por ano.",
                              "A mais cara é \(top.title): \(money(top.monthlyCost)) por mês × 12 = \(money(top.annualCost)) por ano.",
                              "É uma simulação: só você sabe se vale cancelar."]))
        }

        // 2) Corte de 10% nas categorias de gasto variável que mais pesam (média dos 3 últimos meses fechados).
        let current = YearMonth(today)
        let months = (1...3).map { current.adding(months: -$0) }
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let totals = AnomalyDetector.monthlyTotals(transactions: transactions, categories: categories)
        let firstMonth = transactions.map { YearMonth($0.date) }.min()
        let usable = months.filter { m in firstMonth.map { m >= $0 } ?? false }
        let recurringKeys = Set(recurrences.map(\.id))
        if usable.count >= 2 {
            var fixedShare: [UUID?: Decimal] = [:]       // gasto em recorrências/assinaturas por categoria no período
            var totalByCat: [UUID?: Decimal] = [:]
            for t in transactions where isCountedExpense(t) && usable.contains(YearMonth(t.date)) {
                let cat = rootCategory(t.categoryId, byId)
                totalByCat[cat, default: 0] += t.amount
                if t.recurrence != nil || t.recurrenceParentId != nil || recurringKeys.contains(RecurrenceDetector.key(for: t.title)) {
                    fixedShare[cat, default: 0] += t.amount
                }
            }
            let ranked = totals.compactMap { (cat, perMonth) -> (UUID?, Decimal, [Decimal])? in
                let values = usable.map { perMonth[$0] ?? 0 }
                let avg = (values.reduce(0, +) / Decimal(values.count)).rounded(scale: 2)
                let total = totalByCat[cat] ?? 0
                let fixed = fixedShare[cat] ?? 0
                guard avg >= minCategoryAverage, total > 0, fixed * 2 <= total else { return nil }   // maioria fixa: não é "cortável"
                return (cat, avg, values)
            }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : categoryName($0.0, byId) < categoryName($1.0, byId) }
            for (cat, avg, values) in ranked.prefix(maxCategorySuggestions) {
                let saving = (avg * reductionPercent / 100).rounded(scale: 2)
                let name = categoryName(cat, byId)
                out.append(SavingSuggestion(
                    id: "save:cut:\(cat?.uuidString ?? "none")", title: "Reduzir \(pct(reductionPercent)) em \(name)",
                    message: "A média mensal em \(name) é \(money(avg)). Gastar \(pct(reductionPercent)) a menos libera \(money(saving)) por mês, \(money(saving * 12)) por ano.",
                    monthlySaving: saving,
                    explanation: ["Gasto em \(name) nos \(usable.count) últimos meses fechados: \(zip(usable, values).map { "\($0.label): \(money($1))" }.joined(separator: "; ")).",
                                  "Média mensal: \(money(avg)).",
                                  "\(pct(reductionPercent)) de \(money(avg)) = \(money(saving)) por mês; × 12 = \(money(saving * 12)) por ano.",
                                  "Mostramos só categorias sem maioria de gastos fixos. O percentual é uma simulação, não uma meta imposta."]))
            }
        }
        return out
    }
}

// MARK: - Relatório de insights

struct InsightsReport: Sendable, Equatable {
    var insights: [Insight]
    var forecastEndOfMonth: BalanceForecast
    var forecast30: BalanceForecast
    var categoryAnomalies: [CategoryAnomaly]
    var transactionAnomalies: [TransactionAnomaly]
    var recurrences: [DetectedRecurrence]
    var savings: [SavingSuggestion]
    /// false quando há pouco histórico: a tela avisa que os insights ficam melhores com o tempo.
    var hasEnoughHistory: Bool

    func insights(of kind: InsightKind) -> [Insight] { insights.filter { $0.kind == kind } }
}

enum InsightsEngine {
    /// Gera todos os insights a partir dos dados (já filtrados pelo escopo do perfil). Determinístico: mesmos dados, mesmo resultado.
    static func generate(transactions: [Transaction], categories: [Category], liquidBalance: Decimal, invoiceDues: [CashFlowItem],
                         today: Date) -> InsightsReport {
        var insights: [Insight] = []

        // Previsões
        let monthEnd = BalanceForecaster.forecast(startingBalance: liquidBalance, transactions: transactions, invoiceDues: invoiceDues,
                                                  today: today, days: BalanceForecaster.daysLeftInMonth(today))
        let next30 = BalanceForecaster.forecast(startingBalance: liquidBalance, transactions: transactions, invoiceDues: invoiceDues,
                                                today: today, days: 30)
        if let negative = next30.firstNegativeDate {
            insights.append(Insight(
                id: "risk", kind: .negativeRisk, severity: .critical, title: "Risco de saldo negativo",
                message: "Pelo ritmo atual, seu saldo em contas fica negativo em \(day(negative)) e chega a \(money(next30.lowestBalance)) em \(next30.lowestDate.map(day) ?? day(negative)).",
                explanation: BalanceForecaster.explanation(for: next30) + ["Menor saldo previsto nos próximos 30 dias: \(money(next30.lowestBalance))."],
                amount: next30.lowestBalance))
        } else if next30.lowestBalance < BalanceForecaster.lowBalanceThreshold, next30.lowestDate != nil {
            insights.append(Insight(
                id: "risk", kind: .negativeRisk, severity: .warning, title: "Saldo ficará baixo",
                message: "O saldo previsto cai para \(money(next30.lowestBalance)) em \(day(next30.lowestDate!)). Fica positivo, mas com pouca folga.",
                explanation: BalanceForecaster.explanation(for: next30), amount: next30.lowestBalance))
        }
        if monthEnd.days > 0 {
            insights.append(Insight(
                id: "forecast", kind: .forecast, severity: monthEnd.projectedBalance < 0 ? .warning : .info,
                title: "Saldo previsto para o fim do mês",
                message: "Em \(day(monthEnd.endDate)) você deve ter cerca de \(money(monthEnd.projectedBalance)) (confiança \(monthEnd.confidence.displayName)).",
                explanation: BalanceForecaster.explanation(for: monthEnd), amount: monthEnd.projectedBalance))
        }

        // Atípicos
        let anomalies = AnomalyDetector.categoryAnomalies(transactions: transactions, categories: categories, today: today)
        for a in anomalies {
            let above = a.percentAbove.map { " (\(pct($0)) acima do normal)" } ?? ""
            insights.append(Insight(
                id: "anomaly:\(a.categoryId?.uuidString ?? "none"):\(a.month.label)", kind: .anomaly, severity: .warning,
                title: "Gasto atípico em \(a.categoryName)",
                message: "Você já tem \(money(a.amount)) lançados em \(a.categoryName) neste mês; o normal é cerca de \(money(a.median))\(above).",
                explanation: AnomalyDetector.explanation(for: a) + ["Se voltasse à mediana, o mês teria \(money(a.increase)) a menos de gasto."],
                amount: a.increase))
        }
        let txAnomalies = AnomalyDetector.transactionAnomalies(transactions: transactions, categories: categories, today: today)
        for a in txAnomalies.prefix(3) {
            insights.append(Insight(
                id: "anomaly:tx:\(a.transactionId.uuidString)", kind: .anomaly, severity: .info, title: "Compra acima do comum: \(a.title)",
                message: "\(money(a.amount)) em \(a.categoryName); o valor típico das suas compras nessa categoria é \(money(a.median)).",
                explanation: ["Compra: \(a.title), \(money(a.amount)).",
                              "Mediana das \(a.sampleCount) compras anteriores em \(a.categoryName): \(money(a.median)).",
                              "Pontuação robusta = \(num(a.score)) (atípico acima de \(num(AnomalyDetector.threshold))), valor ao menos 2× a mediana e \(money(AnomalyDetector.minIncrease)) acima dela."],
                amount: a.amount))
        }

        // Recorrências e assinaturas
        let recurrences = RecurrenceDetector.detect(transactions: transactions, today: today)
        if !recurrences.isEmpty {
            let monthly = recurrences.reduce(Decimal(0)) { $0 + $1.monthlyCost }
            let undeclared = recurrences.filter { !$0.isDeclared }.count
            let tail = undeclared > 0 ? " \(undeclared) ainda não \(undeclared == 1 ? "está marcada" : "estão marcadas") como recorrente no app." : ""
            insights.append(Insight(
                id: "subscriptions", kind: .subscription, severity: .info,
                title: "\(recurrences.count) \(recurrences.count == 1 ? "recorrência detectada" : "recorrências detectadas")",
                message: "Somam cerca de \(money(monthly)) por mês.\(tail)",
                explanation: recurrences.prefix(8).map(explanation) + ["Detecção: mesma descrição repetida em intervalo regular (mensal com 3+ ocorrências, semanal com 4+, anual com 2+) e ainda ativa."],
                amount: monthly))
        }
        for r in recurrences where r.priceIncreasePercent != nil {
            insights.append(Insight(
                id: "price:\(r.id)", kind: .subscription, severity: .warning, title: "\(r.title) ficou mais cara",
                message: "O último valor (\(money(r.lastAmount))) é \(pct(r.priceIncreasePercent!)) maior que o anterior.",
                explanation: ["Último valor: \(money(r.lastAmount)) em \(day(r.lastDate)).", "Mediana dos valores anteriores: \(money(r.previousAmount ?? 0)).",
                              "Aumento = (último − anterior) ÷ anterior = \(pct(r.priceIncreasePercent!))."],
                amount: r.lastAmount))
        }

        // Economia
        let savings = SavingsAdvisor.suggestions(transactions: transactions, categories: categories, recurrences: recurrences, today: today)
        for s in savings {
            insights.append(Insight(id: s.id, kind: .saving, severity: .info, title: s.title, message: s.message, explanation: s.explanation, amount: s.monthlySaving))
        }

        let history = Set(transactions.map { YearMonth($0.date) }).count
        let ordered = insights.enumerated().sorted { l, r in
            l.element.severity != r.element.severity ? l.element.severity > r.element.severity : l.offset < r.offset
        }.map(\.element)
        return InsightsReport(insights: ordered, forecastEndOfMonth: monthEnd, forecast30: next30, categoryAnomalies: anomalies,
                              transactionAnomalies: txAnomalies, recurrences: recurrences, savings: savings, hasEnoughHistory: history >= 3)
    }

    private static func explanation(_ r: DetectedRecurrence) -> String {
        let freq: String
        switch r.frequency {
        case .monthly: freq = "todo mês"
        case .weekly: freq = "toda semana"
        case .yearly: freq = "todo ano"
        }
        let stable = r.amountIsStable ? "valor fixo" : "valor varia (mediana)"
        let declared = r.isDeclared ? ", já marcada como recorrente" : ""
        return "\(r.title): \(money(r.typicalAmount)) \(freq), \(r.occurrences) ocorrências, \(stable), última em \(day(r.lastDate)), próxima esperada em \(day(r.nextExpectedDate))\(declared). Custo mensal: \(money(r.monthlyCost))."
    }
}
