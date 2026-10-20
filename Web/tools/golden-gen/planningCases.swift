import Foundation

func planningCases() {
    // Categorias: 1 Moradia(pai), 2 Aluguel(filha de 1), 3 Mercado, 4 Lazer, 5 Salário (receita), 6 Freela (receita), 7 Condomínio (filha de 2)
    let cats = [cat(1, "Moradia"), cat(2, "Aluguel", parent: 1), cat(3, "Mercado"), cat(4, "Lazer"), cat(5, "Salário", .income), cat(6, "Freela", .income), cat(7, "Condomínio", parent: 2)]
    let oct = YearMonth(year: 2026, month: 10), sep = YearMonth(year: 2026, month: 9)
    var txs: [Transaction] = [
        tx(1, .income, "5000", d(2026, 10, 5), "Salário", account: 1, cat: 5),
        tx(2, .income, "800.50", d(2026, 10, 20), "Freela", account: 1, cat: 6),
        tx(3, .expense, "1500", d(2026, 10, 6), "Aluguel", account: 1, cat: 2),
        tx(4, .expense, "300.25", d(2026, 10, 7), "Condomínio", account: 1, cat: 7),
        tx(5, .expense, "820", d(2026, 10, 8), "Mercado", account: 1, cat: 3),
        tx(6, .expense, "150", d(2026, 10, 9), "Cinema", status: .pending, account: 1, cat: 4),
        tx(7, .expense, "99.99", d(2026, 10, 10), "Sem categoria", account: 1),
        tx(8, .transfer, "1000", d(2026, 10, 11), "Transf", account: 1, dest: 2),
        tx(9, .transfer, "700", d(2026, 10, 12), "Pagamento fatura", account: 1, card: 1, invoice: uid(500)),
        tx(10, .expense, "400", d(2026, 10, 13), "Compra cartão mercado", cat: 3, card: 1),
        tx(11, .expense, "-50", d(2026, 10, 14), "Estorno mercado", account: 1, cat: 3),
        tx(12, .income, "4000", d(2026, 9, 5), "Salário set", account: 1, cat: 5),
        tx(13, .expense, "1800", d(2026, 9, 6), "Aluguel set", account: 1, cat: 2),
        tx(14, .expense, "500", d(2026, 9, 8), "Mercado set", account: 1, cat: 3),
        tx(15, .expense, "10", d(2026, 9, 30), "Lazer set", account: 1, cat: 4),
        tx(16, .expense, "33.33", d(2026, 10, 31), "Fim do mês", account: 1, cat: 4),
        tx(17, .expense, "33.34", d(2026, 10, 1), "Início do mês", account: 1, cat: 4),
    ]
    txs.append(tx(18, .income, "10", d(2026, 8, 1), "Ago", account: 1, cat: 5))

    // Orçamento
    var budgets: [Budget] = []
    func bud(_ n: Int, _ catId: Int, _ m: YearMonth, _ limit: String) -> Budget {
        var b = Budget(categoryId: uid(catId), month: m, limit: dec(limit)); b.id = uid(n); b.createdAt = stampDate; b.updatedAt = stampDate; return b
    }
    budgets = [bud(1, 1, oct, "2000"), bud(2, 3, oct, "1000"), bud(3, 4, oct, "200"), bud(4, 4, sep, "5"), bud(5, 2, oct, "1800.25"), bud(6, 6, oct, "0"), bud(7, 3, sep, "500")]
    for onlyPaid in [false, true] {
        let sts = budgets.map { BudgetEngine.status(budget: $0, transactions: txs, categories: cats, onlyPaid: onlyPaid) }
        add("budget.statuses", "statuses onlyPaid=\(onlyPaid)", input: ["budgets": ents(budgets), "transactions": ents(txs), "categories": ents(cats), "onlyPaid": onlyPaid],
            expected: sts.map { ["id": $0.budget.id.uuidString, "spent": S($0.spent), "remaining": S($0.remaining), "percentUsed": S($0.percentUsed), "alert": $0.alert.rawValue] as J })
    }
    for m in [oct, sep] {
        let al = BudgetEngine.alerts(month: m, budgets: budgets, transactions: txs, categories: cats)
        add("budget.alerts", "alerts \(m.label)", input: ["month": YMj(m), "budgets": ents(budgets), "transactions": ents(txs), "categories": ents(cats)], expected: al.map { $0.budget.id.uuidString })
    }
    for (spent, limit) in [("79.99", "100"), ("80", "100"), ("99.99", "100"), ("100", "100"), ("0", "0"), ("1", "0"), ("800.01", "1000"), ("0", "-5")] {
        add("budget.alert", "alert \(spent)/\(limit)", input: ["spent": spent, "limit": limit], expected: BudgetEngine.alert(spent: dec(spent), limit: dec(limit)).rawValue)
    }
    let copied = BudgetEngine.copy(budgets: budgets, from: oct, to: YearMonth(year: 2026, month: 11))
    add("budget.copy", "copy oct->nov", input: ["budgets": ents(budgets), "from": YMj(oct), "to": YMj(YearMonth(year: 2026, month: 11))],
        expected: copied.map { ["categoryId": $0.categoryId.uuidString, "limit": S($0.limit), "month": YMj($0.month)] as J })

    // Resumo mensal
    func catTotals(_ list: [CategoryTotal]) -> [J] { list.map { ["categoryId": U($0.categoryId), "amount": S($0.amount), "percent": S($0.percentOfTotal)] } }
    for (m, onlyPaid) in [(oct, false), (oct, true), (sep, false), (YearMonth(year: 2026, month: 8), false), (YearMonth(year: 2026, month: 1), false)] {
        let s = SummaryEngine.summary(month: m, transactions: txs, onlyPaid: onlyPaid)
        let c = s.comparison
        add("summary.month", "summary \(m.label) paid=\(onlyPaid)", input: ["month": YMj(m), "transactions": ents(txs), "onlyPaid": onlyPaid],
            expected: ["income": S(s.income), "expense": S(s.expense), "balance": S(s.balance), "expensesByCategory": catTotals(s.expensesByCategory),
                       "incomeByCategory": catTotals(s.incomeByCategory),
                       "comparison": ["previousIncome": S(c.previousIncome), "previousExpense": S(c.previousExpense), "incomeDelta": S(c.incomeDelta), "expenseDelta": S(c.expenseDelta),
                                      "incomeChangePercent": S(c.incomeChangePercent), "expenseChangePercent": S(c.expenseChangePercent)] as J] as J)
    }

    // Fluxo de caixa
    let from = d(2026, 10, 20)
    var cfTx: [Transaction] = [
        tx(1, .expense, "1500", d(2026, 10, 25), "Aluguel", status: .pending, account: 1),
        tx(2, .income, "5000", d(2026, 11, 5), "Salário", status: .pending, account: 1),
        tx(3, .expense, "200", d(2026, 10, 20), "Hoje (fora da janela)", status: .pending, account: 1),
        tx(4, .expense, "300", d(2026, 11, 10), "Compra cartão pendente", status: .pending, card: 1),
        tx(5, .transfer, "700", d(2026, 11, 15), "Pagamento fatura", status: .pending, account: 1, card: 1, invoice: uid(500)),
        tx(6, .transfer, "100", d(2026, 11, 16), "Entre contas", status: .pending, account: 1, dest: 2),
        tx(7, .expense, "99.90", d(2026, 10, 31), "Assinatura", status: .paid, account: 1, recurrence: RecurrenceRule(frequency: .monthly)),
        tx(8, .income, "250", d(2026, 10, 22), "Aluguel recebido", status: .paid, account: 1, recurrence: RecurrenceRule(frequency: .weekly, interval: 2)),
        tx(9, .expense, "50", d(2027, 1, 15), "Longe", status: .pending, account: 1),
    ]
    cfTx.append(tx(10, .expense, "99.90", d(2026, 11, 30), "Assinatura", status: .pending, account: 1, parent: cfTx[6].id))
    let dues = [CashFlowItem(date: d(2026, 11, 8), amount: dec("-650.40"), label: "Fatura Roxo 11/2026"), CashFlowItem(date: d(2027, 6, 1), amount: dec("-1"), label: "Longe demais")]
    for days in [30, 60, 90] {
        let p = CashFlowEngine.project(startingBalance: dec("3500.75"), from: from, days: days, transactions: cfTx, invoiceDues: dues)
        add("cashflow.project", "cashflow \(days)d",
            input: ["startingBalance": "3500.75", "from": iso(from), "days": days, "transactions": ents(cfTx),
                    "invoiceDues": dues.map { ["date": iso($0.date), "amount": S($0.amount), "label": $0.label] as J }],
            expected: ["ending": S(p.endingBalance), "lowest": S(p.lowestBalance), "lowestDate": isoN(p.lowestBalanceDate), "totalIn": S(p.totalIn), "totalOut": S(p.totalOut),
                       "goesNegative": p.goesNegative, "pointCount": p.points.count,
                       "items": p.items.map { ["date": iso($0.date), "amount": S($0.amount), "label": $0.label] as J },
                       "points": p.points.map { ["date": iso($0.date), "change": S($0.change), "balance": S($0.balance)] as J }] as J)
    }
    let neg = CashFlowEngine.project(startingBalance: dec("100"), from: from, days: 30, transactions: cfTx)
    add("cashflow.project", "cashflow negative", input: ["startingBalance": "100", "from": iso(from), "days": 30, "transactions": ents(cfTx), "invoiceDues": [Any]()],
        expected: ["ending": S(neg.endingBalance), "lowest": S(neg.lowestBalance), "lowestDate": isoN(neg.lowestBalanceDate), "totalIn": S(neg.totalIn), "totalOut": S(neg.totalOut),
                   "goesNegative": neg.goesNegative, "pointCount": neg.points.count,
                   "items": neg.items.map { ["date": iso($0.date), "amount": S($0.amount), "label": $0.label] as J },
                   "points": neg.points.map { ["date": iso($0.date), "change": S($0.change), "balance": S($0.balance)] as J }] as J)

    // Dívidas
    func debt(_ n: Int, _ name: String, _ bal: String, _ rate: String, _ min: String) -> Debt {
        var x = Debt(name: name, balance: dec(bal), monthlyInterestRate: dec(rate), minimumPayment: dec(min)); x.id = uid(n); x.createdAt = stampDate; x.updatedAt = stampDate; return x
    }
    func payJ(_ r: PayoffResult) -> J {
        ["months": r.months, "totalInterest": S(r.totalInterest), "totalPaid": S(r.totalPaid), "order": r.payoffOrder.map { $0.uuidString },
         "payoffMonth": Dictionary(uniqueKeysWithValues: r.payoffMonth.map { ($0.key.uuidString, $0.value) }), "feasible": r.feasible, "monthlyBalances": r.monthlyBalances.map(S)]
    }
    let debtSets: [(String, [Debt], String)] = [
        ("tres dividas", [debt(1, "Cartão", "4500.50", "0.1299", "300"), debt(2, "Empréstimo", "12000", "0.0299", "450"), debt(3, "Cheque especial", "800", "0.0799", "80"), debt(4, "Loja", "600", "0.0199", "50")], "2200"),
        ("orcamento folgado", [debt(1, "A", "1000", "0.02", "50"), debt(2, "B", "3000", "0.01", "100")], "5000"),
        ("so minimos", [debt(1, "A", "1000", "0.02", "50"), debt(2, "B", "300", "0.05", "30")], "80"),
        ("inviavel", [debt(1, "Agiota", "10000", "0.20", "100")], "100"),
        ("uma so", [debt(1, "Única", "2500.99", "0.0349", "200")], "400"),
        ("empate taxa e saldo", [debt(1, "X", "1000", "0.02", "50"), debt(2, "Y", "1000", "0.02", "50")], "300"),
        ("saldo zero ignorado", [debt(1, "Z", "0", "0.02", "50"), debt(2, "W", "100", "0.02", "10")], "60"),
    ]
    for (name, ds, budget) in debtSets {
        var exp: J = [:]
        do {
            let c = try DebtEngine.compare(debts: ds, monthlyBudget: dec(budget))
            exp = ["ok": true, "avalanche": payJ(c.avalanche), "snowball": payJ(c.snowball), "saved": S(c.interestSavedByAvalanche)]
        } catch let e as FinanceError {
            if case .budgetBelowMinimums(let r) = e { exp = ["ok": false, "required": S(r), "message": e.description] } else { fatalError() }
        } catch { fatalError() }
        add("debts.compare", name, input: ["debts": ents(ds), "budget": budget], expected: exp)
    }
    add("debts.compare", "orçamento abaixo dos mínimos", input: ["debts": ents(debtSets[0].1), "budget": "100"],
        expected: { () -> J in
            do { _ = try DebtEngine.compare(debts: debtSets[0].1, monthlyBudget: dec("100")); fatalError() }
            catch let e as FinanceError { if case .budgetBelowMinimums(let r) = e { return ["ok": false, "required": S(r), "message": e.description] } ; fatalError() }
            catch { fatalError() }
        }())

    // Metas
    func goal(_ n: Int, _ name: String, target: String, current: String, deadline: Date?) -> Goal {
        var g = Goal(name: name, targetAmount: dec(target), currentAmount: dec(current), deadline: deadline); g.id = uid(n); g.createdAt = stampDate; g.updatedAt = stampDate; return g
    }
    func gpJ(_ p: GoalProgress) -> J {
        ["percent": S(p.percent), "remaining": S(p.remaining), "complete": p.isComplete, "months": p.monthsRemaining as Any? ?? NSNull(), "needed": S(p.monthlyContributionNeeded)]
    }
    let asOfG = d(2026, 10, 20)
    let goals = [goal(1, "Viagem", target: "12000", current: "3000", deadline: d(2027, 6, 15)), goal(2, "Sem prazo", target: "500", current: "100.50", deadline: nil),
                 goal(3, "Concluída", target: "1000", current: "1500", deadline: d(2027, 1, 1)), goal(4, "Vencida", target: "1000", current: "100", deadline: d(2026, 9, 1)),
                 goal(5, "Mesmo mês depois", target: "1000", current: "100", deadline: d(2026, 10, 28)), goal(6, "Mesmo dia", target: "1000", current: "100", deadline: d(2026, 10, 20)),
                 goal(7, "Valor quebrado", target: "1000", current: "0.01", deadline: d(2027, 1, 20)), goal(8, "Alvo zero", target: "0", current: "5", deadline: nil)]
    for g in goals { add("goal.progress", "progress \(g.name)", input: ["goal": ent(g), "asOf": iso(asOfG)], expected: gpJ(GoalEngine.progress(goal: g, asOf: asOfG))) }
    func contrib(_ n: Int, _ goalId: Int, _ amount: String, _ date: Date) -> GoalContribution {
        var c = GoalContribution(goalId: uid(goalId), amount: dec(amount), date: date); c.id = uid(n); c.createdAt = stampDate; c.updatedAt = stampDate; return c
    }
    let contribs = [contrib(1, 1, "500", d(2026, 8, 10)), contrib(2, 1, "700", d(2026, 9, 12)), contrib(3, 1, "-100", d(2026, 10, 2)), contrib(4, 1, "1000", d(2026, 10, 25)),
                    contrib(5, 1, "50", d(2026, 5, 1)), contrib(6, 4, "100", d(2026, 10, 1)), contrib(7, 5, "300", d(2026, 10, 3)), contrib(8, 7, "0.02", d(2026, 10, 3))]
    for g in goals {
        for look in [3, 6] {
            let p = GoalEngine.projection(goal: g, contributions: contribs, asOf: asOfG, lookbackMonths: look)
            add("goal.projection", "projection \(g.name) look=\(look)", input: ["goal": ent(g), "contributions": ents(contribs), "asOf": iso(asOfG), "lookback": look],
                expected: ["average": S(p.averageMonthlyContribution), "months": p.monthsToComplete as Any? ?? NSNull(), "completion": isoN(p.projectedCompletion),
                           "onTrack": p.onTrack as Any? ?? NSNull(), "extra": S(p.extraPerMonthNeeded)] as J)
        }
    }
    let hist = GoalEngine.history(for: uid(1), in: contribs)
    add("goal.history", "history order", input: ["contributions": ents(contribs), "goalId": uid(1).uuidString], expected: hist.map { $0.id.uuidString })
}
