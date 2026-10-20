import Foundation

private func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

func planningTests() -> [TestCase] {
    let food = Category(name: "Alimentação", kind: .expense)
    let rest = Category(name: "Restaurantes", kind: .expense, parentId: food.id)
    let sub2 = Category(name: "Pizza", kind: .expense, parentId: rest.id)
    let other = Category(name: "Transporte", kind: .expense)
    let cats = [food, rest, sub2, other]
    let salary = Category(name: "Salário", kind: .income)

    return [
        TestCase("orçamento: gasto inclui subcategorias (vários níveis) e ignora outros meses/receitas/transferências") { t in
            let txs = [tx(.expense, "400", D(2025, 1, 5), category: food.id), tx(.expense, "100", D(2025, 1, 9), category: rest.id),
                       tx(.expense, "50", D(2025, 1, 10), category: sub2.id), tx(.expense, "70", D(2025, 1, 11), category: other.id),
                       tx(.expense, "999", D(2025, 2, 1), category: food.id), tx(.income, "999", D(2025, 1, 2), category: food.id),
                       tx(.transfer, "999", D(2025, 1, 2), category: food.id)]
            t.equal(BudgetEngine.spent(categoryId: food.id, month: ym(2025, 1), transactions: txs, categories: cats), 550)
            t.equal(BudgetEngine.spent(categoryId: food.id, month: ym(2025, 1), transactions: txs, categories: []), 400)
            t.equal(BudgetEngine.spent(categoryId: rest.id, month: ym(2025, 1), transactions: txs, categories: cats), 150)
            t.equal(BudgetEngine.spent(categoryId: other.id, month: ym(2025, 1), transactions: txs, categories: cats), 70)
        },
        TestCase("orçamento: onlyPaid") { t in
            let txs = [tx(.expense, "100", D(2025, 1, 5), category: food.id), tx(.expense, "50", D(2025, 1, 6), status: .pending, category: food.id)]
            t.equal(BudgetEngine.spent(categoryId: food.id, month: ym(2025, 1), transactions: txs), 150)
            t.equal(BudgetEngine.spent(categoryId: food.id, month: ym(2025, 1), transactions: txs, onlyPaid: true), 100)
        },
        TestCase("orçamento: alertas em 80% e 100% (limites exatos)") { t in
            t.equal(BudgetEngine.alert(spent: dec("479.99"), limit: 600), .none)
            t.equal(BudgetEngine.alert(spent: 480, limit: 600), .warning)
            t.equal(BudgetEngine.alert(spent: dec("599.99"), limit: 600), .warning)
            t.equal(BudgetEngine.alert(spent: 600, limit: 600), .exceeded)
            t.equal(BudgetEngine.alert(spent: dec("600.01"), limit: 600), .exceeded)
            t.equal(BudgetEngine.alert(spent: 0, limit: 600), .none)
            t.equal(BudgetEngine.alert(spent: 0, limit: 0), .none)
            t.equal(BudgetEngine.alert(spent: 1, limit: 0), .exceeded)
        },
        TestCase("orçamento: status, percentual e restante") { t in
            let b = Budget(categoryId: food.id, month: ym(2025, 1), limit: 600)
            let txs = [tx(.expense, "500", D(2025, 1, 5), category: food.id)]
            let s = BudgetEngine.status(budget: b, transactions: txs)
            t.equal(s.spent, 500); t.equal(s.percentUsed, dec("83.33")); t.equal(s.remaining, 100); t.equal(s.alert, .warning)
            let over = BudgetEngine.status(budget: b, transactions: [tx(.expense, "750.50", D(2025, 1, 5), category: food.id)])
            t.equal(over.percentUsed, dec("125.08")); t.equal(over.remaining, dec("-150.50")); t.equal(over.alert, .exceeded)
            let none = BudgetEngine.status(budget: b, transactions: [])
            t.equal(none.percentUsed, 0); t.equal(none.alert, .none)
        },
        TestCase("orçamento: alerts() ordena e filtra por mês; copy entre meses") { t in
            let b1 = Budget(categoryId: food.id, month: ym(2025, 1), limit: 100)
            let b2 = Budget(categoryId: other.id, month: ym(2025, 1), limit: 100)
            let b3 = Budget(categoryId: other.id, month: ym(2025, 2), limit: 100)
            let txs = [tx(.expense, "85", D(2025, 1, 2), category: food.id), tx(.expense, "120", D(2025, 1, 3), category: other.id), tx(.expense, "10", D(2025, 1, 4), category: salary.id)]
            let a = BudgetEngine.alerts(month: ym(2025, 1), budgets: [b1, b2, b3], transactions: txs)
            t.equal(a.map(\.budget.id), [b2.id, b1.id])
            let copied = BudgetEngine.copy(budgets: [b1, b2, b3], from: ym(2025, 1), to: ym(2025, 2))
            t.equal(copied.count, 2); t.check(copied.allSatisfy { $0.month == ym(2025, 2) && $0.id != b1.id && $0.id != b2.id })
        },
        TestCase("resumo mensal: receitas, despesas, saldo, por categoria") { t in
            let txs = [tx(.income, "5000", D(2025, 1, 5), category: salary.id), tx(.expense, "1000.10", D(2025, 1, 6), category: food.id),
                       tx(.expense, "500.05", D(2025, 1, 7), category: other.id), tx(.expense, "10", D(2025, 1, 8)),
                       tx(.transfer, "700", D(2025, 1, 9)), tx(.expense, "42", D(2025, 2, 1), category: food.id)]
            let s = SummaryEngine.summary(month: ym(2025, 1), transactions: txs)
            t.equal(s.income, 5000); t.equal(s.expense, dec("1510.15")); t.equal(s.balance, dec("3489.85"))
            t.equal(s.expensesByCategory.map(\.categoryId), [food.id, other.id, nil])
            t.equal(s.expensesByCategory.map(\.amount), [dec("1000.10"), dec("500.05"), 10])
            t.equal(s.expensesByCategory[0].percentOfTotal, dec("66.23"))
            t.equal(s.incomeByCategory.count, 1); t.equal(s.incomeByCategory[0].percentOfTotal, 100)
        },
        TestCase("resumo mensal: pagamento de fatura e transferências não contam; compra de cartão conta") { t in
            let cardId = UUID()
            let purchase = Transaction(type: .expense, amount: 200, date: D(2025, 1, 5), title: "c", categoryId: food.id, creditCardId: cardId)
            let payment = Transaction(type: .transfer, amount: 200, date: D(2025, 2, 12), title: "p", accountId: UUID(), creditCardId: cardId, invoiceId: UUID())
            t.equal(SummaryEngine.totals(month: ym(2025, 1), transactions: [purchase, payment]).expense, 200)
            t.equal(SummaryEngine.totals(month: ym(2025, 2), transactions: [purchase, payment]).expense, 0)
            // tipo despesa mas com invoiceId também é ignorado
            var weird = payment; weird.type = .expense
            t.equal(SummaryEngine.totals(month: ym(2025, 2), transactions: [weird]).expense, 0)
        },
        TestCase("resumo mensal: comparação com mês anterior, virada de ano") { t in
            let txs = [tx(.expense, "200", D(2024, 12, 20)), tx(.income, "1000", D(2024, 12, 5)),
                       tx(.expense, "150", D(2025, 1, 20)), tx(.income, "1500", D(2025, 1, 5))]
            let c = SummaryEngine.summary(month: ym(2025, 1), transactions: txs).comparison
            t.equal(c.previousExpense, 200); t.equal(c.expenseDelta, -50); t.equal(c.expenseChangePercent, dec("-25"))
            t.equal(c.previousIncome, 1000); t.equal(c.incomeDelta, 500); t.equal(c.incomeChangePercent, dec("50"))
        },
        TestCase("resumo mensal: mês anterior zero -> variação nil; fevereiro bissexto inclui dia 29") { t in
            let txs = [tx(.expense, "10", D(2024, 2, 29)), tx(.expense, "5", D(2024, 3, 1))]
            let s = SummaryEngine.summary(month: ym(2024, 2), transactions: txs)
            t.equal(s.expense, 10); t.isNil(s.comparison.expenseChangePercent)
            t.equal(SummaryEngine.summary(month: ym(2024, 3), transactions: txs).expense, 5)
            let empty = SummaryEngine.summary(month: ym(2025, 5), transactions: [])
            t.equal(empty.balance, 0); t.equal(empty.expensesByCategory.count, 0)
        },
        TestCase("resumo mensal: onlyPaid e estornos") { t in
            let txs = [tx(.expense, "100", D(2025, 1, 1)), tx(.expense, "50", D(2025, 1, 2), status: .pending), tx(.expense, "-30", D(2025, 1, 3))]
            t.equal(SummaryEngine.totals(month: ym(2025, 1), transactions: txs).expense, 120)
            t.equal(SummaryEngine.totals(month: ym(2025, 1), transactions: txs, onlyPaid: true).expense, 70)
        },
        TestCase("fluxo de caixa 30/60/90 com pendentes, recorrentes e fatura") { t in
            let from = D(2025, 1, 1)
            var rent = tx(.expense, "300", D(2025, 1, 15), "Aluguel", status: .pending)
            rent.recurrence = RecurrenceRule(frequency: .monthly)
            let txs = [tx(.expense, "200", D(2025, 1, 10), "Luz", status: .pending), tx(.income, "500", D(2025, 2, 5), "Freela", status: .pending),
                       rent,
                       tx(.expense, "9999", D(2025, 1, 20), "já pago"),                       // pago: ignorado
                       Transaction(type: .expense, amount: 777, date: D(2025, 1, 12), title: "cartão", status: .pending, creditCardId: UUID()), // compra cartão: ignorada
                       Transaction(type: .transfer, amount: 400, date: D(2025, 1, 13), title: "tr", status: .pending, accountId: UUID(), destinationAccountId: UUID())]
            let dues = [CashFlowItem(date: D(2025, 2, 20), amount: -150, label: "Fatura")]
            let p = CashFlowEngine.standardProjections(startingBalance: 1000, from: from, transactions: txs, invoiceDues: dues)
            t.equal(p[30]!.endingBalance, 500)       // -200 -300
            t.equal(p[60]!.endingBalance, 550)       // +500 -300 (15/fev) -150
            t.equal(p[90]!.endingBalance, 250)       // -300 (15/mar)
            t.equal(p[30]!.points.count, 30); t.equal(p[90]!.points.count, 90)
            t.equal(ymd(p[60]!.points[0].date), "2025-01-02"); t.equal(ymd(p[60]!.points.last!.date), "2025-03-02")
            t.equal(p[60]!.lowestBalance, 500); t.equal(p[60]!.lowestBalanceDate.map(ymd), "2025-01-15")
            t.equal(p[60]!.totalIn, 500); t.equal(p[60]!.totalOut, 950)
            t.check(!p[60]!.goesNegative)
            t.equal(p[90]!.items.map(\.label), ["Luz", "Aluguel", "Freela", "Aluguel", "Fatura", "Aluguel"])
        },
        TestCase("fluxo de caixa: saldo negativo, janela exclui o dia inicial, vazio") { t in
            let txs = [tx(.expense, "300", D(2025, 1, 5), status: .pending), tx(.expense, "50", D(2025, 1, 1), status: .pending)]
            let p = CashFlowEngine.project(startingBalance: 100, from: D(2025, 1, 1), days: 30, transactions: txs)
            t.equal(p.endingBalance, -200); t.check(p.goesNegative); t.equal(p.lowestBalanceDate.map(ymd), "2025-01-05")
            let e = CashFlowEngine.project(startingBalance: 100, from: D(2025, 1, 1), days: 30, transactions: [])
            t.equal(e.endingBalance, 100); t.isNil(e.lowestBalanceDate); t.equal(e.items.count, 0)
        },
        TestCase("fluxo de caixa: pagamento de fatura pendente é saída; ocorrências já geradas não duplicam") { t in
            var tpl = tx(.expense, "100", D(2025, 1, 10), "Assinatura", status: .pending)
            tpl.recurrence = RecurrenceRule(frequency: .monthly)
            let generated = RecurrenceEngine.generate(from: tpl, from: D(2025, 1, 1), to: D(2025, 3, 31))
            let pay = Transaction(type: .transfer, amount: 80, date: D(2025, 1, 20), title: "fatura", status: .pending, accountId: UUID(), invoiceId: UUID())
            let p = CashFlowEngine.project(startingBalance: 1000, from: D(2025, 1, 1), days: 90, transactions: [tpl] + generated + [pay])
            t.equal(p.endingBalance, 1000 - 100 * 3 - 80)
        },
        TestCase("fluxo de caixa: invoiceDues a partir de faturas") { t in
            let c = CreditCard(name: "Visa", limit: 1000, closingDay: 10, dueDay: 20)
            let txs = [Transaction(type: .expense, amount: 120, date: D(2025, 1, 5), title: "x", creditCardId: c.id)]
            let list = CreditCardEngine.upcomingInvoices(card: c, transactions: txs, asOf: D(2025, 1, 12), futureCount: 1)
            let dues = CashFlowEngine.invoiceDues(summaries: list, cardNames: [c.id: "Visa"])
            t.equal(dues.count, 1); t.equal(dues[0].amount, -120); t.equal(dues[0].label, "Fatura Visa 01/2025")
            t.equal(CashFlowEngine.project(startingBalance: 500, from: D(2025, 1, 12), days: 30, transactions: [], invoiceDues: dues).endingBalance, 380)
        },
    ]
}

func debtGoalTests() -> [TestCase] {
    [
        TestCase("dívida única: cronograma exato com juros") { t in
            let d = Debt(name: "Empréstimo", balance: 1000, monthlyInterestRate: dec("0.01"), minimumPayment: 500)
            let r = try DebtEngine.simulate(debts: [d], monthlyBudget: 500, strategy: .avalanche)
            t.equal(r.months, 3); t.equal(r.totalInterest, dec("15.25")); t.equal(r.totalPaid, dec("1015.25"))
            t.check(r.feasible); t.equal(r.payoffOrder, [d.id]); t.equal(r.payoffMonth[d.id], 3)
        },
        TestCase("dívida sem juros: 1000 a 300/mês = 4 meses") { t in
            let d = Debt(name: "Amigo", balance: 1000, monthlyInterestRate: 0, minimumPayment: 100)
            let r = try DebtEngine.simulate(debts: [d], monthlyBudget: 300, strategy: .snowball)
            t.equal(r.months, 4); t.equal(r.totalInterest, 0); t.equal(r.totalPaid, 1000)
        },
        TestCase("avalanche quita primeiro a maior taxa; bola de neve o menor saldo; avalanche paga menos juros") { t in
            let small = Debt(name: "Loja", balance: 500, monthlyInterestRate: dec("0.01"), minimumPayment: 25)
            let big = Debt(name: "Cartão", balance: 5000, monthlyInterestRate: dec("0.04"), minimumPayment: 100)
            let (a, s, saved) = try DebtEngine.compare(debts: [small, big], monthlyBudget: 600)
            t.equal(s.payoffOrder.first, small.id)
            t.equal(a.payoffOrder.first, big.id)
            t.equal(a.payoffOrder.last, small.id)
            t.check(a.totalInterest < s.totalInterest, "avalanche deve pagar menos juros: \(a.totalInterest) vs \(s.totalInterest)")
            t.equal(saved, s.totalInterest - a.totalInterest)
            t.check(a.feasible && s.feasible)
            t.check(a.months <= s.months)
            // conservação: total pago = principal + juros
            t.equal(a.totalPaid, 5500 + a.totalInterest); t.equal(s.totalPaid, 5500 + s.totalInterest)
        },
        TestCase("avalanche: ordem de quitação com taxa maior e saldo menor") { t in
            let a = Debt(name: "A", balance: 1000, monthlyInterestRate: dec("0.05"), minimumPayment: 30)
            let b = Debt(name: "B", balance: 3000, monthlyInterestRate: dec("0.01"), minimumPayment: 30)
            let r = try DebtEngine.simulate(debts: [b, a], monthlyBudget: 500, strategy: .avalanche)
            t.equal(r.payoffOrder, [a.id, b.id])
            t.check(r.payoffMonth[a.id]! < r.payoffMonth[b.id]!)
        },
        TestCase("orçamento abaixo dos mínimos lança erro; dívidas quitadas são ignoradas") { t in
            let a = Debt(name: "A", balance: 1000, monthlyInterestRate: dec("0.01"), minimumPayment: 80)
            let b = Debt(name: "B", balance: 1000, monthlyInterestRate: dec("0.01"), minimumPayment: 80)
            t.throwsError(.budgetBelowMinimums(required: 160)) { try DebtEngine.simulate(debts: [a, b], monthlyBudget: 150, strategy: .avalanche) }
            let paid = Debt(name: "Z", balance: 0, monthlyInterestRate: dec("0.5"), minimumPayment: 999)
            let r = try DebtEngine.simulate(debts: [a, paid], monthlyBudget: 100, strategy: .avalanche)
            t.check(r.feasible && r.months > 0)
            let none = try DebtEngine.simulate(debts: [], monthlyBudget: 0, strategy: .snowball)
            t.equal(none.months, 0); t.check(none.feasible)
        },
        TestCase("pagamento que não cobre os juros é inviável (sem estouro)") { t in
            let d = Debt(name: "Rotativo", balance: 1000, monthlyInterestRate: dec("0.15"), minimumPayment: 50)
            let r = try DebtEngine.simulate(debts: [d], monthlyBudget: 50, strategy: .avalanche)
            t.check(!r.feasible); t.equal(r.months, 1)
        },
        TestCase("meta: progresso e percentual") { t in
            let g = Goal(name: "Viagem", targetAmount: 10000, currentAmount: 2500)
            let p = GoalEngine.progress(goal: g, asOf: D(2025, 1, 15))
            t.equal(p.fraction, dec("0.25")); t.equal(p.percent, 25); t.equal(p.remaining, 7500)
            t.check(!p.isComplete); t.isNil(p.monthsRemaining); t.isNil(p.monthlyContributionNeeded)
        },
        TestCase("meta: aporte mensal necessário (arredonda para cima, virada de ano)") { t in
            var g = Goal(name: "Reserva", targetAmount: 10000, currentAmount: 2500, deadline: D(2026, 1, 15))
            let p = GoalEngine.progress(goal: g, asOf: D(2025, 1, 15))
            t.equal(p.monthsRemaining, 12); t.equal(p.monthlyContributionNeeded, 625)
            g = Goal(name: "G", targetAmount: 1000, currentAmount: 0, deadline: D(2025, 4, 30))
            let p2 = GoalEngine.progress(goal: g, asOf: D(2025, 1, 31))
            t.equal(p2.monthsRemaining, 3); t.equal(p2.monthlyContributionNeeded, dec("333.34"))
            let p3 = GoalEngine.progress(goal: Goal(name: "G", targetAmount: 1000, deadline: D(2025, 2, 10)), asOf: D(2024, 12, 20))
            t.equal(p3.monthsRemaining, 2); t.equal(p3.monthlyContributionNeeded, 500)
        },
        TestCase("meta: prazo vencido, no mês, concluída e superada") { t in
            let late = GoalEngine.progress(goal: Goal(name: "G", targetAmount: 1000, currentAmount: 400, deadline: D(2025, 1, 1)), asOf: D(2025, 3, 1))
            t.equal(late.monthsRemaining, 0); t.equal(late.monthlyContributionNeeded, 600)
            let sameMonth = GoalEngine.progress(goal: Goal(name: "G", targetAmount: 1000, currentAmount: 400, deadline: D(2025, 3, 30)), asOf: D(2025, 3, 1))
            t.equal(sameMonth.monthsRemaining, 1); t.equal(sameMonth.monthlyContributionNeeded, 600)
            let done = GoalEngine.progress(goal: Goal(name: "G", targetAmount: 1000, currentAmount: 1200, deadline: D(2026, 1, 1)), asOf: D(2025, 3, 1))
            t.check(done.isComplete); t.equal(done.fraction, 1); t.equal(done.percent, 100); t.equal(done.remaining, 0); t.equal(done.monthlyContributionNeeded, 0)
            let zero = GoalEngine.progress(goal: Goal(name: "G", targetAmount: 0), asOf: D(2025, 3, 1))
            t.check(zero.isComplete)
        },
        TestCase("meta: aporte e retirada nunca deixam saldo negativo") { t in
            let g = Goal(name: "G", targetAmount: 100, currentAmount: 10)
            t.equal(try GoalEngine.contribute(g, amount: dec("25.50")).currentAmount, dec("35.50"))
            t.equal(try GoalEngine.contribute(g, amount: -50).currentAmount, 0)
            t.throwsError(.invalidAmount) { try GoalEngine.contribute(g, amount: 0) }
        },
    ]
}
