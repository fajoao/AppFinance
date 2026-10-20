import Foundation

private func card(closing: Int, due: Int, limit: String = "1000") -> CreditCard {
    CreditCard(name: "Visa", limit: dec(limit), closingDay: closing, dueDay: due)
}
private func buy(_ c: CreditCard, _ amount: String, _ date: Date, type: TransactionType = .expense) -> Transaction {
    Transaction(type: type, amount: dec(amount), date: date, title: "compra", creditCardId: c.id)
}
private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

func creditCardTests() -> [TestCase] {
    [
        TestCase("compra antes do fechamento fica na fatura do mês; no dia ou depois vai para a próxima") { t in
            let c = card(closing: 10, due: 20)
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 9), card: c), ym(2025, 1))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 10), card: c), ym(2025, 2))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 11), card: c), ym(2025, 2))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 1), card: c), ym(2025, 1))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 31), card: c), ym(2025, 2))
        },
        TestCase("virada de ano na atribuição") { t in
            let c = card(closing: 25, due: 5)
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2024, 12, 24), card: c), ym(2024, 12))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2024, 12, 25), card: c), ym(2025, 1))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2024, 12, 31), card: c), ym(2025, 1))
        },
        TestCase("fechamento dia 31 e 30 em fevereiro (comum e bissexto)") { t in
            let c31 = card(closing: 31, due: 10)
            t.equal(ymd(CreditCardEngine.closingDate(card: c31, month: ym(2025, 2))), "2025-02-28")
            t.equal(ymd(CreditCardEngine.closingDate(card: c31, month: ym(2024, 2))), "2024-02-29")
            t.equal(ymd(CreditCardEngine.closingDate(card: c31, month: ym(2025, 4))), "2025-04-30")
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 2, 27), card: c31), ym(2025, 2))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 2, 28), card: c31), ym(2025, 3))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 30), card: c31), ym(2025, 1))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2025, 1, 31), card: c31), ym(2025, 2))
            let c30 = card(closing: 30, due: 10)
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2024, 2, 28), card: c30), ym(2024, 2))
            t.equal(CreditCardEngine.invoiceMonth(forPurchaseOn: D(2024, 2, 29), card: c30), ym(2024, 3))
        },
        TestCase("vencimento: mesmo mês se vencimento > fechamento; senão mês seguinte") { t in
            t.equal(ymd(CreditCardEngine.dueDate(card: card(closing: 10, due: 20), month: ym(2025, 1))), "2025-01-20")
            t.equal(ymd(CreditCardEngine.dueDate(card: card(closing: 25, due: 5), month: ym(2025, 1))), "2025-02-05")
            t.equal(ymd(CreditCardEngine.dueDate(card: card(closing: 25, due: 5), month: ym(2024, 12))), "2025-01-05")
            t.equal(ymd(CreditCardEngine.dueDate(card: card(closing: 10, due: 31), month: ym(2025, 2))), "2025-02-28")
            t.equal(ymd(CreditCardEngine.dueDate(card: card(closing: 20, due: 20), month: ym(2025, 3))), "2025-04-20")
        },
        TestCase("total da fatura soma compras do ciclo; estorno abate") { t in
            let c = card(closing: 10, due: 20)
            let txs = [buy(c, "100.10", D(2024, 12, 15)), buy(c, "50.20", D(2025, 1, 9)), buy(c, "10", D(2025, 1, 10)),
                       buy(c, "-5.30", D(2025, 1, 2)), buy(c, "20", D(2025, 1, 3), type: .income)]
            // fatura de jan (fecha 10/jan): 15/dez(>=10 dez -> jan), 9/jan, 2/jan (estorno), 3/jan (crédito)
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2025, 1), transactions: txs), dec("100.10") + dec("50.20") - dec("5.30") - 20)
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2025, 2), transactions: txs), 10)
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2025, 3), transactions: txs), 0)
        },
        TestCase("compras de outro cartão não entram") { t in
            let c = card(closing: 10, due: 20), other = card(closing: 10, due: 20)
            let txs = [buy(other, "99", D(2025, 1, 5))]
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2025, 1), transactions: txs), 0)
        },
        TestCase("fatura atual na data") { t in
            let c = card(closing: 10, due: 20)
            t.equal(CreditCardEngine.currentInvoiceMonth(card: c, asOf: D(2025, 1, 9)), ym(2025, 1))
            t.equal(CreditCardEngine.currentInvoiceMonth(card: c, asOf: D(2025, 1, 10)), ym(2025, 2))
        },
        TestCase("status da fatura: aberta, fechada, vencida, paga") { t in
            let c = card(closing: 10, due: 20)
            let txs = [buy(c, "100", D(2025, 1, 5))]
            func st(_ d: Date) -> InvoiceStatus { CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: txs, asOf: d).status }
            t.equal(st(D(2025, 1, 9)), .open)
            t.equal(st(D(2025, 1, 10)), .closed)
            t.equal(st(D(2025, 1, 20)), .closed)
            t.equal(st(D(2025, 1, 21)), .overdue)
            var s = CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: txs, asOf: D(2025, 1, 15))
            s.invoice.paidAmount = 100
            let stored = CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: txs, storedInvoices: [s.invoice], asOf: D(2025, 3, 1))
            t.equal(stored.status, .paid); t.equal(stored.remaining, 0); t.check(stored.isStored)
        },
        TestCase("compra parcelada distribui parcelas nas faturas seguintes") { t in
            let c = card(closing: 10, due: 20)
            let parts = try CreditCardEngine.makePurchase(card: c, title: "Notebook", total: dec("100.01"), date: D(2025, 11, 15), installments: 3)
            t.equal(parts.map(\.amount), [dec("33.33"), dec("33.33"), dec("33.35")])
            t.check(parts.allSatisfy { $0.isCardPurchase && $0.status == .paid })
            let months = parts.map { CreditCardEngine.invoiceMonth(forPurchaseOn: $0.date, card: c) }
            t.equal(months, [ym(2025, 12), ym(2026, 1), ym(2026, 2)])
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2026, 1), transactions: parts), dec("33.33"))
            t.equal(CreditCardEngine.invoiceTotal(card: c, month: ym(2026, 2), transactions: parts), dec("33.35"))
        },
        TestCase("parcelamento 10x de 100,01 no cartão fecha no total") { t in
            let c = card(closing: 10, due: 20, limit: "5000")
            let parts = try CreditCardEngine.makePurchase(card: c, title: "Sofá", total: dec("100.01"), date: D(2025, 1, 5), installments: 10)
            t.equal(parts.map(\.amount).reduce(0, +), dec("100.01"))
            t.equal(parts.last!.amount, dec("10.01"))
            t.equal(CreditCardEngine.usedLimit(card: c, transactions: parts), dec("100.01"))
        },
        TestCase("limite disponível: compras (inclui parcelas futuras) menos pagamentos") { t in
            let c = card(closing: 10, due: 20, limit: "1000")
            var txs = [buy(c, "300", D(2025, 1, 5))]
            txs += try CreditCardEngine.makePurchase(card: c, title: "TV", total: 90, date: D(2025, 1, 6), installments: 3)
            t.equal(CreditCardEngine.availableLimit(card: c, transactions: txs), 610)
            let s = CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: txs, asOf: D(2025, 1, 15))
            let (inv, pay) = try CreditCardEngine.pay(s, card: c, amount: 100, from: UUID(), on: D(2025, 1, 18))
            t.equal(inv.paidAmount, 100)
            t.equal(CreditCardEngine.availableLimit(card: c, transactions: txs + [pay]), 710)
        },
        TestCase("limite estourado fica negativo") { t in
            let c = card(closing: 10, due: 20, limit: "100")
            t.equal(CreditCardEngine.availableLimit(card: c, transactions: [buy(c, "130.50", D(2025, 1, 1))]), dec("-30.50"))
        },
        TestCase("pagamento de fatura: total, parcial, excesso") { t in
            let c = card(closing: 10, due: 20)
            let acc = Account(name: "CC", type: .checking, initialBalance: 1000)
            let purchases = [buy(c, "250.75", D(2025, 1, 3))]
            let s = CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: purchases, asOf: D(2025, 1, 12))
            t.equal(s.total, dec("250.75"))
            t.throwsError(.overpayment) { try CreditCardEngine.pay(s, card: c, amount: dec("250.76"), from: acc.id, on: D(2025, 1, 18)) }
            t.throwsError(.invalidAmount) { try CreditCardEngine.pay(s, card: c, amount: 0, from: acc.id, on: D(2025, 1, 18)) }
            // parcial
            let (inv1, pay1) = try CreditCardEngine.pay(s, card: c, amount: 100, from: acc.id, on: D(2025, 1, 15))
            t.isNil(inv1.paidAt)
            let s2 = CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: purchases + [pay1], storedInvoices: [inv1], asOf: D(2025, 1, 16))
            t.equal(s2.total, dec("250.75"))     // pagamento (transferência) não vira compra
            t.equal(s2.remaining, dec("150.75"))
            // restante
            let (inv2, pay2) = try CreditCardEngine.pay(s2, card: c, from: acc.id, on: D(2025, 1, 19))
            t.equal(inv2.paidAmount, dec("250.75")); t.equal(inv2.paidAt.map(ymd), "2025-01-19")
            t.equal(inv2.id, inv1.id)
            let all = purchases + [pay1, pay2]
            t.equal(BalanceEngine.balance(of: acc, transactions: all), dec("749.25"))
            t.equal(CreditCardEngine.usedLimit(card: c, transactions: all), 0)
            t.equal(CreditCardEngine.summary(card: c, month: ym(2025, 1), transactions: all, storedInvoices: [inv2], asOf: D(2025, 1, 20)).status, .paid)
            t.equal(pay2.type, .transfer); t.check(pay2.isInvoicePayment && !pay2.isCardPurchase)
            // pagamentos não contam como despesa no resumo
            t.equal(SummaryEngine.totals(month: YearMonth(year: 2025, month: 1), transactions: all).expense, dec("250.75"))
        },
        TestCase("faturas atual e futuras (inclui anterior em aberto)") { t in
            let c = card(closing: 10, due: 20)
            let parts = try CreditCardEngine.makePurchase(card: c, title: "X", total: 300, date: D(2025, 1, 5), installments: 3)
            // asOf 12/jan: atual = fev (fecha 10/fev); jan está fechada e não paga
            let list = CreditCardEngine.upcomingInvoices(card: c, transactions: parts, asOf: D(2025, 1, 12), futureCount: 2)
            t.equal(list.map(\.invoice.month), [ym(2025, 1), ym(2025, 2), ym(2025, 3), ym(2025, 4)])
            t.equal(list.map(\.total), [100, 100, 100, 0])
            t.equal(list[0].status, .closed); t.equal(list[1].status, .open)
            // sem anterior pendente
            let list2 = CreditCardEngine.upcomingInvoices(card: c, transactions: [], asOf: D(2025, 12, 5), futureCount: 1)
            t.equal(list2.map(\.invoice.month), [ym(2025, 12), ym(2026, 1)])
        },
        TestCase("fatura sem compras e dados do vencimento") { t in
            let c = card(closing: 5, due: 12)
            let s = CreditCardEngine.summary(card: c, month: ym(2025, 6), transactions: [], asOf: D(2025, 6, 1))
            t.equal(s.total, 0); t.equal(ymd(s.invoice.dueDate), "2025-06-12"); t.equal(ymd(s.invoice.closingDate), "2025-06-05")
            t.equal(s.status, .open)
        },
    ]
}
