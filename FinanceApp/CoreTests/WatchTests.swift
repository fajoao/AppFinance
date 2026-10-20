import Foundation

private let today = D(2026, 10, 19)

func watchTests() -> [TestCase] {
    [
        TestCase("contexto iPhone -> relógio: ida e volta preserva o resumo (Decimal exato)") { t in
            let s = WidgetSnapshot.sample(today: today)
            let ctx = WatchLink.context(for: s)
            t.equal(WatchLink.snapshot(from: ctx), s)
            t.equal(WatchLink.snapshot(from: ctx)?.balance, dec("19000.77"))
        },
        TestCase("contexto inválido, de outra versão ou de outro tipo é ignorado") { t in
            t.isNil(WatchLink.snapshot(from: [:]))
            t.isNil(WatchLink.snapshot(from: ["v": 99, "snapshot": Data()]))
            t.isNil(WatchLink.snapshot(from: ["v": 1, "snapshot": Data("lixo".utf8)]))
            t.isNil(WatchLink.snapshot(from: ["v": 1, "snapshot": "texto"]))
            t.isNil(WatchLink.quickAdd(from: WatchLink.context(for: WidgetSnapshot.sample(today: today))))
        },
        TestCase("despesa rápida: mensagem relógio -> iPhone preserva id, texto e data") { t in
            let req = WatchQuickAddRequest(text: "gastei 45,90 no mercado", createdAt: Date(timeIntervalSince1970: 1_792_000_000))
            let back = WatchLink.quickAdd(from: WatchLink.message(for: req))
            t.equal(back, req)
        },
        TestCase("ditado vira despesa com externalId do relógio; reentrega não duplica") { t in
            let req = WatchQuickAddRequest(text: "gastei 45,90 no mercado", createdAt: Date())
            let acc = UUID(), cat = UUID(), member = UUID()
            guard case .created(let tx) = WatchQuickAdd.process(req, existing: [], accountId: acc, categoryId: cat, memberId: member, today: today) else {
                t.fail("esperava created"); return
            }
            t.equal(tx.type, .expense); t.equal(tx.amount, dec("45.90")); t.equal(tx.title, "Mercado"); t.equal(tx.accountId, acc)
            t.equal(tx.categoryId, cat); t.equal(tx.memberId, member); t.equal(tx.status, .paid)
            t.equal(tx.externalId, "watch:" + req.id.uuidString)
            t.equal(WatchQuickAdd.process(req, existing: [tx], accountId: acc, categoryId: nil, memberId: nil, today: today), .duplicate)
        },
        TestCase("ditado sem valor, com valor zero ou absurdo é recusado com mensagem") { t in
            for text in ["comprei pão", "gastei 0 reais", "gastei 99999999 no carro", ""] {
                let r = WatchQuickAdd.process(WatchQuickAddRequest(text: text), existing: [], accountId: nil, categoryId: nil, memberId: nil, today: today)
                t.equal(r, .invalid(WatchQuickAdd.invalidMessage), text)
            }
            t.isNil(WatchQuickAdd.preview("sem valor"))
            t.equal(WatchQuickAdd.preview("paguei 12,5 na padaria")?.amount, dec("12.5"))
            t.equal(WatchQuickAdd.preview("paguei 12,5 na padaria")?.title, "Padaria")
        },
        TestCase("data do ditado nunca fica no futuro") { t in
            let future = FinanceCalendar.addDays(Date(), 10)
            guard case .created(let tx) = WatchQuickAdd.process(WatchQuickAddRequest(text: "gastei 10 no café", createdAt: future), existing: [],
                                                                accountId: nil, categoryId: nil, memberId: nil, today: today) else { t.fail("created"); return }
            t.equal(ymd(tx.date), "2026-10-19")
        },
        TestCase("painel do relógio: textos, vencimento e frescor") { t in
            var s = WidgetSnapshot.sample(today: today)
            let now = Date()
            // frescor medido em dias civis a partir de hoje (do relógio)
            let todayCivil = FinanceCalendar.normalize(now)
            s.generatedAt = todayCivil
            var d = WatchDashboard.make(snapshot: s, now: now)
            t.equal(d.balanceText, "R$\u{00A0}19.000,77"); t.equal(d.todaySpentText, "R$\u{00A0}89,90"); t.equal(d.freshnessText, "Atualizado hoje")
            t.check(!d.isStale && d.hasData); t.equal(d.nextDueTitle, "Energia (Enel)")
            t.check(d.nextDueText!.hasSuffix("R$\u{00A0}189,40"), d.nextDueText ?? "")
            s.generatedAt = FinanceCalendar.addDays(todayCivil, -1)
            d = WatchDashboard.make(snapshot: s, now: now)
            t.equal(d.freshnessText, "Atualizado ontem"); t.check(!d.isStale)
            s.generatedAt = FinanceCalendar.addDays(todayCivil, -4)
            d = WatchDashboard.make(snapshot: s, now: now)
            t.equal(d.freshnessText, "Atualizado há 4 dias"); t.check(d.isStale)
        },
        TestCase("painel do relógio: sem dados e com valores ocultos") { t in
            t.equal(WatchDashboard.make(snapshot: nil, now: Date()), .placeholder)
            t.check(!WatchDashboard.placeholder.hasData)
            var s = WidgetSnapshot.sample(today: today); s.hideValues = true; s.nextDue = nil
            let d = WatchDashboard.make(snapshot: s, now: Date())
            t.equal(d.balanceText, WidgetSnapshot.maskedMoney); t.equal(d.todaySpentText, WidgetSnapshot.maskedMoney); t.isNil(d.nextDueText)
        },
        TestCase("valor curto da complicação") { t in
            t.equal(WatchDashboard.shortMoney(dec("950.40"), hidden: false), "R$\u{00A0}950")
            t.equal(WatchDashboard.shortMoney(dec("19000.77"), hidden: false), "R$\u{00A0}19 mil")
            t.equal(WatchDashboard.shortMoney(dec("1250"), hidden: false), "R$\u{00A0}1,3 mil")
            t.equal(WatchDashboard.shortMoney(dec("2500000"), hidden: false), "R$\u{00A0}2,5 mi")
            t.equal(WatchDashboard.shortMoney(dec("-1250"), hidden: false), "-R$\u{00A0}1,3 mil")
            t.equal(WatchDashboard.shortMoney(dec("5"), hidden: true), WidgetSnapshot.maskedMoney)
        },
    ]
}
