import Foundation

private let today = D(2026, 10, 19)

private func fixture() -> FinanceSnapshot {
    do {
        var s = FinanceSnapshot()
        let checking = Account(name: "Corrente", type: .checking, initialBalance: 1000)
        let savings = Account(name: "Poupança", type: .savings, initialBalance: 500)
        let invest = Account(name: "Corretora", type: .investment, initialBalance: 9000)
        let archived = Account(name: "Velha", type: .wallet, initialBalance: 77, isArchived: true)
        s.accounts = [checking, savings, invest, archived]
        let card = CreditCard(name: "Visa", limit: 5000, closingDay: 5, dueDay: 12, paymentAccountId: checking.id)
        s.creditCards = [card]
        s.transactions = [
            tx(.expense, "30", today, "Almoço", account: checking.id),
            Transaction(type: .expense, amount: 20, date: today, title: "Café cartão", creditCardId: card.id),
            tx(.income, "100", today, "Freela", account: checking.id),
            tx(.expense, "999", D(2026, 10, 18), "Ontem", account: checking.id),
            Transaction(type: .transfer, amount: 40, date: today, title: "Transf", accountId: checking.id, destinationAccountId: savings.id),
            tx(.expense, "250", D(2026, 10, 25), "Internet", status: .pending, account: checking.id),
            tx(.expense, "80", D(2026, 10, 22), "Academia", status: .pending, account: checking.id),
        ]
        return s
    }
}

func widgetTests() -> [TestCase] {
    return [
        TestCase("widget: saldo líquido ignora investimentos e contas arquivadas") { t in
            let w = WidgetDataBuilder.make(snapshot: fixture(), today: today, hideValues: false)
            // 1000 + 500 (corrente/poupança) -30 -999 +100 -40 +40 (pagas até hoje; pendentes não contam)
            t.equal(w.balance, 1000 + 500 - 30 + 100 - 999)
            t.equal(w.hideValues, false); t.equal(ymd(w.generatedAt), "2026-10-19")
        },
        TestCase("widget: gastos do dia somam despesas de hoje, inclusive cartão; sem transferências") { t in
            let w = WidgetDataBuilder.make(snapshot: fixture(), today: today, hideValues: true)
            t.equal(w.todaySpent, 50); t.equal(w.hideValues, true)
        },
        TestCase("widget: próximo vencimento é o pendente mais cedo (conta ou fatura)") { t in
            let w = WidgetDataBuilder.make(snapshot: fixture(), today: today, hideValues: false)
            t.equal(w.nextDue?.title, "Academia"); t.equal(w.nextDue?.amount, 80); t.equal(w.nextDue?.isOverdue, false)
            // fatura de 20 (compra hoje fecha dia 5 -> fatura de novembro vence 12/11) não antecede
            var s = fixture()
            s.creditCards[0].closingDay = 20; s.creditCards[0].dueDay = 21     // compra de hoje cai na fatura de outubro, que vence 21/10
            let w2 = WidgetDataBuilder.make(snapshot: s, today: today, hideValues: false)
            t.equal(w2.nextDue?.kind, .invoice); t.equal(w2.nextDue?.amount, 20); t.equal(ymd(w2.nextDue!.dueDate), "2026-10-21")
        },
        TestCase("widget: atrasado aparece primeiro e é marcado; sem pendências é nil") { t in
            var s = fixture()
            s.transactions.append(tx(.expense, "60", D(2026, 10, 10), "Luz", status: .pending, account: s.accounts[0].id))
            let w = WidgetDataBuilder.make(snapshot: s, today: today, hideValues: false)
            t.equal(w.nextDue?.title, "Luz"); t.equal(w.nextDue?.isOverdue, true)
            t.isNil(WidgetDataBuilder.make(snapshot: FinanceSnapshot(), today: today, hideValues: false).nextDue)
        },
        TestCase("widget: arquivo JSON do App Group faz round-trip e tolera ausência/corrupção") { t in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("widget.json")
            t.isNil(WidgetSnapshotStore.load(from: url))
            let w = WidgetDataBuilder.make(snapshot: fixture(), today: today, hideValues: false)
            try WidgetSnapshotStore.save(w, to: url)
            t.equal(WidgetSnapshotStore.load(from: url), w)
            try Data("lixo".utf8).write(to: url)
            t.isNil(WidgetSnapshotStore.load(from: url))
        },
        TestCase("widget: textos respeitam ocultar valores e descrevem o vencimento") { t in
            let w = WidgetDataBuilder.make(snapshot: fixture(), today: today, hideValues: false)
            t.equal(w.balanceText, "R$\u{00A0}571,00"); t.equal(w.todaySpentText, "R$\u{00A0}50,00"); t.equal(w.nextDueAmountText, "R$\u{00A0}80,00")
            var hidden = w; hidden.hideValues = true
            t.equal(hidden.balanceText, "R$\u{00A0}••••"); t.equal(hidden.nextDueAmountText, "R$\u{00A0}••••")
            func due(_ days: Int) -> WidgetDue { WidgetDue(title: "x", amount: 1, dueDate: FinanceCalendar.addDays(today, days), kind: .bill, isOverdue: days < 0) }
            t.equal(due(0).statusText(today: today), "Vence hoje"); t.equal(due(1).statusText(today: today), "Vence amanhã")
            t.equal(due(5).statusText(today: today), "Vence em 5 dias"); t.equal(due(-1).statusText(today: today), "Atrasada há 1 dia")
            t.equal(due(-9).statusText(today: today), "Atrasada há 9 dias")
            t.equal(WidgetSnapshot.sample(today: today).nextDue?.title, "Energia (Enel)")
        },
        TestCase("atalho de voz: interpreta frases com valor e descrição") { t in
            let cases: [(String, String, String)] = [
                ("mercado 45,90", "Mercado", "45.90"),
                ("gastei 45,90 no mercado", "Mercado", "45.90"),
                ("paguei R$ 1.250,00 de aluguel", "Aluguel", "1250.00"),
                ("uber 23 reais", "Uber", "23"),
                ("12,50", "Despesa", "12.50"),
                ("almoço com a equipe 38,5", "Almoço com a equipe", "38.5"),
            ]
            for (text, title, amount) in cases {
                let q = QuickExpenseParser.parse(text)
                t.equal(q?.title, title, text); t.equal(q?.amount, dec(amount), text)
            }
            t.isNil(QuickExpenseParser.parse("sem valor aqui"))
            t.isNil(QuickExpenseParser.parse("mercado 0"))
            t.isNil(QuickExpenseParser.parse("   "))
        },
        TestCase("atalho de voz: monta a despesa na conta padrão, paga hoje") { t in
            let acc = UUID(), cat = UUID()
            let q = QuickExpense(title: "Padaria", amount: dec("8.75"))
            let x = q.makeTransaction(accountId: acc, categoryId: cat, memberId: nil, date: today)
            t.equal(x.type, .expense); t.equal(x.amount, dec("8.75")); t.equal(x.status, .paid)
            t.equal(x.accountId, acc); t.equal(x.categoryId, cat); t.equal(x.title, "Padaria"); t.equal(x.date, today)
        },
    ]
}
