import Foundation

func summaryJ(_ s: InvoiceSummary) -> J {
    ["month": YMj(s.invoice.month), "closing": iso(s.invoice.closingDate), "due": iso(s.invoice.dueDate), "total": S(s.total), "paid": S(s.paidAmount),
     "remaining": S(s.remaining), "status": s.status.rawValue, "isStored": s.isStored, "txCount": s.transactions.count]
}

func cardCases() {
    let cards = [card(1, "Roxo", limit: "5000", closing: 5, due: 15), card(2, "Azul", limit: "3000", closing: 31, due: 10),
                 card(3, "Verde", limit: "1000", closing: 28, due: 5), card(4, "Preto", limit: "10000", closing: 10, due: 10),
                 card(5, "Dia1", limit: "800", closing: 1, due: 20)]
    let purchaseDates = [d(2026, 1, 4), d(2026, 1, 5), d(2026, 1, 6), d(2026, 2, 27), d(2026, 2, 28), d(2026, 3, 1), d(2026, 3, 30), d(2026, 3, 31),
                         d(2026, 12, 31), d(2024, 2, 29), d(2026, 4, 30), d(2026, 4, 28)]
    for c in cards {
        for date in purchaseDates {
            add("card.invoiceMonth", "\(c.name) purchase \(iso(date))", input: ["card": ent(c), "date": iso(date)], expected: YMj(CreditCardEngine.invoiceMonth(forPurchaseOn: date, card: c)))
        }
        for m in [YearMonth(year: 2026, month: 1), YearMonth(year: 2026, month: 2), YearMonth(year: 2026, month: 4), YearMonth(year: 2026, month: 12), YearMonth(year: 2024, month: 2)] {
            add("card.dates", "\(c.name) dates \(m.label)", input: ["card": ent(c), "month": YMj(m)],
                expected: ["closing": iso(CreditCardEngine.closingDate(card: c, month: m)), "due": iso(CreditCardEngine.dueDate(card: c, month: m))] as J)
        }
    }

    // Cenário completo: cartão Roxo (fecha 5, vence 15)
    let c = cards[0]
    var inv9 = Invoice(cardId: c.id, month: YearMonth(year: 2026, month: 9), closingDate: d(2026, 9, 5), dueDate: d(2026, 9, 15))
    inv9.id = uid(100); inv9.paidAmount = dec("200"); inv9.createdAt = stampDate; inv9.updatedAt = stampDate
    var invOct = Invoice(cardId: c.id, month: YearMonth(year: 2026, month: 10), closingDate: d(2026, 10, 5), dueDate: d(2026, 10, 15))
    invOct.id = uid(101); invOct.paidAmount = dec("0"); invOct.createdAt = stampDate; invOct.updatedAt = stampDate
    let base = tx(1, .expense, "1200.01", d(2026, 8, 20), "Notebook", status: .paid, cat: 3, card: 1)
    let parcelas = try! InstallmentEngine.makeInstallments(from: base, count: 10) // set..jun
    var txs = parcelas
    txs.append(tx(20, .expense, "89.90", d(2026, 9, 10), "Restaurante", card: 1))
    txs.append(tx(21, .expense, "150", d(2026, 10, 3), "Posto", card: 1))
    txs.append(tx(22, .expense, "40", d(2026, 10, 5), "Padaria (no fechamento)", card: 1))
    txs.append(tx(23, .income, "30", d(2026, 10, 12), "Estorno", card: 1))
    txs.append(tx(24, .transfer, "200", d(2026, 9, 14), "Pagamento fatura", account: 1, card: 1, invoice: inv9.id))
    txs.append(tx(25, .expense, "500", d(2026, 10, 1), "Outro cartão", card: 2))
    txs.append(tx(26, .expense, "70", d(2026, 10, 2), "Conta normal", account: 1))
    for asOf in [d(2026, 9, 1), d(2026, 9, 20), d(2026, 10, 4), d(2026, 10, 5), d(2026, 10, 16), d(2026, 11, 20)] {
        let ups = CreditCardEngine.upcomingInvoices(card: c, transactions: txs, storedInvoices: [inv9, invOct], asOf: asOf, futureCount: 3)
        add("card.upcoming", "upcoming asOf \(iso(asOf))",
            input: ["card": ent(c), "transactions": ents(txs), "invoices": ents([inv9, invOct]), "asOf": iso(asOf), "futureCount": 3],
            expected: ["invoices": ups.map(summaryJ), "used": S(CreditCardEngine.usedLimit(card: c, transactions: txs)),
                       "available": S(CreditCardEngine.availableLimit(card: c, transactions: txs))] as J)
    }
    // sem faturas guardadas e com fatura pequena paga integralmente
    let ups2 = CreditCardEngine.upcomingInvoices(card: cards[1], transactions: txs, asOf: d(2026, 10, 20), futureCount: 2)
    add("card.upcoming", "card sem compras fechado 31", input: ["card": ent(cards[1]), "transactions": ents(txs), "invoices": [Any](), "asOf": "2026-10-20", "futureCount": 2],
        expected: ["invoices": ups2.map(summaryJ), "used": S(CreditCardEngine.usedLimit(card: cards[1], transactions: txs)),
                   "available": S(CreditCardEngine.availableLimit(card: cards[1], transactions: txs))] as J)

    // pagar fatura
    func payCase(_ name: String, month: YearMonth, amount: String?, asOf: Date) {
        let s = CreditCardEngine.summary(card: c, month: month, transactions: txs, storedInvoices: [inv9, invOct], asOf: asOf)
        let input: J = ["card": ent(c), "transactions": ents(txs), "invoices": ents([inv9, invOct]), "month": YMj(month), "amount": amount.map { $0 as Any } ?? NSNull(), "asOf": iso(asOf), "from": uid(1).uuidString, "on": iso(asOf)]
        do {
            let r = try CreditCardEngine.pay(s, card: c, amount: amount.map(dec), from: uid(1), on: asOf)
            add("card.pay", name, input: input, expected: ["ok": true, "paidAmount": S(r.invoice.paidAmount), "paidAt": isoN(r.invoice.paidAt), "paymentAmount": S(r.payment.amount),
                                                           "paymentTitle": r.payment.title, "paymentType": r.payment.type.rawValue] as J)
        } catch let e as FinanceError {
            add("card.pay", name, input: input, expected: ["ok": false, "error": e.description] as J)
        } catch { fatalError() }
    }
    payCase("pagar total outubro", month: YearMonth(year: 2026, month: 10), amount: nil, asOf: d(2026, 10, 10))
    payCase("pagar parcial setembro", month: YearMonth(year: 2026, month: 9), amount: "50", asOf: d(2026, 9, 20))
    payCase("pagar a mais", month: YearMonth(year: 2026, month: 10), amount: "99999", asOf: d(2026, 10, 10))
    payCase("pagar zero", month: YearMonth(year: 2026, month: 10), amount: "0", asOf: d(2026, 10, 10))
    payCase("pagar mês sem compras", month: YearMonth(year: 2027, month: 6), amount: nil, asOf: d(2026, 10, 10))

    // compra parcelada no cartão
    let p = try! CreditCardEngine.makePurchase(card: c, title: "TV", total: dec("100.01"), date: d(2026, 1, 31), installments: 10, categoryId: uid(3))
    add("card.makePurchase", "TV 10x", input: ["card": ent(c), "title": "TV", "total": "100.01", "date": "2026-01-31", "installments": 10],
        expected: p.map { ["amount": S($0.amount), "date": iso($0.date), "title": $0.title, "status": $0.status.rawValue] as J })
}
