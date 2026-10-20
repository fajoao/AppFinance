import Foundation

func goalsDebtsInstallmentTests() -> [TestCase] {
    let asOf = D(2026, 10, 19)
    return [
        TestCase("meta: editar valida nome e valor e preserva o progresso") { t in
            let g = Goal(name: "Viagem", targetAmount: 5000, currentAmount: 1200)
            let e = try GoalEngine.edit(g, name: "  Europa ", target: 8000, deadline: D(2027, 6, 1))
            t.equal(e.name, "Europa"); t.equal(e.targetAmount, 8000); t.equal(e.currentAmount, 1200)
            t.equal(e.deadline, D(2027, 6, 1)); t.equal(e.id, g.id)
            t.throwsError(.invalidAmount) { try GoalEngine.edit(g, name: "x", target: 0, deadline: nil) }
            t.throwsError(.invalidState("Informe um nome.")) { try GoalEngine.edit(g, name: "  ", target: 10, deadline: nil) }
        },
        TestCase("meta: aporte gera histórico; retirada não passa de zero; reverter desfaz") { t in
            let g = Goal(name: "Reserva", targetAmount: 1000, currentAmount: 100)
            let a = try GoalEngine.record(g, amount: 250, date: asOf)
            t.equal(a.goal.currentAmount, 350); t.equal(a.entry.amount, 250); t.equal(a.entry.goalId, g.id)
            let w = try GoalEngine.record(a.goal, amount: -500, date: asOf)
            t.equal(w.goal.currentAmount, 0)
            t.equal(w.entry.amount, -350, "registra o que realmente saiu")
            t.equal(GoalEngine.revert(a.goal, entry: a.entry).currentAmount, 100)
            t.throwsError(.invalidAmount) { try GoalEngine.record(g, amount: 0, date: asOf) }
        },
        TestCase("meta: histórico filtra por meta e ordena do mais recente") { t in
            let g1 = UUID(), g2 = UUID()
            let list = [GoalContribution(goalId: g1, amount: 10, date: D(2026, 8, 1)),
                        GoalContribution(goalId: g2, amount: 99, date: D(2026, 9, 1)),
                        GoalContribution(goalId: g1, amount: 20, date: D(2026, 9, 5))]
            t.equal(GoalEngine.history(for: g1, in: list).map(\.amount), [20, 10])
        },
        TestCase("meta: projeção pelo ritmo dos últimos 3 meses") { t in
            let g = Goal(name: "Carro", targetAmount: 10000, currentAmount: 4000, deadline: D(2027, 4, 19))
            let c = [GoalContribution(goalId: g.id, amount: 500, date: D(2026, 8, 10)),
                     GoalContribution(goalId: g.id, amount: 700, date: D(2026, 9, 10)),
                     GoalContribution(goalId: g.id, amount: 800, date: D(2026, 10, 10)),
                     GoalContribution(goalId: g.id, amount: 5000, date: D(2026, 1, 10))] // fora da janela
            let p = GoalEngine.projection(goal: g, contributions: c, asOf: asOf)
            t.equal(p.averageMonthlyContribution, countedAverage)   // (500+700+800)/3 = 666.67
            t.equal(p.monthsToComplete, 9)                         // 6000 / 666.67 = 9.0 -> 9
            t.equal(ymd(p.projectedCompletion!), "2027-07-19")
            t.equal(p.onTrack, false)                               // prazo 19/04/2027
            // meta precisa de 6000/6 meses = 1000; faltam 333.33 por mês
            t.equal(p.extraPerMonthNeeded, dec("333.33"))
        },
        TestCase("meta: projeção sem aportes, concluída, sem prazo e janela curta") { t in
            let g = Goal(name: "X", targetAmount: 1000, currentAmount: 0, deadline: D(2027, 1, 1))
            let none = GoalEngine.projection(goal: g, contributions: [], asOf: asOf)
            t.equal(none.averageMonthlyContribution, 0); t.isNil(none.monthsToComplete); t.isNil(none.projectedCompletion)
            t.equal(none.onTrack, false)
            let done = Goal(name: "Y", targetAmount: 100, currentAmount: 100, deadline: D(2027, 1, 1))
            let pd = GoalEngine.projection(goal: done, contributions: [], asOf: asOf)
            t.equal(pd.monthsToComplete, 0); t.equal(pd.onTrack, true); t.equal(pd.extraPerMonthNeeded, 0)
            let open = Goal(name: "Z", targetAmount: 1000, currentAmount: 200)
            let c = [GoalContribution(goalId: open.id, amount: 200, date: D(2026, 10, 2))]
            let po = GoalEngine.projection(goal: open, contributions: c, asOf: asOf)
            t.equal(po.averageMonthlyContribution, 200, "primeiro aporte neste mês: divide por 1")
            t.equal(po.monthsToComplete, 4); t.isNil(po.onTrack); t.isNil(po.extraPerMonthNeeded)
        },
        TestCase("meta de filho: filtra por membro") { t in
            let kid = UUID()
            let goals = [Goal(name: "Bicicleta", targetAmount: 500, memberId: kid), Goal(name: "Casa", targetAmount: 9)]
            t.equal(GoalEngine.goals(for: kid, in: goals).map(\.name), ["Bicicleta"])
            t.equal(GoalEngine.goals(for: nil, in: goals).map(\.name), ["Casa"])
        },
        TestCase("dívidas: série mensal de saldo para o gráfico e fim em zero") { t in
            let debts = [Debt(name: "Cartão", balance: 1000, monthlyInterestRate: dec("0.10"), minimumPayment: 100),
                         Debt(name: "Empréstimo", balance: 2000, monthlyInterestRate: dec("0.02"), minimumPayment: 100)]
            let r = try DebtEngine.simulate(debts: debts, monthlyBudget: 600, strategy: .avalanche)
            t.equal(r.monthlyBalances.count, r.months)
            t.equal(r.monthlyBalances.last, 0)
            t.check(r.monthlyBalances.first! < 3000 + 220, "primeiro mês já amortiza")
            t.check(zip(r.monthlyBalances, r.monthlyBalances.dropFirst()).allSatisfy { $0 >= $1 }, "saldo nunca sobe com orçamento folgado")
            let c = try DebtEngine.compare(debts: debts, monthlyBudget: 600)
            t.check(c.avalanche.totalInterest <= c.snowball.totalInterest)
            t.equal(c.interestSavedByAvalanche, c.snowball.totalInterest - c.avalanche.totalInterest)
        },
        TestCase("parcelas: escopo de exclusão (esta, esta e seguintes, todas)") { t in
            let base = Transaction(type: .expense, amount: 300, date: D(2026, 1, 10), title: "TV", accountId: UUID())
            let list = try InstallmentEngine.makeInstallments(from: base, count: 4)
            let other = tx(.expense, "5", D(2026, 1, 1))
            let all = list + [other]
            t.equal(InstallmentEngine.idsToDelete(list[1], scope: .thisOnly, in: all), [list[1].id])
            t.equal(InstallmentEngine.idsToDelete(list[1], scope: .thisAndFuture, in: all), [list[1].id, list[2].id, list[3].id])
            t.equal(InstallmentEngine.idsToDelete(list[2], scope: .all, in: all), list.map(\.id))
            t.equal(InstallmentEngine.idsToDelete(other, scope: .all, in: all), [other.id])
            t.equal(InstallmentEngine.groupMembers(of: list[3], in: all.shuffled()).map(\.id), list.map(\.id))
        },
        TestCase("persistência: arquivo da Fase 1 (sem campos novos) continua carregando") { t in
            let legacy = """
            {"version":1,"accounts":[{"id":"11111111-1111-1111-1111-111111111111","name":"Antiga","type":"checking","initialBalance":10,"currency":"BRL","isArchived":false,"createdAt":0,"updatedAt":0}],
             "categories":[{"id":"22222222-2222-2222-2222-222222222222","name":"Mercado","kind":"expense","createdAt":0,"updatedAt":0}],
             "tags":[],"transactions":[],"creditCards":[],"invoices":[],"budgets":[],"goals":[],"debts":[],"households":[],"familyMembers":[]}
            """
            let snap = try JSONFileStore.decoder.decode(FinanceSnapshot.self, from: Data(legacy.utf8))
            t.equal(snap.accounts.first?.visibility, .shared)
            t.equal(snap.categories.first?.visibility, .shared)
            t.isNil(snap.categories.first?.taxKind)
            t.equal(snap.investments.count, 0); t.equal(snap.tombstones.count, 0); t.equal(snap.version, 1)
            // novo -> JSON -> novo
            var s2 = FinanceSnapshot()
            s2.accounts = [Account(name: "Privada", type: .wallet, visibility: .personal)]
            s2.categories = [Category(name: "Saúde", kind: .expense, taxKind: .health)]
            let data = try JSONFileStore.encoder.encode(s2)
            let back = try JSONFileStore.decoder.decode(FinanceSnapshot.self, from: data)
            t.equal(back, s2); t.equal(back.accounts[0].visibility, .personal); t.equal(back.categories[0].taxKind, .health)
        },
    ]
}

private let countedAverage = dec("666.67")
