import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

private func tx(_ type: TransactionType, _ amount: String, _ date: Date, _ title: String, account: UUID? = nil,
                category: UUID? = nil, status: TransactionStatus = .paid) -> Transaction {
    Transaction(type: type, amount: dec(amount), date: date, title: title, status: status, accountId: account, categoryId: category)
}

func filterTests() -> [TestCase] {
    let acc = Account(name: "Nubank", type: .checking)
    let mercado = Category(name: "Mercado", kind: .expense)
    let tag = Tag(name: "família")
    let lookup = FinanceLookup(accounts: [acc], categories: [mercado], tags: [tag], cards: [])
    var tagged = tx(.expense, "50", D(2026, 10, 10), "Padaria", account: acc.id, category: mercado.id)
    tagged.tagIds = [tag.id]
    let list = [
        tx(.expense, "100", D(2026, 10, 18), "Carrefour", account: acc.id, category: mercado.id),
        tx(.income, "5000", D(2026, 10, 5), "Salário", account: acc.id),
        tx(.expense, "30", D(2026, 9, 20), "Uber", account: acc.id),
        tagged,
        tx(.transfer, "200", D(2026, 10, 6), "Reserva", account: acc.id),
    ]
    return [
        TestCase("período padrão é o mês atual") { t in
            let r = TransactionFilter().apply(to: list, lookup: lookup, today: testToday)
            t.equal(r.count, 4)
            t.equal(r.first?.title, "Carrefour")  // mais recente primeiro
        },
        TestCase("busca ignora acento e caixa; procura em nome, categoria, tag e conta") { t in
            var f = TransactionFilter(); f.period = .all
            f.query = "SALARIO"; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 1)
            f.query = "mercado"; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 2)
            f.query = "familia"; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 1)
            f.query = "nubank"; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 5)
            f.query = "zzz"; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 0)
        },
        TestCase("filtros de tipo, valor, categoria e contagem de filtros ativos") { t in
            var f = TransactionFilter()
            t.equal(f.advancedCount, 0); t.check(f.isDefault)
            f.type = .expense; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 2)
            f.minAmount = dec("60"); t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 1)
            f.categoryIds = [mercado.id]; f.period = .all
            t.equal(f.advancedCount, 4)
            t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 1)
            f.reset(); t.check(f.isDefault)
        },
        TestCase("períodos: mês passado, 30 dias, ano") { t in
            var f = TransactionFilter(); f.period = .lastMonth
            t.equal(f.apply(to: list, lookup: lookup, today: testToday).map(\.title), ["Uber"])
            f.period = .last30Days; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 5)
            f.period = .thisYear; t.equal(f.apply(to: list, lookup: lookup, today: testToday).count, 5)
        },
        TestCase("agrupa por dia com total do dia (transferência não entra)") { t in
            var f = TransactionFilter(); f.period = .all
            let sorted = f.apply(to: list, lookup: lookup, today: testToday)
            let groups = TransactionFilter.groupByDay(sorted)
            t.equal(groups.count, 5)
            t.equal(groups[0].total, dec("-100"))
            t.equal(TransactionFilter.result(of: sorted), dec("5000") - dec("100") - dec("30") - dec("50"))
            t.equal(TransactionFilter.dayTitle(D(2026, 10, 19), today: testToday), "Hoje")
            t.equal(TransactionFilter.dayTitle(D(2026, 10, 18), today: testToday), "Ontem")
            t.equal(TransactionFilter.dayTitle(D(2026, 10, 17), today: testToday), "Sábado, 17 de outubro")
        },
        TestCase("datas em português") { t in
            t.equal(DateText.monthYear(YearMonth(year: 2026, month: 10)), "Outubro de 2026")
            t.equal(DateText.dayMonthShort(D(2026, 3, 5)), "5 mar.")
            t.equal(DateText.full(D(2026, 10, 19)), "19 de outubro de 2026")
            t.equal(DateText.weekdayIndex(D(2026, 10, 19)), 1) // segunda-feira
        },
    ]
}

func draftTests() -> [TestCase] {
    let acc = Account(name: "Nubank", type: .checking)
    let acc2 = Account(name: "Poupança", type: .savings)
    let card = CreditCard(name: "Cartão", limit: 5000, closingDay: 3, dueDay: 10)
    func draft(_ amount: String, type: TransactionType = .expense, source: TransactionDraft.Source? = .account(acc.id)) -> TransactionDraft {
        var d = TransactionDraft(date: testToday, type: type)
        for ch in amount { if ch == "," { d.keypad.press(.comma) } else if let n = ch.wholeNumberValue { d.keypad.press(.digit(n)) } }
        d.source = source
        return d
    }
    return [
        TestCase("valida valor, origem e destino") { t in
            t.equal(draft("").validate(), .zeroAmount)
            t.equal(draft("10", source: nil).validate(), .missingSource)
            var tr = draft("10", type: .transfer)
            t.equal(tr.validate(), .missingDestination)
            tr.destinationAccountId = acc.id
            t.equal(tr.validate(), .sameAccount)
            tr.destinationAccountId = acc2.id
            t.isNil(tr.validate())
            t.throwsError(DraftError.zeroAmount) { try draft("").makeTransactions(cards: [], today: testToday) }
        },
        TestCase("despesa à vista na conta") { t in
            var d = draft("45,90"); d.title = "  Padaria  "
            let list = try d.makeTransactions(cards: [], today: testToday)
            t.equal(list.count, 1)
            t.equal(list[0].amount, dec("45.9")); t.equal(list[0].title, "Padaria")
            t.equal(list[0].status, .paid); t.equal(list[0].accountId, acc.id)
        },
        TestCase("título vazio usa o nome do tipo") { t in
            t.equal(draft("1").effectiveTitle, "Despesa")
            t.equal(draft("1", type: .income).effectiveTitle, "Receita")
        },
        TestCase("data futura fica pendente (aparece em A pagar)") { t in
            var d = draft("100"); d.date = D(2026, 10, 25)
            t.equal(try d.makeTransactions(cards: [], today: testToday)[0].status, .pending)
        },
        TestCase("parcelado na conta: soma fecha e só a 1ª é paga") { t in
            var d = draft("1000"); d.repeatRule = .installments(3); d.title = "TV"
            let list = try d.makeTransactions(cards: [], today: testToday)
            t.equal(list.count, 3)
            t.equal(list.reduce(Decimal(0)) { $0 + $1.amount }, 1000)
            t.equal(list.map(\.status), [.paid, .pending, .pending])
            t.equal(list[2].title, "TV (3/3)")
            t.equal(d.installmentSummary(), "3x de R$\u{00A0}333,33, última R$\u{00A0}333,34")
        },
        TestCase("compra parcelada no cartão usa o Core") { t in
            var d = draft("600", source: .card(card.id)); d.repeatRule = .installments(6)
            let list = try d.makeTransactions(cards: [card], today: testToday)
            t.equal(list.count, 6); t.check(list.allSatisfy { $0.creditCardId == card.id && $0.accountId == nil })
            t.equal(list.reduce(Decimal(0)) { $0 + $1.amount }, 600)
            t.throwsError(DraftError.cardNotFound) { try d.makeTransactions(cards: [], today: testToday) }
        },
        TestCase("transferência gera uma transferência com destino") { t in
            var d = draft("250", type: .transfer); d.destinationAccountId = acc2.id
            let tx = try d.makeTransactions(cards: [], today: testToday)[0]
            t.equal(tx.type, .transfer); t.equal(tx.destinationAccountId, acc2.id)
        },
        TestCase("recorrência mensal e semanal definem regra no modelo") { t in
            var d = draft("10"); d.repeatRule = .monthly
            t.equal(try d.makeTransactions(cards: [], today: testToday)[0].recurrence?.frequency, .monthly)
            d.repeatRule = .weekly
            t.equal(try d.makeTransactions(cards: [], today: testToday)[0].recurrence?.frequency, .weekly)
        },
        TestCase("trocar o tipo limpa categoria e remove cartão/parcelas incompatíveis") { t in
            var d = draft("10", source: .card(card.id)); d.repeatRule = .installments(4)
            d.chooseCategory(UUID())
            d.changeType(.income)
            t.isNil(d.categoryId); t.isNil(d.source); t.equal(d.repeatRule, .none)
        },
        TestCase("sugestão de categoria: aplica até a pessoa escolher manualmente") { t in
            let mercado = Category(name: "Mercado", kind: .expense), lazer = Category(name: "Lazer", kind: .expense)
            let sug = CategorySuggester(keywords: [mercado.id: ["padaria"], lazer.id: ["cinema"]])
            var d = draft("10")
            d.title = "Padaria Real"; d.descriptionChanged(suggester: sug)
            t.equal(d.categoryId, mercado.id); t.check(d.categoryIsSuggested)
            d.title = "Cinema Kinoplex"; d.descriptionChanged(suggester: sug)
            t.equal(d.categoryId, lazer.id)
            d.chooseCategory(mercado.id)
            d.title = "Cinema de novo"; d.descriptionChanged(suggester: sug)
            t.equal(d.categoryId, mercado.id); t.check(!d.categoryIsSuggested)
        },
    ]
}

func billsTests() -> [TestCase] {
    func bill(_ due: Date, paid: Bool = false, dir: BillDirection = .payable) -> BillItem {
        BillItem(id: UUID().uuidString, title: "Conta", amount: 100, dueDate: due, direction: dir, isPaid: paid)
    }
    return [
        TestCase("status por proximidade do vencimento") { t in
            t.equal(BillsModel.status(of: bill(D(2026, 10, 15)), today: testToday), .overdue(days: 4, receivable: false))
            t.equal(BillsModel.status(of: bill(D(2026, 10, 19)), today: testToday), .dueToday)
            t.equal(BillsModel.status(of: bill(D(2026, 10, 20)), today: testToday).label, "Vence amanhã")
            t.equal(BillsModel.status(of: bill(D(2026, 10, 22)), today: testToday).label, "Vence em 3 dias")
            t.equal(BillsModel.status(of: bill(D(2026, 10, 23)), today: testToday), .pending)
            t.equal(BillsModel.status(of: bill(D(2026, 10, 15), paid: true), today: testToday).label, "Pago")
            t.equal(BillsModel.status(of: bill(D(2026, 10, 30), dir: .receivable), today: testToday).label, "A receber")
            t.equal(BillsModel.status(of: bill(D(2026, 10, 15), dir: .receivable), today: testToday).label, "Recebimento atrasado")
            t.equal(BillsModel.status(of: bill(D(2026, 10, 18)), today: testToday).label, "Atrasado 1 dia")
        },
        TestCase("totais a pagar e a receber ignoram o que já foi pago") { t in
            let items = [bill(D(2026, 10, 20)), bill(D(2026, 10, 21), paid: true), bill(D(2026, 10, 30), dir: .receivable)]
            let totals = BillsModel.totals(items)
            t.equal(totals.toPay, 100); t.equal(totals.toReceive, 100)
        },
        TestCase("calendário: outubro de 2026 começa na quinta e tem 5 semanas") { t in
            let weeks = BillsModel.calendarWeeks(for: YearMonth(year: 2026, month: 10))
            t.equal(weeks.count, 5)
            t.check(weeks[0][4] != nil && weeks[0][3] == nil)   // 1/10/2026 é quinta-feira (índice 4)
            t.equal(weeks[0].compactMap { $0 }.count, 3)
            t.equal(weeks.flatMap { $0 }.compactMap { $0 }.count, 31)
        },
        TestCase("pontos do dia na ordem de gravidade") { t in
            let day = D(2026, 10, 15)
            let items = [bill(day), bill(day, paid: true)]
            t.equal(BillsModel.dots(on: day, bills: items, today: testToday), [.danger, .ok])
            t.equal(BillsModel.dots(on: D(2026, 10, 16), bills: items, today: testToday), [])
        },
        TestCase("lembretes: antecedência, ignora pagas, passadas e recebimentos") { t in
            let items = [bill(D(2026, 10, 25)), bill(D(2026, 10, 25), paid: true), bill(D(2026, 10, 18)),
                         bill(D(2026, 10, 26), dir: .receivable), bill(D(2026, 10, 20))]
            let plan = ReminderPlanner.plan(bills: items, today: testToday, daysBefore: 1)
            // 25 -> aviso dia 24; 20 -> aviso dia 19 (hoje); 18 -> aviso dia 17 (passou)
            t.equal(plan.map { $0.day }, [19, 24])
            t.equal(plan[1].body, "Conta vence amanhã: R$\u{00A0}100,00.")
            t.equal(plan[0].hour, 9)
            t.equal(ReminderPlanner.plan(bills: items, today: testToday, daysBefore: 0).map { $0.day }, [20, 25])
        },
    ]
}

func payInvoiceTests() -> [TestCase] {
    [
        TestCase("pagar fatura: total, mínimo de 15% arredondado para cima e outro valor") { t in
            var m = PayInvoiceModel(remaining: dec("2104.77"))
            t.equal(m.amount, dec("2104.77")); t.check(!m.leavesRevolvingBalance)
            m.option = .minimum
            t.equal(m.minimum, dec("315.72"))        // 315,7155 -> 315,72
            t.check(m.leavesRevolvingBalance)
            m.option = .custom; m.customText = "500,00"
            t.equal(m.amount, 500); t.isNil(m.amountError)
            m.customText = "3.000,00"
            t.check(m.amountError?.contains("maior que o saldo") == true)
            m.customText = ""
            t.isNil(m.amount); t.equal(m.amountError, "Informe um valor maior que zero.")
        },
        TestCase("pagar fatura: saldo insuficiente e habilitação do botão") { t in
            var m = PayInvoiceModel(remaining: 100)
            t.check(!m.canPay(accountBalance: 500))     // sem conta
            m.accountId = UUID()
            t.check(m.canPay(accountBalance: 500))
            t.check(m.isInsufficient(accountBalance: 50))
            t.check(!m.isInsufficient(accountBalance: 100))
            m.option = .custom; m.customText = "0"
            t.check(!m.canPay(accountBalance: 500))
            t.equal(PayInvoiceModel(remaining: dec("0.05")).minimum, dec("0.01"))
        },
    ]
}

func dashboardTests() -> [TestCase] {
    [
        TestCase("linhas de categoria com variação contra o mês anterior") { t in
            let mercado = Category(name: "Mercado", kind: .expense), lazer = Category(name: "Lazer", kind: .expense)
            let lookup = FinanceLookup(accounts: [], categories: [mercado, lazer], tags: [], cards: [])
            let txs = [
                Transaction(type: .expense, amount: 150, date: D(2026, 10, 3), title: "a", categoryId: mercado.id),
                Transaction(type: .expense, amount: 100, date: D(2026, 9, 3), title: "b", categoryId: mercado.id),
                Transaction(type: .expense, amount: 40, date: D(2026, 10, 4), title: "c", categoryId: lazer.id),
            ]
            let ym = YearMonth(year: 2026, month: 10)
            let rows = DashboardModel.categoryRows(current: SummaryEngine.summary(month: ym, transactions: txs),
                                                   previous: SummaryEngine.summary(month: ym.previous, transactions: txs), lookup: lookup)
            t.equal(rows.map(\.name), ["Mercado", "Lazer"])
            t.equal(rows[0].deltaPercent, 50); t.isNil(rows[1].deltaPercent)
            t.equal(DashboardModel.deltaText(50, previous: ym.previous), "+50% vs set.")
            t.equal(DashboardModel.deltaText(-5, previous: ym.previous), "\u{2212}5% vs set.")
            t.equal(DashboardModel.deltaText(nil, previous: ym.previous), "sem gasto em set.")
        },
    ]
}
