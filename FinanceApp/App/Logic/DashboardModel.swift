import Foundation

/// Linha do gráfico "Para onde foi": gasto por categoria no mês e variação contra o mês anterior.
struct CategoryRow: Identifiable, Equatable, Sendable {
    var categoryId: UUID?
    var name: String
    var amount: Decimal
    var previousAmount: Decimal
    /// Parte do total de despesas, em % (Core: SummaryEngine).
    var percentOfTotal: Decimal
    /// Variação % contra o mês anterior, inteira. nil quando o mês anterior é zero.
    var deltaPercent: Int?
    var id: String { categoryId?.uuidString ?? "none" }
}

enum DashboardModel {
    /// Combina os resumos de dois meses (calculados pelo Core) em linhas prontas para exibir.
    static func categoryRows(current: MonthlySummary, previous: MonthlySummary, lookup: FinanceLookup, limit: Int = 8) -> [CategoryRow] {
        let prev = Dictionary(previous.expensesByCategory.map { ($0.categoryId, $0.amount) }, uniquingKeysWith: +)
        return current.expensesByCategory.prefix(limit).map { total in
            let before = prev[total.categoryId] ?? 0
            let delta: Int? = before == 0 ? nil : NSDecimalNumber(decimal: ((total.amount - before) * 100 / before).rounded(scale: 0)).intValue
            return CategoryRow(categoryId: total.categoryId, name: lookup.categoryName(total.categoryId), amount: total.amount,
                               previousAmount: before, percentOfTotal: total.percentOfTotal, deltaPercent: delta)
        }
    }

    /// "+12% vs set." / "−5% vs set." / "novo neste mês".
    static func deltaText(_ delta: Int?, previous: YearMonth) -> String {
        guard let delta else { return "sem gasto em \(DateText.monthShort(previous))" }
        if delta == 0 { return "igual a \(DateText.monthShort(previous))" }
        return "\(delta > 0 ? "+" : MoneyDisplay.minus)\(abs(delta))% vs \(DateText.monthShort(previous))"
    }
}
