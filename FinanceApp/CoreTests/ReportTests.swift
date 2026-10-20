import Foundation

private let food = Category(name: "Alimentação", kind: .expense)
private let rest = Category(name: "Restaurantes", kind: .expense, parentId: food.id)
private let health = Category(name: "Saúde", kind: .expense, taxKind: .health)
private let dentist = Category(name: "Dentista", kind: .expense, parentId: health.id)
private let school = Category(name: "Escola", kind: .expense, taxKind: .education)
private let salary = Category(name: "Salário", kind: .income)
private let cats = [food, rest, health, dentist, school, salary]
private let ana = UUID(), caio = UUID()
private let acc1 = UUID(), acc2 = UUID()

private func m(_ t: TransactionType, _ amount: String, _ date: Date, cat: Category? = nil, member: UUID? = nil,
               account: UUID? = nil, status: TransactionStatus = .paid, title: String = "x") -> Transaction {
    var x = Transaction(type: t, amount: dec(amount), date: date, title: title, status: status, accountId: account ?? acc1, categoryId: cat?.id)
    x.memberId = member
    return x
}

private func sample() -> [Transaction] {
    [m(.income, "5000", D(2026, 1, 5), cat: salary, member: ana),
     m(.expense, "400", D(2026, 1, 10), cat: food, member: ana),
     m(.expense, "100", D(2026, 1, 12), cat: rest, member: caio, account: acc2),
     m(.expense, "300", D(2026, 2, 3), cat: health, member: ana),
     m(.expense, "200", D(2026, 2, 4), cat: dentist, member: caio),
     m(.expense, "1500", D(2026, 2, 6), cat: school, member: caio),
     m(.expense, "50", D(2026, 3, 1), cat: food, member: ana, status: .pending),
     m(.income, "5000", D(2026, 3, 5), cat: salary, member: ana),
     Transaction(type: .transfer, amount: 999, date: D(2026, 1, 20), title: "t", accountId: acc1, destinationAccountId: acc2),
     Transaction(type: .transfer, amount: 777, date: D(2026, 1, 21), title: "fatura", accountId: acc1, creditCardId: UUID(), invoiceId: UUID()),
     m(.expense, "10", D(2025, 12, 31), cat: food, member: ana)]
}

func reportTests() -> [TestCase] {
    return [
        TestCase("relatório: período, totais e exclusão de transferências/faturas") { t in
            let f = ReportFilter(from: D(2026, 1, 1), to: D(2026, 3, 31))
            let r = ReportEngine.run(f, transactions: sample(), categories: cats)
            t.equal(r.income, 10000); t.equal(r.expense, 2550); t.equal(r.net, 7450); t.equal(r.count, 8)
            t.equal(ReportEngine.run(ReportFilter(from: D(2026, 1, 1), to: D(2026, 1, 31)), transactions: sample(), categories: cats).expense, 500)
            t.equal(ReportEngine.run(f.with(onlyPaid: true), transactions: sample(), categories: cats).expense, 2500)
        },
        TestCase("relatório: filtro por categoria inclui subcategorias") { t in
            let f = ReportFilter(from: D(2026, 1, 1), to: D(2026, 3, 31), categoryIds: [food.id])
            let r = ReportEngine.run(f, transactions: sample(), categories: cats)
            t.equal(r.expense, 550); t.equal(r.income, 0)
            t.equal(r.byCategory.map(\.id), [food.id, rest.id])
        },
        TestCase("relatório: filtro por membro e conta") { t in
            let base = ReportFilter(from: D(2026, 1, 1), to: D(2026, 3, 31))
            let c = ReportEngine.run(base.with(memberIds: [caio]), transactions: sample(), categories: cats)
            t.equal(c.expense, 1800); t.equal(c.income, 0)
            let a2 = ReportEngine.run(base.with(accountIds: [acc2]), transactions: sample(), categories: cats)
            t.equal(a2.expense, 100); t.equal(a2.count, 1)
        },
        TestCase("relatório: agrupamentos por categoria, membro, conta e mês") { t in
            let r = ReportEngine.run(ReportFilter(from: D(2026, 1, 1), to: D(2026, 3, 31)), transactions: sample(), categories: cats)
            t.equal(r.byCategory.first?.id, school.id, "maior despesa primeiro")
            t.equal(r.byCategory.first?.expense, 1500)
            let pct = r.byCategory.map(\.percentOfExpense).reduce(Decimal(0), +)
            t.check(pct >= dec("99.9") && pct <= dec("100.1"), "percentuais somam ~100: \(pct)")
            t.equal(r.byMember.first { $0.id == caio }?.expense, 1800)
            t.equal(r.byMember.first { $0.id == ana }?.income, 10000)
            t.equal(r.byAccount.first { $0.id == acc2 }?.expense, 100)
            t.equal(r.byMonth.map(\.month), [YearMonth(year: 2026, month: 1), YearMonth(year: 2026, month: 2), YearMonth(year: 2026, month: 3)])
            t.equal(r.byMonth.map(\.expense), [500, 2000, 50])
            t.equal(r.byMonth.map(\.income), [5000, 0, 5000])
            t.equal(r.transactions.first?.date, D(2026, 1, 5))
        },
        TestCase("relatório: período vazio") { t in
            let r = ReportEngine.run(ReportFilter(from: D(2030, 1, 1), to: D(2030, 1, 31)), transactions: sample(), categories: cats)
            t.equal(r.count, 0); t.equal(r.net, 0); t.equal(r.byCategory.count, 0); t.equal(r.byMonth.count, 0)
        },
        TestCase("documento: seções com nomes, páginas e CSV") { t in
            let f = ReportFilter(from: D(2026, 1, 1), to: D(2026, 3, 31))
            let r = ReportEngine.run(f, transactions: sample(), categories: cats)
            let names = ReportNames(categories: [food.id: "Alimentação", school.id: "Escola"], members: [ana: "Ana", caio: "Caio"], accounts: [acc1: "Itaú", acc2: "Nubank"])
            let doc = ReportDocumentBuilder.build(r, title: "Relatório", names: names, generatedOn: D(2026, 10, 19))
            t.equal(doc.title, "Relatório")
            t.check(doc.subtitle.contains("01/01/2026") && doc.subtitle.contains("31/03/2026"), doc.subtitle)
            let titles = doc.sections.map(\.title)
            t.equal(titles, ["Resumo", "Por categoria", "Por membro", "Por conta", "Por mês"])
            let summary = doc.sections[0].rows
            t.equal(summary.first { $0.label == "Receitas" }?.value, Money.format(10000))
            t.equal(summary.first { $0.label == "Saldo" }?.value, Money.format(7450))
            t.check(doc.sections[1].rows.contains { $0.label == "Escola" })
            let pages = doc.pages(linesPerPage: 10)
            t.check(pages.count >= 2); t.check(pages.allSatisfy { $0.count <= 10 })
            t.equal(pages.flatMap { $0 }.count, doc.lines.count)
            let csv = doc.csv()
            t.check(csv.hasPrefix("Seção;Item;Valor"))
            t.check(csv.contains("Resumo;Receitas;10000,00"), csv)
            t.check(csv.contains("Por categoria;Escola;1500,00"))
        },
        TestCase("IR: rendimentos por categoria e despesas dedutíveis (saúde herda do pai)") { t in
            let s = TaxEngine.summary(year: 2026, transactions: sample(), categories: cats)
            t.equal(s.totalIncome, 10000)
            t.equal(s.incomeLines.map(\.total), [10000])
            t.equal(s.healthTotal, 500)                 // 300 saúde + 200 dentista (subcategoria)
            t.equal(s.educationTotal, 1500)
            t.equal(s.educationDeductible, 1500)
            t.equal(s.educationExcess, 0)
            t.equal(s.totalDeductible, 2000)
            t.equal(s.deductionLines.count, 3)
            t.equal(TaxEngine.effectiveKind(of: dentist.id, categories: cats), .health)
            t.isNil(TaxEngine.effectiveKind(of: food.id, categories: cats))
        },
        TestCase("IR: limite anual de educação por pessoa") { t in
            var list: [Transaction] = []
            list.append(m(.expense, "3000", D(2026, 2, 1), cat: school, member: ana))
            list.append(m(.expense, "3000", D(2026, 2, 1), cat: school, member: caio))
            list.append(m(.expense, "1100", D(2026, 2, 1), cat: school, member: caio))
            let s = TaxEngine.summary(year: 2026, transactions: list, categories: cats)
            t.equal(s.educationTotal, 7100)
            t.equal(s.educationDeductible, dec("6561.50"), "ana 3000 integral + caio limitado a 3561,50")
            t.equal(s.educationExcess, dec("538.50"))
            let noCap = TaxEngine.summary(year: 2026, transactions: list, categories: cats, rules: TaxRules(educationAnnualLimit: nil))
            t.equal(noCap.educationDeductible, 7100)
        },
        TestCase("IR: ignora pendentes, outros anos, transferências e filtra por membro") { t in
            let s = TaxEngine.summary(year: 2026, transactions: sample() + [m(.expense, "999", D(2026, 5, 1), cat: health, status: .pending)], categories: cats)
            t.equal(s.healthTotal, 500)
            t.equal(TaxEngine.summary(year: 2025, transactions: sample(), categories: cats).totalIncome, 0)
            let c = TaxEngine.summary(year: 2026, transactions: sample(), categories: cats, memberId: caio)
            t.equal(c.healthTotal, 200); t.equal(c.educationTotal, 1500); t.equal(c.totalIncome, 0)
            let withPending = TaxEngine.summary(year: 2026, transactions: [m(.expense, "50", D(2026, 5, 1), cat: health, status: .pending)], categories: cats, onlyPaid: false)
            t.equal(withPending.healthTotal, 50)
        },
        TestCase("IR: documento exportável") { t in
            let s = TaxEngine.summary(year: 2026, transactions: sample(), categories: cats)
            let names = ReportNames(categories: [salary.id: "Salário", health.id: "Saúde", dentist.id: "Dentista", school.id: "Escola"], members: [:], accounts: [:])
            let doc = TaxEngine.document(s, names: names, memberName: nil, generatedOn: D(2026, 10, 19))
            t.check(doc.title.contains("2026"))
            t.equal(doc.sections.map(\.title), ["Rendimentos", "Despesas dedutíveis", "Totais"])
            t.check(doc.csv().contains("Despesas dedutíveis;Escola;1500,00"), doc.csv())
            t.check(doc.footer.contains("não substitui"))
        },
    ]
}

private extension ReportFilter {
    func with(onlyPaid: Bool? = nil, memberIds: Set<UUID>? = nil, accountIds: Set<UUID>? = nil) -> ReportFilter {
        var f = self
        if let onlyPaid { f.onlyPaid = onlyPaid }
        if let memberIds { f.memberIds = memberIds }
        if let accountIds { f.accountIds = accountIds }
        return f
    }
}
