import Foundation

private func inv(_ name: String, _ cls: AssetClass, qty: String, avg: String, quote: String? = nil) -> Investment {
    Investment(name: name, assetClass: cls, quantity: dec(qty), averagePrice: dec(avg), quote: quote.map(dec))
}

func investmentTests() -> [TestCase] {
    return [
        TestCase("posição: custo, valor de mercado, ganho e rentabilidade simples") { t in
            let p = inv("PETR4", .stock, qty: "100", avg: "30.50", quote: "35.25")
            t.equal(InvestmentEngine.cost(p), 3050)
            t.equal(InvestmentEngine.marketValue(p), 3525)
            t.equal(InvestmentEngine.gain(p), 475)
            t.equal(InvestmentEngine.returnPercent(p), dec("15.57"))   // 475/3050
            let loss = inv("XPTO", .stock, qty: "10", avg: "10", quote: "8")
            t.equal(InvestmentEngine.returnPercent(loss), -20)
        },
        TestCase("posição sem cotação usa o preço médio (ganho zero); custo zero não divide") { t in
            let p = inv("Tesouro", .fixedIncome, qty: "1", avg: "1000")
            t.equal(InvestmentEngine.marketValue(p), 1000); t.equal(InvestmentEngine.gain(p), 0)
            t.equal(InvestmentEngine.returnPercent(p), 0)
            t.isNil(InvestmentEngine.returnPercent(inv("Bônus", .stock, qty: "5", avg: "0", quote: "3")))
        },
        TestCase("compra recalcula o preço médio ponderado") { t in
            let p = inv("MXRF11", .reit, qty: "100", avg: "10")
            let b = try InvestmentEngine.buy(p, quantity: 50, price: 11)
            t.equal(b.quantity, 150)
            t.equal(b.averagePrice, dec("10.3333"))      // (1000+550)/150 com 4 casas
            t.throwsError(.invalidQuantity) { try InvestmentEngine.buy(p, quantity: 0, price: 1) }
            t.throwsError(.invalidAmount) { try InvestmentEngine.buy(p, quantity: 1, price: -1) }
        },
        TestCase("venda parcial realiza lucro e mantém o preço médio; vender tudo zera; excesso falha") { t in
            let p = inv("VALE3", .stock, qty: "100", avg: "60", quote: "70")
            let s = try InvestmentEngine.sell(p, quantity: 40, price: 75)
            t.equal(s.quantity, 60); t.equal(s.averagePrice, 60); t.equal(s.realizedProfit, 600)
            let all = try InvestmentEngine.sell(s, quantity: 60, price: 50)
            t.equal(all.quantity, 0); t.equal(all.realizedProfit, 600 - 600)
            t.throwsError(.insufficientQuantity) { try InvestmentEngine.sell(p, quantity: 101, price: 1) }
            t.throwsError(.invalidQuantity) { try InvestmentEngine.sell(p, quantity: -1, price: 1) }
        },
        TestCase("cripto com quantidade fracionária mantém precisão decimal") { t in
            let p = inv("Bitcoin", .crypto, qty: "0.00123456", avg: "300000", quote: "350000")
            t.equal(InvestmentEngine.marketValue(p), dec("432.096"))
            t.equal(InvestmentEngine.cost(p), dec("370.368"))
        },
        TestCase("cotação manual atualiza valor e data") { t in
            let p = inv("ITSA4", .stock, qty: "10", avg: "9")
            let q = try InvestmentEngine.updateQuote(p, quote: dec("10.5"), date: D(2026, 10, 19))
            t.equal(q.quote, dec("10.5")); t.equal(ymd(q.quoteDate!), "2026-10-19")
            t.throwsError(.invalidAmount) { try InvestmentEngine.updateQuote(p, quote: -1, date: D(2026, 10, 19)) }
        },
        TestCase("alocação por classe: percentuais somam 100 e ordem decrescente") { t in
            let list = [inv("A", .stock, qty: "1", avg: "100", quote: "100"), inv("B", .fixedIncome, qty: "1", avg: "100", quote: "100"),
                        inv("C", .reit, qty: "1", avg: "100", quote: "100"), inv("D", .fixedIncome, qty: "1", avg: "50", quote: "50")]
            let a = InvestmentEngine.allocation(list)
            t.equal(a.map(\.assetClass), [.fixedIncome, .stock, .reit])
            t.equal(a.map(\.value), [150, 100, 100])
            t.equal(a.reduce(Decimal(0)) { $0 + $1.percent }, 100)
            t.equal(a[0].percent, dec("42.86"))
            t.equal(InvestmentEngine.allocation([]).count, 0)
        },
        TestCase("totais da carteira") { t in
            let list = [inv("A", .stock, qty: "10", avg: "10", quote: "12"), inv("B", .crypto, qty: "2", avg: "100", quote: "50")]
            let tot = InvestmentEngine.totals(list)
            t.equal(tot.cost, 300); t.equal(tot.value, 220); t.equal(tot.gain, -80); t.equal(tot.returnPercent, dec("-26.67"))
            t.isNil(InvestmentEngine.totals([]).returnPercent)
        },
        TestCase("patrimônio líquido: ativos - passivos (dívidas, faturas, cheque especial)") { t in
            let c1 = Account(name: "Corrente", type: .checking, initialBalance: 1000)
            let c2 = Account(name: "Negativa", type: .checking, initialBalance: -200)
            let card = CreditCard(name: "Visa", limit: 5000, closingDay: 10, dueDay: 20)
            let purchase = Transaction(type: .expense, amount: 800, date: D(2026, 10, 5), title: "TV", creditCardId: card.id)
            let income = Transaction(type: .income, amount: 500, date: D(2026, 10, 1), title: "Freela", accountId: c1.id)
            let debt = Debt(name: "Empréstimo", balance: 3000, monthlyInterestRate: dec("0.02"), minimumPayment: 100)
            let invest = inv("PETR4", .stock, qty: "10", avg: "30", quote: "40")
            let nw = NetWorthEngine.compute(accounts: [c1, c2], transactions: [purchase, income], investments: [invest],
                                            debts: [debt], creditCards: [card])
            t.equal(nw.accountsAssets, 1500)
            t.equal(nw.investmentsValue, 400)
            t.equal(nw.assets, 1900)
            t.equal(nw.overdraft, 200); t.equal(nw.debts, 3000); t.equal(nw.cardBalances, 800)
            t.equal(nw.liabilities, 4000)
            t.equal(nw.netWorth, -2100)
        },
        TestCase("patrimônio: contas arquivadas e pagamento de fatura") { t in
            let c = Account(name: "C", type: .checking, initialBalance: 2000)
            let old = Account(name: "Velha", type: .savings, initialBalance: 999, isArchived: true)
            let card = CreditCard(name: "Visa", limit: 5000, closingDay: 10, dueDay: 20)
            let buy = Transaction(type: .expense, amount: 500, date: D(2026, 9, 5), title: "x", creditCardId: card.id)
            let pay = Transaction(type: .transfer, amount: 500, date: D(2026, 10, 1), title: "fatura", accountId: c.id, creditCardId: card.id, invoiceId: UUID())
            let nw = NetWorthEngine.compute(accounts: [c, old], transactions: [buy, pay], investments: [], debts: [], creditCards: [card])
            t.equal(nw.cardBalances, 0); t.equal(nw.accountsAssets, 1500); t.equal(nw.netWorth, 1500)
        },
        TestCase("evolução mensal: um snapshot por mês (substitui) e série ordenada") { t in
            let m = YearMonth(year: 2026, month: 10)
            let first = NetWorthSnapshot(month: m, assets: 1000, liabilities: 200)
            var list = [NetWorthSnapshot(month: m.previous, assets: 900, liabilities: 300)]
            let up1 = NetWorthEngine.upsert(first, into: list)
            list = up1.list
            t.equal(list.count, 2)
            var newer = NetWorthSnapshot(month: m, assets: 1500, liabilities: 100)
            newer.updatedAt = Date()
            let up2 = NetWorthEngine.upsert(newer, into: list)
            t.equal(up2.list.count, 2)
            t.equal(up2.saved.id, first.id, "mantém o id do registro do mês")
            t.equal(up2.list.first { $0.month == m }?.netWorth, 1400)
            let series = NetWorthEngine.evolution(up2.list, months: 4, endingAt: m)
            t.equal(series.map(\.month), [m.adding(months: -3), m.adding(months: -2), m.previous, m])
            t.equal(series.map(\.netWorth), [nil, nil, 600, 1400])
            t.equal(NetWorthEngine.change(series), 800)
        },
    ]
}
