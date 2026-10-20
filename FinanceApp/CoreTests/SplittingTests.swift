import Foundation

func splittingTests() -> [TestCase] {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    return [
        TestCase("divisão igual: centavos exatos, a soma fecha o total") { t in
            let s = try SplitEngine.make(title: "Jantar", total: dec("100.00"), date: D(2026, 10, 1), paidBy: a, participants: [a, b, c], mode: .equal)
            t.equal(s.shares.map(\.amount), [dec("33.33"), dec("33.33"), dec("33.34")])
            t.equal(s.shares.reduce(Decimal(0)) { $0 + $1.amount }, 100)
            t.equal(s.shares.map(\.memberId), [a, b, c])
            t.equal(s.mode, .equal)
        },
        TestCase("divisão percentual: usa os percentuais; deve somar 100") { t in
            let s = try SplitEngine.make(title: "Aluguel", total: 2000, date: D(2026, 10, 1), paidBy: a, participants: [a, b],
                                         mode: .percentage, percentages: [a: 70, b: 30])
            t.equal(s.shares.map(\.amount), [1400, 600]); t.equal(s.shares.map(\.percent), [70, 30])
            let odd = try SplitEngine.make(title: "x", total: dec("100.00"), date: D(2026, 10, 1), paidBy: a, participants: [a, b, c],
                                           mode: .percentage, percentages: [a: dec("33.3"), b: dec("33.3"), c: dec("33.4")])
            t.equal(odd.shares.reduce(Decimal(0)) { $0 + $1.amount }, 100)
            t.throwsError(.invalidPercentages) { try SplitEngine.make(title: "x", total: 10, date: D(2026, 1, 1), paidBy: a, participants: [a, b], mode: .percentage, percentages: [a: 60, b: 30]) }
            t.throwsError(.invalidPercentages) { try SplitEngine.make(title: "x", total: 10, date: D(2026, 1, 1), paidBy: a, participants: [a, b], mode: .percentage, percentages: [a: 100]) }
            t.throwsError(.invalidPercentages) { try SplitEngine.make(title: "x", total: 10, date: D(2026, 1, 1), paidBy: a, participants: [a, b], mode: .percentage, percentages: [a: 110, b: -10]) }
        },
        TestCase("divisão: validações de participantes e valor") { t in
            t.throwsError(.noParticipants) { try SplitEngine.make(title: "x", total: 10, date: D(2026, 1, 1), paidBy: a, participants: [], mode: .equal) }
            t.throwsError(.invalidAmount) { try SplitEngine.make(title: "x", total: 0, date: D(2026, 1, 1), paidBy: a, participants: [a], mode: .equal) }
            let dup = try SplitEngine.make(title: "x", total: 10, date: D(2026, 1, 1), paidBy: a, participants: [a, a, b], mode: .equal)
            t.equal(dup.shares.count, 2, "participante repetido conta uma vez")
        },
        TestCase("saldos: quem pagou recebe a parte dos outros") { t in
            let s = try SplitEngine.make(title: "Mercado", total: 300, date: D(2026, 10, 1), paidBy: a, participants: [a, b, c], mode: .equal)
            let bal = SettlementEngine.balances(splits: [s], settlements: [])
            t.equal(bal[a], 200); t.equal(bal[b], -100); t.equal(bal[c], -100)
            t.equal(bal.values.reduce(Decimal(0), +), 0)
        },
        TestCase("pagador fora da divisão (pagou pelos outros) recebe tudo") { t in
            let s = try SplitEngine.make(title: "Presente", total: 90, date: D(2026, 10, 1), paidBy: a, participants: [b, c], mode: .equal)
            let bal = SettlementEngine.balances(splits: [s], settlements: [])
            t.equal(bal[a], 90); t.equal(bal[b], -45); t.equal(bal[c], -45)
        },
        TestCase("acerto: minimiza transferências (cadeia A deve B, B deve C vira A paga C)") { t in
            let s1 = try SplitEngine.make(title: "1", total: 20, date: D(2026, 10, 1), paidBy: b, participants: [a, b], mode: .equal)   // A deve 10 a B
            let s2 = try SplitEngine.make(title: "2", total: 20, date: D(2026, 10, 2), paidBy: c, participants: [b, c], mode: .equal)   // B deve 10 a C
            let plan = SettlementEngine.plan(splits: [s1, s2], settlements: [])
            t.equal(plan.count, 1)
            t.equal(plan.first?.from, a); t.equal(plan.first?.to, c); t.equal(plan.first?.amount, 10)
        },
        TestCase("acerto: n pessoas resultam em no máximo n-1 transferências e zeram os saldos") { t in
            let s1 = try SplitEngine.make(title: "1", total: 400, date: D(2026, 10, 1), paidBy: a, participants: [a, b, c, d], mode: .equal)
            let s2 = try SplitEngine.make(title: "2", total: 90, date: D(2026, 10, 2), paidBy: b, participants: [a, b, c], mode: .equal)
            let s3 = try SplitEngine.make(title: "3", total: dec("33.35"), date: D(2026, 10, 3), paidBy: d, participants: [a, b, c, d], mode: .equal)
            let plan = SettlementEngine.plan(splits: [s1, s2, s3], settlements: [])
            t.check(plan.count <= 3, "no máximo 3 transferências, obteve \(plan.count)")
            var bal = SettlementEngine.balances(splits: [s1, s2, s3], settlements: [])
            for p in plan { bal[p.from, default: 0] += p.amount; bal[p.to, default: 0] -= p.amount }
            t.check(bal.values.allSatisfy { $0 == 0 }, "saldos zerados: \(bal)")
            t.check(plan.allSatisfy { $0.amount > 0 && $0.from != $0.to })
        },
        TestCase("acerto parcial: pagamento registrado reduz o que falta") { t in
            let s = try SplitEngine.make(title: "Viagem", total: 300, date: D(2026, 10, 1), paidBy: a, participants: [a, b, c], mode: .equal)
            let paid = SplitSettlement(fromMemberId: b, toMemberId: a, amount: 100, date: D(2026, 10, 5))
            let plan = SettlementEngine.plan(splits: [s], settlements: [paid])
            t.equal(plan.count, 1); t.equal(plan[0].from, c); t.equal(plan[0].to, a); t.equal(plan[0].amount, 100)
            let half = SplitSettlement(fromMemberId: c, toMemberId: a, amount: 40, date: D(2026, 10, 6))
            t.equal(SettlementEngine.plan(splits: [s], settlements: [paid, half]).first?.amount, 60)
            let both = SettlementEngine.plan(splits: [s], settlements: [paid, SplitSettlement(fromMemberId: c, toMemberId: a, amount: 100, date: D(2026, 10, 6))])
            t.equal(both.count, 0, "tudo quitado")
        },
        TestCase("registrar acerto cria o SplitSettlement") { t in
            let tr = SettlementTransfer(from: b, to: a, amount: 25)
            let st = SettlementEngine.settle(tr, on: D(2026, 10, 7))
            t.equal(st.fromMemberId, b); t.equal(st.toMemberId, a); t.equal(st.amount, 25); t.equal(ymd(st.date), "2026-10-07")
        },
        TestCase("sem divisões não há o que acertar") { t in
            t.equal(SettlementEngine.plan(splits: [], settlements: []).count, 0)
        },
    ]
}
