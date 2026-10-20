import Foundation

private let today = D(2026, 10, 19)
private let thisMonth = YearMonth(today)

/// Letras diferentes por índice, para que descrições não sejam confundidas com uma recorrência.
private func unique(_ i: Int, _ prefix: String = "Compra") -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    return "\(prefix) \(letters[i / 26 % 26])\(letters[i % 26])"
}

private func spend(_ cat: Category, _ amounts: [String], monthsBack: Range<Int>, day: Int = 10, prefix: String = "Compra") -> [Transaction] {
    var list: [Transaction] = []
    for (i, k) in monthsBack.enumerated() {
        list.append(tx(.expense, amounts[i], thisMonth.adding(months: -k).date(day: day), unique(i + k * 3, prefix), category: cat.id))
    }
    return list
}

private func generate(_ transactions: [Transaction], _ categories: [Category] = [], balance: String = "5000", dues: [CashFlowItem] = []) -> InsightsReport {
    InsightsEngine.generate(transactions: transactions, categories: categories, liquidBalance: dec(balance), invoiceDues: dues, today: today)
}

func insightsTests() -> [TestCase] {
    let lazer = Category(name: "Lazer", kind: .expense)
    let mercado = Category(name: "Mercado", kind: .expense)
    let moradia = Category(name: "Moradia", kind: .expense)
    let cats = [lazer, mercado, moradia]

    return [
        TestCase("estatística robusta: mediana, MAD e escore z modificado") { t in
            t.equal(RobustStats.median([3, 1, 2]), 2)
            t.equal(RobustStats.median([1, 2, 3, 4]), dec("2.5"))
            t.equal(RobustStats.median([]), 0)
            t.equal(RobustStats.mad([1, 2, 3, 4, 100]), 1)          // mediana 3; desvios 2,1,0,1,97 -> mediana 1
            t.equal(RobustStats.modifiedZ(8, median: 3, mad: 1), dec("3.3725"))
            t.equal(RobustStats.modifiedZ(8, median: 3, mad: 0), 0, "MAD zero não divide")
        },
        TestCase("gasto atípico: categoria muito acima da mediana dos meses anteriores") { t in
            var txs = spend(lazer, ["400", "420", "380", "410", "390"], monthsBack: 1..<6)
            txs.append(tx(.expense, "900", D(2026, 10, 12), "Show", category: lazer.id))
            txs += spend(mercado, ["800", "820", "790", "810", "805"], monthsBack: 1..<6, prefix: "Super")
            txs.append(tx(.expense, "830", D(2026, 10, 3), "Supermercado", category: mercado.id))
            let found = AnomalyDetector.categoryAnomalies(transactions: txs, categories: cats, today: today)
            t.equal(found.count, 1); let a = found[0]
            t.equal(a.categoryName, "Lazer"); t.equal(a.amount, 900); t.equal(a.median, 400)
            t.equal(a.spread, 40, "MAD dos meses = 10, mas o piso de 10% da mediana vence: 400 × 0,10 = 40")
            t.equal(a.score, dec("8.4")); t.equal(a.percentAbove, 125); t.equal(a.increase, 500); t.equal(a.history.count, 5)
        },
        TestCase("gasto atípico: aumento pequeno, histórico curto e categoria constante não disparam") { t in
            let constant = spend(moradia, ["1000", "1000", "1000", "1000", "1000"], monthsBack: 1..<6, prefix: "Aluguel")
            let small = constant + [tx(.expense, "1050", D(2026, 10, 5), "Aluguel extra", category: moradia.id)]
            t.equal(AnomalyDetector.categoryAnomalies(transactions: small, categories: cats, today: today).count, 0, "R$ 50 acima não passa de 3,5")
            let big = constant + [tx(.expense, "1600", D(2026, 10, 5), "Reforma", category: moradia.id)]
            let found = AnomalyDetector.categoryAnomalies(transactions: big, categories: cats, today: today)
            t.equal(found.count, 1); t.equal(found[0].spread, 100, "MAD zero: piso de 10% da mediana")
            // só 2 meses de histórico: sem detecção
            let short = spend(lazer, ["400", "400"], monthsBack: 1..<3) + [tx(.expense, "3000", D(2026, 10, 5), "Viagem", category: lazer.id)]
            t.equal(AnomalyDetector.categoryAnomalies(transactions: short, categories: cats, today: today).count, 0)
        },
        TestCase("gasto atípico: subcategoria soma na categoria pai; transferências e fatura ficam de fora") { t in
            let sub = Category(name: "Cinema", kind: .expense, parentId: lazer.id)
            var txs = spend(lazer, ["400", "420", "380", "410", "390"], monthsBack: 1..<6)
            txs.append(tx(.expense, "600", D(2026, 10, 12), "Ingressos", category: sub.id))
            txs.append(tx(.expense, "300", D(2026, 10, 13), "Show", category: lazer.id))
            var payment = tx(.transfer, "5000", D(2026, 10, 14), "Fatura", category: lazer.id); payment.invoiceId = UUID()
            txs.append(payment)
            let found = AnomalyDetector.categoryAnomalies(transactions: txs, categories: cats + [sub], today: today)
            t.equal(found.first?.amount, 900); t.equal(found.first?.categoryName, "Lazer")
        },
        TestCase("compra individual atípica exige 8 compras anteriores") { t in
            var txs: [Transaction] = []
            for i in 0..<10 { txs.append(tx(.expense, "\(40 + i)", D(2026, 8, 1 + i), unique(i), category: mercado.id)) }
            txs.append(tx(.expense, "900", D(2026, 10, 10), "Geladeira", category: mercado.id))
            txs.append(tx(.expense, "60", D(2026, 10, 11), "Feira", category: mercado.id))
            let found = AnomalyDetector.transactionAnomalies(transactions: txs, categories: cats, today: today)
            t.equal(found.count, 1); t.equal(found[0].title, "Geladeira"); t.equal(found[0].sampleCount, 10)
            let few = Array(txs.suffix(5))
            t.equal(AnomalyDetector.transactionAnomalies(transactions: few, categories: cats, today: today).count, 0)
        },
        TestCase("previsão do saldo no fim do mês: compromissos + gasto variável diário") { t in
            var txs: [Transaction] = []
            txs.append(tx(.expense, "300", D(2026, 8, 20), "Mercado A"))
            txs.append(tx(.expense, "200", D(2026, 9, 15), "Farmácia"))
            txs.append(tx(.expense, "100", D(2026, 10, 5), "Padaria"))
            txs.append(tx(.expense, "200", D(2026, 10, 25), "Conta de luz", status: .pending))
            txs.append(tx(.income, "1000", D(2026, 10, 30), "Freela", status: .pending))
            let avg = BalanceForecaster.variableDailyAverage(transactions: txs, today: today)
            t.equal(avg.days, 60); t.equal(avg.average, 10)
            let f = BalanceForecaster.forecast(startingBalance: 500, transactions: txs, today: today, days: BalanceForecaster.daysLeftInMonth(today))
            t.equal(f.days, 12); t.equal(ymd(f.endDate), "2026-10-31")
            t.equal(f.committedIn, 1000); t.equal(f.committedOut, 200); t.equal(f.committedItemCount, 2)
            t.equal(f.variableTotal, 120); t.equal(f.projectedBalance, 1180)
            t.equal(f.confidence, .high); t.check(!f.goesNegative); t.isNil(f.firstNegativeDate)
            t.equal(f.lowestBalance, 200); t.equal(ymd(f.lowestDate!), "2026-10-29")
            let lines = BalanceForecaster.explanation(for: f)
            t.check(lines.contains { $0.contains("R$\u{00A0}1.180,00") }); t.check(lines.contains { $0.contains("R$\u{00A0}10,00 por dia × 12 dias") })
        },
        TestCase("previsão: poucos dias de histórico = confiança baixa; compra no cartão e recorrência não entram no gasto variável") { t in
            let card = CreditCard(name: "Cartão", limit: 1000, closingDay: 5, dueDay: 10)
            var cardBuy = tx(.expense, "900", D(2026, 10, 14), "TV")
            cardBuy.creditCardId = card.id
            var recurring = tx(.expense, "50", D(2026, 10, 15), "Streaming"); recurring.recurrenceParentId = UUID()
            var installment = tx(.expense, "100", D(2026, 10, 16), "Sofá (1/3)"); installment.installment = InstallmentInfo(number: 1, total: 3, groupId: UUID())
            let normal = tx(.expense, "50", D(2026, 10, 14), "Lanche")
            let avg = BalanceForecaster.variableDailyAverage(transactions: [cardBuy, recurring, installment, normal], today: today)
            t.equal(avg.days, 5); t.equal(avg.average, 10, "só o lanche: 50 ÷ 5 dias")
            let f = BalanceForecaster.forecast(startingBalance: 100, transactions: [normal], today: today, days: 10)
            t.equal(f.confidence, .low)
            t.check(BalanceForecaster.explanation(for: f).contains { $0.contains("Confiança baixa") })
            t.equal(BalanceForecaster.variableDailyAverage(transactions: [], today: today).average, 0)
        },
        TestCase("alerta de saldo negativo: data do primeiro dia negativo e menor saldo") { t in
            let txs = [tx(.expense, "600", D(2026, 8, 20), "Mercado A"),
                       tx(.expense, "400", D(2026, 10, 22), "Aluguel", status: .pending)]
            let r = generate(txs, balance: "100")
            let risk = r.insights.first { $0.id == "risk" }!
            t.equal(risk.severity, .critical); t.equal(risk.kind, .negativeRisk); t.equal(r.insights.first?.id, "risk", "alerta crítico vem primeiro")
            t.check(risk.message.contains("22/10/2026"), risk.message)
            t.equal(ymd(r.forecast30.firstNegativeDate!), "2026-10-22")
            t.check(risk.amount! < 0); t.check(!risk.explanation.isEmpty)
        },
        TestCase("alerta de saldo baixo (positivo, mas abaixo de R$ 100) é aviso, não crítico") { t in
            let r = generate([tx(.expense, "60", D(2026, 10, 25), "Conta", status: .pending), tx(.expense, "1", D(2026, 8, 20), "x")], balance: "130")
            let risk = r.insights.first { $0.id == "risk" }
            t.equal(risk?.severity, .warning); t.equal(risk?.title, "Saldo ficará baixo")
        },
        TestCase("sem risco: saldo folgado não gera alerta") { t in
            let r = generate([tx(.expense, "60", D(2026, 10, 25), "Conta", status: .pending), tx(.expense, "30", D(2026, 8, 20), "x")], balance: "5000")
            t.isNil(r.insights.first { $0.id == "risk" })
            t.check(r.insights.contains { $0.id == "forecast" })
        },
        TestCase("recorrências: mensal, semanal, aumento de preço, valor variável; ignora parcelas e canceladas") { t in
            var txs: [Transaction] = []
            for (i, amount) in ["44.90", "44.90", "44.90", "54.90"].enumerated() {
                txs.append(tx(.expense, amount, thisMonth.adding(months: -(3 - i)).date(day: 6), "Netflix"))
            }
            for k in 1...4 { txs.append(tx(.expense, "34.90", thisMonth.adding(months: -k).date(day: 8), "Spotify Família")) }
            for k in 0..<5 { txs.append(tx(.expense, "30.00", FinanceCalendar.addDays(D(2026, 10, 17), -7 * k), "Academia Diária")) }
            for (k, amount) in [(1, "150.00"), (2, "250.00"), (3, "200.00")] { txs.append(tx(.expense, amount, thisMonth.adding(months: -k).date(day: 15), "Conta de luz")) }
            for k in 1...3 { txs.append(tx(.expense, "99.00", thisMonth.adding(months: -(k + 5)).date(day: 2), "Revista cancelada")) }
            var inst = tx(.expense, "100", D(2026, 8, 5), "Sofá (1/3)"); inst.installment = InstallmentInfo(number: 1, total: 3, groupId: UUID())
            txs.append(inst)
            let found = RecurrenceDetector.detect(transactions: txs, today: today)
            let titles = found.map(\.title)
            t.check(titles.contains("Netflix") && titles.contains("Spotify Família") && titles.contains("Academia Diária") && titles.contains("Conta de luz"), "\(titles)")
            t.check(!titles.contains("Revista cancelada") && !titles.contains { $0.hasPrefix("Sofá") }, "\(titles)")
            let netflix = found.first { $0.title == "Netflix" }!
            t.equal(netflix.frequency, .monthly); t.equal(netflix.occurrences, 4); t.equal(netflix.lastAmount, dec("54.90"))
            t.check(netflix.amountIsStable); t.equal(netflix.typicalAmount, dec("44.90")); t.equal(netflix.priceIncreasePercent, 22); t.equal(netflix.previousAmount, dec("44.90"))
            t.equal(ymd(netflix.nextExpectedDate), "2026-11-06")
            let gym = found.first { $0.title == "Academia Diária" }!
            t.equal(gym.frequency, .weekly); t.equal(gym.monthlyCost, dec("130.00")); t.check(!gym.isSubscriptionLike)
            let luz = found.first { $0.title == "Conta de luz" }!
            t.check(!luz.amountIsStable); t.equal(luz.typicalAmount, 200); t.check(!luz.isSubscriptionLike)
            t.check(found.first { $0.title == "Spotify Família" }!.isSubscriptionLike)
            t.equal(found.first { $0.title == "Spotify Família" }!.annualCost, dec("418.80"))
            // ordenado pelo custo mensal
            t.equal(found.map(\.monthlyCost), found.map(\.monthlyCost).sorted(by: >))
        },
        TestCase("recorrência: exige 3 ocorrências mensais, anual aceita 2, e marca as já declaradas") { t in
            let two = [tx(.expense, "50", thisMonth.adding(months: -2).date(day: 6), "Clube"), tx(.expense, "50", thisMonth.adding(months: -1).date(day: 6), "Clube")]
            t.equal(RecurrenceDetector.detect(transactions: two, today: today).count, 0)
            let yearly = [tx(.expense, "600", D(2025, 10, 3), "Seguro do carro"), tx(.expense, "600", D(2026, 10, 2), "Seguro do carro")]
            let y = RecurrenceDetector.detect(transactions: yearly, today: today)
            t.equal(y.first?.frequency, .yearly); t.equal(y.first?.monthlyCost, 50)
            var declared = (1...3).map { tx(.expense, "20", thisMonth.adding(months: -$0).date(day: 9), "Plano") }
            declared[0].recurrenceParentId = UUID()
            t.check(RecurrenceDetector.detect(transactions: declared, today: today).first!.isDeclared)
            t.equal(RecurrenceDetector.key(for: "NETFLIX.COM 12/3 (2/6)"), "netflix com")
        },
        TestCase("economia: assinaturas somadas e corte de 10% com o cálculo mostrado") { t in
            var txs: [Transaction] = []
            for k in 1...4 { txs.append(tx(.expense, "44.90", thisMonth.adding(months: -k).date(day: 6), "Netflix")) }
            for k in 1...4 { txs.append(tx(.expense, "34.90", thisMonth.adding(months: -k).date(day: 8), "Spotify")) }
            txs += spend(lazer, ["500", "600", "700"], monthsBack: 1..<4, prefix: "Diversão")
            let recurrences = RecurrenceDetector.detect(transactions: txs, today: today)
            let list = SavingsAdvisor.suggestions(transactions: txs, categories: cats, recurrences: recurrences, today: today)
            let subs = list.first { $0.id == "save:subscriptions" }!
            t.equal(subs.monthlySaving, dec("44.90")); t.equal(subs.annualSaving, dec("538.80"))
            t.check(subs.message.contains("2 assinaturas")); t.check(subs.message.contains("R$\u{00A0}79,80"), subs.message)
            let cut = list.first { $0.id == "save:cut:\(lazer.id.uuidString)" }!
            t.equal(cut.monthlySaving, 60); t.equal(cut.annualSaving, 720)
            t.check(cut.explanation.contains { $0.contains("Média mensal: R$\u{00A0}600,00") })
            t.check(cut.explanation.contains { $0.contains("10% de R$\u{00A0}600,00 = R$\u{00A0}60,00") })
        },
        TestCase("economia: categoria de custo fixo (recorrente) e média pequena não são sugeridas para corte") { t in
            var rent = spend(moradia, ["1500", "1500", "1500"], monthsBack: 1..<4, prefix: "Aluguel")
            for i in rent.indices { rent[i].recurrenceParentId = UUID() }
            let small = spend(mercado, ["40", "50", "60"], monthsBack: 1..<4, prefix: "Banca")
            let list = SavingsAdvisor.suggestions(transactions: rent + small, categories: cats, recurrences: [], today: today)
            t.equal(list.count, 0)
        },
        TestCase("relatório: determinístico, ordenado por gravidade, e avisa quando falta histórico") { t in
            var txs = spend(lazer, ["400", "420", "380", "410", "390"], monthsBack: 1..<6)
            txs.append(tx(.expense, "900", D(2026, 10, 12), "Show", category: lazer.id))
            for k in 1...4 { txs.append(tx(.expense, "44.90", thisMonth.adding(months: -k).date(day: 6), "Netflix")) }
            let a = generate(txs, cats), b = generate(txs, cats)
            t.equal(a, b, "mesmos dados, mesmo resultado")
            t.check(a.hasEnoughHistory)
            let severities = a.insights.map(\.severity)
            t.equal(severities, severities.sorted(by: >))
            t.check(a.insights.contains { $0.kind == .anomaly && $0.title == "Gasto atípico em Lazer" })
            t.check(a.insights.contains { $0.kind == .subscription })
            t.check(a.insights.allSatisfy { !$0.explanation.isEmpty && !$0.title.isEmpty && !$0.id.isEmpty })
            t.equal(Set(a.insights.map(\.id)).count, a.insights.count, "ids únicos")
            let empty = generate([], [])
            t.check(!empty.hasEnoughHistory); t.equal(empty.categoryAnomalies.count, 0); t.equal(empty.recurrences.count, 0)
            t.equal(empty.forecastEndOfMonth.projectedBalance, 5000)
        },
        TestCase("faturas a vencer entram nas saídas previstas") { t in
            let due = CashFlowItem(date: D(2026, 10, 28), amount: -1200, label: "Fatura Nubank")
            let f = BalanceForecaster.forecast(startingBalance: 1000, transactions: [], invoiceDues: [due], today: today, days: 12)
            t.equal(f.committedOut, 1200); t.equal(f.projectedBalance, -200); t.equal(ymd(f.firstNegativeDate!), "2026-10-28")
        },
    ]
}
