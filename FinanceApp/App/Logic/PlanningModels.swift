import Foundation

// MARK: - Simulador de dívidas

struct DebtChartPoint: Equatable, Sendable, Identifiable {
    var month: Int
    var strategy: PayoffStrategy
    var balance: Decimal
    var id: String { "\(strategy.rawValue)-\(month)" }
}

struct DebtComparison: Equatable, Sendable {
    var avalanche: PayoffResult
    var snowball: PayoffResult
    var interestSavedByAvalanche: Decimal
    var initialTotal: Decimal

    /// Estratégia recomendada. Quem consegue quitar vence; se ambas quitam, a que paga menos juros
    /// (empate: bola de neve, que costuma motivar mais). Se nenhuma quita, a de menor saldo restante ao fim da simulação.
    var recommended: PayoffStrategy {
        switch (avalanche.feasible, snowball.feasible) {
        case (true, false): return .avalanche
        case (false, true): return .snowball
        case (false, false):
            return (avalanche.monthlyBalances.last ?? 0) <= (snowball.monthlyBalances.last ?? 0) ? .avalanche : .snowball
        case (true, true): return interestSavedByAvalanche > 0 ? .avalanche : .snowball
        }
    }

    /// Só uma das estratégias consegue quitar com o orçamento informado.
    var onlyOneFeasible: PayoffStrategy? {
        switch (avalanche.feasible, snowball.feasible) {
        case (true, false): return .avalanche
        case (false, true): return .snowball
        default: return nil
        }
    }

    func result(for s: PayoffStrategy) -> PayoffResult { s == .avalanche ? avalanche : snowball }

    /// Data estimada de quitação (hoje + meses).
    func payoffDate(_ s: PayoffStrategy, today: Date) -> Date? {
        let r = result(for: s)
        return r.feasible ? FinanceCalendar.addMonths(today, r.months) : nil
    }

    /// Série para o gráfico de linhas (mês 0 = saldo atual).
    var chartPoints: [DebtChartPoint] {
        var pts: [DebtChartPoint] = []
        for s in PayoffStrategy.allCases {
            pts.append(DebtChartPoint(month: 0, strategy: s, balance: initialTotal))
            for (i, b) in result(for: s).monthlyBalances.enumerated() { pts.append(DebtChartPoint(month: i + 1, strategy: s, balance: b)) }
        }
        return pts
    }

    var isFeasible: Bool { avalanche.feasible && snowball.feasible }
}

enum DebtSimulation {
    /// Soma dos pagamentos mínimos (orçamento mensal mínimo aceito pelo simulador).
    static func minimumBudget(_ debts: [Debt]) -> Decimal {
        debts.filter { $0.balance > 0 }.reduce(Decimal(0)) { $0 + $1.minimumPayment }
    }

    static func run(debts: [Debt], monthlyBudget: Decimal) throws -> DebtComparison {
        let c = try DebtEngine.compare(debts: debts, monthlyBudget: monthlyBudget)
        return DebtComparison(avalanche: c.avalanche, snowball: c.snowball, interestSavedByAvalanche: c.interestSavedByAvalanche,
                              initialTotal: debts.filter { $0.balance > 0 }.reduce(Decimal(0)) { $0 + $1.balance })
    }

    /// "1 ano e 3 meses", "8 meses".
    static func durationText(months: Int) -> String {
        let y = months / 12, m = months % 12
        var parts: [String] = []
        if y > 0 { parts.append(y == 1 ? "1 ano" : "\(y) anos") }
        if m > 0 || y == 0 { parts.append(m == 1 ? "1 mês" : "\(m) meses") }
        return parts.joined(separator: " e ")
    }
}

// MARK: - Fluxo de caixa

struct CashFlowSummary: Equatable, Sendable {
    var days: Int
    var endingBalance: Decimal
    var lowestBalance: Decimal
    var lowestDate: Date?
    var goesNegative: Bool
    var totalIn: Decimal
    var totalOut: Decimal
    var headline: String
}

enum CashFlowModel {
    static func summary(_ p: CashFlowProjection) -> CashFlowSummary {
        let headline: String
        if p.goesNegative, let d = p.lowestBalanceDate {
            headline = "Atenção: o saldo fica negativo, no pior ponto em \(DateText.dayMonthShort(d))."
        } else {
            headline = "O saldo se mantém positivo nos próximos \(p.days) dias."
        }
        return CashFlowSummary(days: p.days, endingBalance: p.endingBalance, lowestBalance: p.lowestBalance,
                               lowestDate: p.lowestBalanceDate, goesNegative: p.goesNegative,
                               totalIn: p.totalIn, totalOut: p.totalOut, headline: headline)
    }

    /// Pontos do gráfico incluindo o saldo inicial (dia 0).
    static func chartPoints(_ p: CashFlowProjection, today: Date) -> [CashFlowPoint] {
        [CashFlowPoint(date: today, change: 0, balance: p.startingBalance)] + p.points
    }
}

// MARK: - Período de relatório

enum ReportPeriod: String, CaseIterable, Sendable, Identifiable {
    case thisMonth, lastMonth, last3Months, thisYear, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thisMonth: return "Este mês"
        case .lastMonth: return "Mês passado"
        case .last3Months: return "3 meses"
        case .thisYear: return "Este ano"
        case .custom: return "Personalizado"
        }
    }

    /// Texto do chip: "Este mês" só no mês atual; em outro mês visualizado mostra o nome dele.
    func title(viewed: YearMonth, today: Date) -> String {
        switch self {
        case .thisMonth: return PeriodSelection.isCurrent(viewed, today: today) ? title : DateText.monthYear(viewed)
        case .lastMonth: return PeriodSelection.isCurrent(viewed, today: today) ? title : DateText.monthYear(viewed.previous)
        case .thisYear: return PeriodSelection.isCurrent(viewed, today: today) ? title : "Ano de \(viewed.year)"
        default: return title
        }
    }

    /// `month`: mês visualizado (nil = mês de `today`). Os períodos "Este mês", "Mês passado", "3 meses" e "Este ano" são relativos a ele.
    func range(today: Date, custom: (from: Date, to: Date)? = nil, month: YearMonth? = nil) -> (from: Date, to: Date) {
        let ym = month ?? YearMonth(today)
        switch self {
        case .thisMonth: return (ym.firstDay, ym.lastDay)
        case .lastMonth: return (ym.previous.firstDay, ym.previous.lastDay)
        case .last3Months: return (ym.adding(months: -2).firstDay, ym.lastDay)
        case .thisYear: return (FinanceCalendar.date(ym.year, 1, 1), FinanceCalendar.date(ym.year, 12, 31))
        case .custom: return custom ?? (ym.firstDay, ym.lastDay)
        }
    }
}
