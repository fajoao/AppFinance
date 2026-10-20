import Foundation

enum FilterPeriod: String, CaseIterable, Sendable, Identifiable {
    case thisMonth, lastMonth, last30Days, thisYear, all
    var id: String { rawValue }
    /// "Este mês"/"Mês passado" só valem para o mês atual; em outro mês visualizado mostra o nome do mês.
    func title(viewed: YearMonth, today: Date) -> String {
        guard !PeriodSelection.isCurrent(viewed, today: today) else { return title }
        switch self {
        case .thisMonth: return DateText.monthYear(viewed)
        case .lastMonth: return DateText.monthYear(viewed.previous)
        case .thisYear: return "Ano de \(viewed.year)"
        default: return title
        }
    }
    var title: String {
        switch self {
        case .thisMonth: return "Este mês"
        case .lastMonth: return "Mês passado"
        case .last30Days: return "Últimos 30 dias"
        case .thisYear: return "Este ano"
        case .all: return "Tudo"
        }
    }
}

enum TypeFilter: String, CaseIterable, Sendable, Identifiable {
    case all, expense, income, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todos"
        case .expense: return "Despesas"
        case .income: return "Receitas"
        case .transfer: return "Transferências"
        }
    }
}

struct DayGroup: Identifiable, Equatable, Sendable {
    var date: Date
    var items: [Transaction]
    /// Resultado do dia (receitas − despesas; transferências e pagamentos de fatura não entram).
    var total: Decimal
    var id: Date { date }
}

/// Busca e filtros da lista de lançamentos (puro, sem UI).
struct TransactionFilter: Equatable, Sendable {
    var query: String = ""
    var period: FilterPeriod = .thisMonth
    var type: TypeFilter = .all
    /// Ids de contas e cartões.
    var sourceIds: Set<UUID> = []
    var categoryIds: Set<UUID> = []
    var tagId: UUID? = nil
    var minAmount: Decimal? = nil
    var maxAmount: Decimal? = nil

    /// Quantos filtros avançados (sheet) estão ativos: período fora do padrão, tipo, fontes, categorias, valor, tag.
    var advancedCount: Int {
        var n = 0
        if period != .thisMonth { n += 1 }
        if type != .all { n += 1 }
        if !sourceIds.isEmpty { n += 1 }
        if !categoryIds.isEmpty { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        if tagId != nil { n += 1 }
        return n
    }

    var isDefault: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && advancedCount == 0 }

    mutating func reset() { self = TransactionFilter() }

    /// `month`: mês visualizado (nil = mês de `today`). "Este mês", "Mês passado" e "Este ano" são relativos a ele;
    /// "Últimos 30 dias" continua contando a partir de hoje.
    func matches(_ tx: Transaction, lookup: FinanceLookup, today: Date, month: YearMonth? = nil) -> Bool {
        guard periodMatches(tx.date, today: today, month: month ?? YearMonth(today)) else { return false }
        switch type {
        case .all: break
        case .expense: if tx.type != .expense { return false }
        case .income: if tx.type != .income { return false }
        case .transfer: if tx.type != .transfer { return false }
        }
        if !sourceIds.isEmpty {
            let ids = [tx.accountId, tx.destinationAccountId, tx.creditCardId].compactMap { $0 }
            if !ids.contains(where: sourceIds.contains) { return false }
        }
        if !categoryIds.isEmpty {
            guard let c = tx.categoryId else { return false }
            let parent = lookup.categories[c]?.parentId
            if !categoryIds.contains(c) && !(parent.map(categoryIds.contains) ?? false) { return false }
        }
        if let tagId, !tx.tagIds.contains(tagId) { return false }
        if let minAmount, tx.amount.magnitude < minAmount { return false }
        if let maxAmount, tx.amount.magnitude > maxAmount { return false }
        let q = TextDecoding.normalize(query)
        if !q.isEmpty {
            var haystack = [tx.title, lookup.categoryName(tx.categoryId), lookup.accountLabel(of: tx)]
            haystack.append(contentsOf: lookup.tagNames(of: tx))
            if let note = tx.note { haystack.append(note) }
            if !haystack.contains(where: { TextDecoding.normalize($0).contains(q) }) { return false }
        }
        return true
    }

    private func periodMatches(_ date: Date, today: Date, month: YearMonth) -> Bool {
        switch period {
        case .all: return true
        case .thisMonth: return YearMonth(date) == month
        case .lastMonth: return YearMonth(date) == month.previous
        case .thisYear: return FinanceCalendar.components(date).year == month.year
        case .last30Days:
            let d = FinanceCalendar.daysBetween(date, today)
            return d >= 0 && d <= 30
        }
    }

    func apply(to transactions: [Transaction], lookup: FinanceLookup, today: Date, month: YearMonth? = nil) -> [Transaction] {
        transactions
            .filter { matches($0, lookup: lookup, today: today, month: month) }
            .sorted { a, b in
                let da = FinanceCalendar.startOfDay(a.date), db = FinanceCalendar.startOfDay(b.date)
                return da != db ? da > db : a.createdAt > b.createdAt
            }
    }

    /// Agrupa (já ordenado, mais recente primeiro) por dia civil.
    static func groupByDay(_ sorted: [Transaction]) -> [DayGroup] {
        var groups: [DayGroup] = []
        for tx in sorted {
            let day = FinanceCalendar.startOfDay(tx.date)
            if let last = groups.last, last.date == day {
                groups[groups.count - 1].items.append(tx)
                groups[groups.count - 1].total += tx.signedAmount
            } else {
                groups.append(DayGroup(date: day, items: [tx], total: tx.signedAmount))
            }
        }
        return groups
    }

    static func result(of list: [Transaction]) -> Decimal { list.reduce(0) { $0 + $1.signedAmount } }

    /// "Hoje", "Ontem" ou "Sábado, 17 de outubro".
    static func dayTitle(_ date: Date, today: Date) -> String {
        let d = FinanceCalendar.daysBetween(date, today)
        if d == 0 { return "Hoje" }
        if d == 1 { return "Ontem" }
        return DateText.weekdayDayMonth(date)
    }
}

/// Textos de data em pt-BR sem depender de DateFormatter/locale (determinístico em testes e no Simulador).
enum DateText {
    static let months = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
    static let months3 = ["jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez."]
    static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
    static let weekdays1 = ["D", "S", "T", "Q", "Q", "S", "S"]

    static func weekdayIndex(_ date: Date) -> Int { FinanceCalendar.calendar.component(.weekday, from: date) - 1 }

    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func weekdayDayMonth(_ date: Date) -> String {
        let c = FinanceCalendar.components(date)
        return "\(capitalized(weekdays[weekdayIndex(date)])), \(c.day) de \(months[c.month - 1])"
    }

    /// "19 out."
    static func dayMonthShort(_ date: Date) -> String {
        let c = FinanceCalendar.components(date)
        return "\(c.day) \(months3[c.month - 1])"
    }

    /// "19 de outubro de 2026"
    static func full(_ date: Date) -> String {
        let c = FinanceCalendar.components(date)
        return "\(c.day) de \(months[c.month - 1]) de \(c.year)"
    }

    /// "Outubro de 2026"
    static func monthYear(_ ym: YearMonth) -> String { "\(capitalized(months[ym.month - 1])) de \(ym.year)" }

    static func monthName(_ ym: YearMonth) -> String { capitalized(months[ym.month - 1]) }
    static func monthNameLower(_ ym: YearMonth) -> String { months[ym.month - 1] }
    static func monthShort(_ ym: YearMonth) -> String { months3[ym.month - 1] }
}
