import Foundation

// MARK: - Relatórios

struct ReportFilter: Sendable, Equatable {
    var from: Date
    var to: Date
    /// Vazio = todas. Inclui subcategorias.
    var categoryIds: Set<UUID> = []
    var memberIds: Set<UUID> = []
    var accountIds: Set<UUID> = []
    var onlyPaid: Bool = false
}

struct GroupTotal: Sendable, Equatable {
    /// nil = sem categoria / sem membro / sem conta.
    var id: UUID?
    var income: Decimal
    var expense: Decimal
    var count: Int
    /// Participação nas despesas do relatório (0...100, 2 casas).
    var percentOfExpense: Decimal
}

struct MonthTotal: Sendable, Equatable {
    var month: YearMonth
    var income: Decimal
    var expense: Decimal
    var net: Decimal { income - expense }
}

struct ReportResult: Sendable, Equatable {
    var filter: ReportFilter
    var income: Decimal
    var expense: Decimal
    var net: Decimal { income - expense }
    var count: Int
    var byCategory: [GroupTotal]
    var byMember: [GroupTotal]
    var byAccount: [GroupTotal]
    var byMonth: [MonthTotal]
    /// Lançamentos considerados, do mais antigo para o mais novo.
    var transactions: [Transaction]
}

enum ReportEngine {
    /// Receitas e despesas no período. Transferências e pagamentos de fatura não entram (como no resumo mensal).
    static func run(_ filter: ReportFilter, transactions: [Transaction], categories: [Category]) -> ReportResult {
        var family = Set<UUID>()
        for id in filter.categoryIds { family.formUnion(BudgetEngine.categoryFamily(id, categories: categories)) }
        let from = FinanceCalendar.startOfDay(filter.from), to = FinanceCalendar.startOfDay(filter.to)

        let selected = transactions.filter { tx in
            guard tx.type != .transfer, !tx.isInvoicePayment else { return false }
            let day = FinanceCalendar.startOfDay(tx.date)
            guard day >= from, day <= to else { return false }
            if filter.onlyPaid, tx.status != .paid { return false }
            if !family.isEmpty, !(tx.categoryId.map(family.contains) ?? false) { return false }
            if !filter.memberIds.isEmpty, !(tx.memberId.map(filter.memberIds.contains) ?? false) { return false }
            if !filter.accountIds.isEmpty, !(tx.accountId.map(filter.accountIds.contains) ?? false) { return false }
            return true
        }.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }

        let income = selected.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = selected.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + $1.amount }

        func group(_ key: (Transaction) -> UUID?) -> [GroupTotal] {
            var map: [UUID?: (Decimal, Decimal, Int)] = [:]
            for tx in selected {
                var v = map[key(tx)] ?? (0, 0, 0)
                if tx.type == .income { v.0 += tx.amount } else { v.1 += tx.amount }
                v.2 += 1
                map[key(tx)] = v
            }
            return map.map { GroupTotal(id: $0.key, income: $0.value.0, expense: $0.value.1, count: $0.value.2,
                                        percentOfExpense: expense == 0 ? 0 : ($0.value.1 * 100 / expense).rounded(scale: 2)) }
                .sorted {
                    if $0.expense != $1.expense { return $0.expense > $1.expense }
                    if $0.income != $1.income { return $0.income > $1.income }
                    return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
                }
        }

        var months: [YearMonth: (Decimal, Decimal)] = [:]
        for tx in selected {
            var v = months[YearMonth(tx.date)] ?? (0, 0)
            if tx.type == .income { v.0 += tx.amount } else { v.1 += tx.amount }
            months[YearMonth(tx.date)] = v
        }
        let byMonth = months.map { MonthTotal(month: $0.key, income: $0.value.0, expense: $0.value.1) }.sorted { $0.month < $1.month }

        return ReportResult(filter: filter, income: income, expense: expense, count: selected.count,
                            byCategory: group { $0.categoryId }, byMember: group { $0.memberId },
                            byAccount: group { $0.accountId }, byMonth: byMonth, transactions: selected)
    }
}

// MARK: - Documento exportável (PDF/CSV)

struct ReportNames: Sendable, Equatable {
    var categories: [UUID: String] = [:]
    var members: [UUID: String] = [:]
    var accounts: [UUID: String] = [:]
}

struct ReportRow: Sendable, Equatable {
    var label: String
    /// Texto exibido (já formatado).
    var value: String
    /// Valor numérico para o CSV (nil em linhas que não são dinheiro).
    var amount: Decimal?
    var detail: String?
}

struct ReportSection: Sendable, Equatable {
    var title: String
    var rows: [ReportRow]
}

struct ReportLine: Sendable, Equatable {
    enum Kind: Sendable { case title, subtitle, heading, row, note }
    var kind: Kind
    var left: String
    var right: String = ""
}

/// Documento neutro de apresentação: o App desenha em PDF; o Core gera o CSV e a paginação.
struct ReportDocument: Sendable, Equatable {
    var title: String
    var subtitle: String
    var generatedOn: String
    var sections: [ReportSection]
    var footer: String

    var lines: [ReportLine] {
        var result = [ReportLine(kind: .title, left: title), ReportLine(kind: .subtitle, left: subtitle, right: generatedOn)]
        for s in sections {
            result.append(ReportLine(kind: .heading, left: s.title))
            for r in s.rows { result.append(ReportLine(kind: .row, left: r.detail.map { "\(r.label) (\($0))" } ?? r.label, right: r.value)) }
        }
        result.append(ReportLine(kind: .note, left: footer))
        return result
    }

    func pages(linesPerPage: Int) -> [[ReportLine]] {
        let n = max(linesPerPage, 1)
        let all = lines
        return stride(from: 0, to: all.count, by: n).map { Array(all[$0..<min($0 + n, all.count)]) }
    }

    /// `;` como separador e vírgula decimal (abre no Excel pt-BR). O BOM é responsabilidade de quem grava o arquivo.
    func csv() -> String {
        func esc(_ s: String) -> String {
            s.contains(";") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var out = ["Seção;Item;Valor"]
        for s in sections {
            for r in s.rows {
                let value = r.amount.map { Money.plain($0) } ?? r.value
                out.append([esc(s.title), esc(r.label), esc(value)].joined(separator: ";"))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}

enum ReportDocumentBuilder {
    static func dateText(_ date: Date) -> String {
        let c = FinanceCalendar.components(date)
        return String(format: "%02d/%02d/%04d", c.day, c.month, c.year)
    }

    static func build(_ r: ReportResult, title: String, names: ReportNames, generatedOn: Date) -> ReportDocument {
        func rows(_ list: [GroupTotal], _ lookup: [UUID: String], none: String) -> [ReportRow] {
            list.map { g in
                let label = g.id.map { lookup[$0] ?? "Sem nome" } ?? none
                let net = g.expense > 0 || g.income == 0 ? g.expense : g.income
                return ReportRow(label: label, value: Money.format(net), amount: net,
                                 detail: g.expense > 0 ? "\(g.percentOfExpense)%" : "receita")
            }
        }
        var sections = [ReportSection(title: "Resumo", rows: [
            ReportRow(label: "Receitas", value: Money.format(r.income), amount: r.income),
            ReportRow(label: "Despesas", value: Money.format(r.expense), amount: r.expense),
            ReportRow(label: "Saldo", value: Money.format(r.net), amount: r.net),
            ReportRow(label: "Lançamentos", value: "\(r.count)", amount: nil),
        ])]
        sections.append(ReportSection(title: "Por categoria", rows: rows(r.byCategory, names.categories, none: "Sem categoria")))
        sections.append(ReportSection(title: "Por membro", rows: rows(r.byMember, names.members, none: "Sem membro")))
        sections.append(ReportSection(title: "Por conta", rows: rows(r.byAccount, names.accounts, none: "Cartão ou sem conta")))
        sections.append(ReportSection(title: "Por mês", rows: r.byMonth.map {
            ReportRow(label: $0.month.label, value: Money.format($0.net), amount: $0.net,
                      detail: "receitas \(Money.format($0.income)), despesas \(Money.format($0.expense))")
        }))
        return ReportDocument(title: title,
                              subtitle: "Período: \(dateText(r.filter.from)) a \(dateText(r.filter.to))",
                              generatedOn: "Gerado em \(dateText(generatedOn))",
                              sections: sections,
                              footer: "Gerado localmente pelo app Finanças. Valores em reais (BRL).")
    }
}

// MARK: - Imposto de Renda

struct TaxRules: Sendable, Equatable {
    /// Limite anual de dedução com instrução, POR PESSOA (titular e cada dependente). nil = sem limite.
    /// O valor padrão é o da tabela vigente em 2025 e muda por lei: confira na Receita Federal.
    var educationAnnualLimit: Decimal? = dec("3561.50")
    static let `default` = TaxRules()
}

struct TaxIncomeLine: Sendable, Equatable {
    var categoryId: UUID?
    var total: Decimal
}

struct TaxDeductionLine: Sendable, Equatable {
    var kind: TaxDeductionKind
    var categoryId: UUID?
    var total: Decimal
    var count: Int
}

struct TaxSummary: Sendable, Equatable {
    var year: Int
    var incomeLines: [TaxIncomeLine]
    var totalIncome: Decimal
    var deductionLines: [TaxDeductionLine]
    var healthTotal: Decimal
    var educationTotal: Decimal
    /// Educação limitada por pessoa.
    var educationDeductible: Decimal
    var educationExcess: Decimal { educationTotal - educationDeductible }
    var totalDeductible: Decimal { healthTotal + educationDeductible }
}

enum TaxEngine {
    /// Tipo dedutível da categoria; subcategorias herdam do pai.
    static func effectiveKind(of categoryId: UUID?, categories: [Category]) -> TaxDeductionKind? {
        var current = categoryId
        var guardCount = 0
        while let id = current, guardCount < 20, let c = categories.first(where: { $0.id == id }) {
            if let k = c.taxKind { return k }
            current = c.parentId
            guardCount += 1
        }
        return nil
    }

    /// Resumo do ano-calendário. `memberId` restringe a um membro. Despesas de educação são limitadas por beneficiário
    /// (`Transaction.memberId`; sem membro conta como uma única pessoa, o titular).
    static func summary(year: Int, transactions: [Transaction], categories: [Category], rules: TaxRules = .default,
                        memberId: UUID? = nil, onlyPaid: Bool = true) -> TaxSummary {
        let list = transactions.filter { tx in
            tx.type != .transfer && !tx.isInvoicePayment && FinanceCalendar.components(tx.date).year == year
                && (!onlyPaid || tx.status == .paid) && (memberId == nil || tx.memberId == memberId)
        }
        var incomes: [UUID?: Decimal] = [:]
        var deductions: [String: TaxDeductionLine] = [:]
        var educationByPerson: [UUID?: Decimal] = [:]
        var health: Decimal = 0, education: Decimal = 0
        for tx in list {
            if tx.type == .income { incomes[tx.categoryId, default: 0] += tx.amount; continue }
            guard let kind = effectiveKind(of: tx.categoryId, categories: categories) else { continue }
            let key = "\(kind.rawValue)|\(tx.categoryId?.uuidString ?? "")"
            var line = deductions[key] ?? TaxDeductionLine(kind: kind, categoryId: tx.categoryId, total: 0, count: 0)
            line.total += tx.amount; line.count += 1
            deductions[key] = line
            switch kind {
            case .health: health += tx.amount
            case .education: education += tx.amount; educationByPerson[tx.memberId, default: 0] += tx.amount
            }
        }
        let deductibleEducation = educationByPerson.values.reduce(Decimal(0)) { acc, v in
            acc + (rules.educationAnnualLimit.map { min(v, $0) } ?? v)
        }
        var incomeLines: [TaxIncomeLine] = incomes.map { TaxIncomeLine(categoryId: $0.key, total: $0.value) }
        incomeLines.sort { (a: TaxIncomeLine, b: TaxIncomeLine) -> Bool in
            if a.total != b.total { return a.total > b.total }
            return (a.categoryId?.uuidString ?? "") < (b.categoryId?.uuidString ?? "")
        }
        let lines = deductions.values.sorted { (a: TaxDeductionLine, b: TaxDeductionLine) -> Bool in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            if a.total != b.total { return a.total > b.total }
            return (a.categoryId?.uuidString ?? "") < (b.categoryId?.uuidString ?? "")
        }
        return TaxSummary(year: year, incomeLines: incomeLines, totalIncome: incomes.values.reduce(0, +), deductionLines: lines,
                          healthTotal: health, educationTotal: education, educationDeductible: deductibleEducation)
    }

    static func document(_ s: TaxSummary, names: ReportNames, memberName: String?, generatedOn: Date) -> ReportDocument {
        let incomeRows = s.incomeLines.map {
            ReportRow(label: $0.categoryId.flatMap { names.categories[$0] } ?? "Sem categoria", value: Money.format($0.total), amount: $0.total)
        }
        let deductionRows = s.deductionLines.map {
            ReportRow(label: $0.categoryId.flatMap { names.categories[$0] } ?? $0.kind.displayName, value: Money.format($0.total),
                      amount: $0.total, detail: "\($0.kind.displayName), \($0.count) lançamentos")
        }
        let totals = [
            ReportRow(label: "Total de rendimentos", value: Money.format(s.totalIncome), amount: s.totalIncome),
            ReportRow(label: "Saúde (sem limite)", value: Money.format(s.healthTotal), amount: s.healthTotal),
            ReportRow(label: "Educação (informada)", value: Money.format(s.educationTotal), amount: s.educationTotal),
            ReportRow(label: "Educação dedutível (limite por pessoa)", value: Money.format(s.educationDeductible), amount: s.educationDeductible),
            ReportRow(label: "Total dedutível", value: Money.format(s.totalDeductible), amount: s.totalDeductible),
        ]
        return ReportDocument(title: "Resumo para o Imposto de Renda \(s.year)",
                              subtitle: memberName.map { "Ano-calendário \(s.year), \($0)" } ?? "Ano-calendário \(s.year), toda a família",
                              generatedOn: "Gerado em \(ReportDocumentBuilder.dateText(generatedOn))",
                              sections: [ReportSection(title: "Rendimentos", rows: incomeRows),
                                         ReportSection(title: "Despesas dedutíveis", rows: deductionRows),
                                         ReportSection(title: "Totais", rows: totals)],
                              footer: "Este resumo é um auxílio e não substitui informes de rendimentos, recibos e notas fiscais. Confira regras e limites vigentes com a Receita Federal.")
    }
}
