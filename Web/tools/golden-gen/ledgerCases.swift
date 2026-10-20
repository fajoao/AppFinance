import Foundation

func ledgerCases() {
    // ---- Saldos ----
    let accounts = [acct(1, "Corrente", initial: "1000"), acct(2, "Poupança", .savings, initial: "500.50"), acct(3, "Antiga", initial: "10", archived: true)]
    let txs = [
        tx(1, .income, "3000", d(2026, 10, 5), "Salário", account: 1),
        tx(2, .expense, "250.30", d(2026, 10, 6), "Mercado", account: 1),
        tx(3, .transfer, "400", d(2026, 10, 7), "p/ poupança", account: 1, dest: 2),
        tx(4, .expense, "100", d(2026, 10, 20), "Futura", status: .pending, account: 1),
        tx(5, .expense, "80", d(2026, 10, 8), "Cartão", account: nil, card: 9),
        tx(6, .income, "50", d(2026, 11, 1), "Futuro pago", account: 2),
        tx(7, .expense, "-30", d(2026, 10, 9), "Estorno", account: 1),
    ]
    for (asOf, pending) in [(nil as Date?, false), (d(2026, 10, 7), false), (nil, true), (d(2026, 10, 6), true), (d(2026, 12, 31), false)] {
        let bal = accounts.map { S(BalanceEngine.balance(of: $0, transactions: txs, asOf: asOf, includePending: pending)) }
        let total = S(BalanceEngine.totalBalance(accounts: accounts, transactions: txs, asOf: asOf, includePending: pending))
        let invest = S(BalanceEngine.totalBalance(accounts: accounts, transactions: txs, asOf: asOf, includePending: pending, types: [.savings]))
        add("balance.compute", "balance asOf=\(asOf.map { iso($0) } ?? "nil") pending=\(pending)",
            input: ["accounts": ents(accounts), "transactions": ents(txs), "asOf": isoN(asOf), "includePending": pending],
            expected: ["balances": bal, "total": total, "savingsOnly": invest] as J)
    }
    let recon = BalanceEngine.reconciliationAdjustment(account: accounts[0], statementBalance: dec("4000"), transactions: txs, date: d(2026, 10, 31))
    add("balance.reconcile", "reconciliation adjustment", input: ["account": ent(accounts[0]), "transactions": ents(txs), "statement": "4000", "date": "2026-10-31"],
        expected: ["diff": S(BalanceEngine.reconciliationDifference(account: accounts[0], statementBalance: dec("4000"), transactions: txs, asOf: d(2026, 10, 31))),
                   "type": recon.map { $0.type.rawValue } ?? "none", "amount": recon.map { S($0.amount) } ?? "0"] as J)

    // ---- Parcelamento ----
    for (total, count, date, card) in [("100.01", 10, d(2026, 1, 31), false), ("1000", 3, d(2026, 8, 15), false), ("100.01", 10, d(2026, 1, 31), true),
                                       ("59.9", 12, d(2026, 10, 30), true), ("0.10", 3, d(2026, 5, 31), false), ("1", 1, d(2026, 5, 1), false)] {
        var t = tx(1, .expense, total, date, "Geladeira", status: .paid, account: card ? nil : 1, cat: 4, card: card ? 7 : nil)
        t.status = .paid
        let items = try! InstallmentEngine.makeInstallments(from: t, count: count)
        let out: [J] = items.map { ["amount": S($0.amount), "date": iso($0.date), "title": $0.title, "status": $0.status.rawValue,
                                      "number": $0.installment!.number, "total": $0.installment!.total] }
        add("installments.make", "installments \(total) in \(count) card=\(card)", input: ["template": ent(t), "count": count], expected: out)
    }
    // exclusão em grupo
    do {
        let t = tx(1, .expense, "300", d(2026, 3, 10), "TV", account: 1)
        let items = try! InstallmentEngine.makeInstallments(from: t, count: 4)
        let others = [tx(50, .expense, "10", d(2026, 3, 10), "Outra", account: 1)]
        let all = items + others
        for scope in InstallmentScope.allCases {
            let ids = InstallmentEngine.idsToDelete(items[1], scope: scope, in: all)
            let idxs = ids.map { id in items.firstIndex { $0.id == id }! }
            add("installments.delete", "delete scope \(scope.rawValue)", input: ["transactions": ents(all), "targetIndex": 1, "scope": scope.rawValue], expected: idxs)
        }
    }

    // ---- Recorrência ----
    func ruleJ(_ r: RecurrenceRule) -> Any { ent(r) }
    let rules: [(String, Date, RecurrenceRule, Date, Date)] = [
        ("mensal dia 31", d(2026, 1, 31), RecurrenceRule(frequency: .monthly), d(2026, 1, 1), d(2026, 12, 31)),
        ("mensal dia 31 a cada 2", d(2026, 1, 31), RecurrenceRule(frequency: .monthly, interval: 2), d(2026, 1, 1), d(2027, 3, 31)),
        ("mensal dia 30", d(2026, 1, 30), RecurrenceRule(frequency: .monthly), d(2026, 1, 1), d(2026, 4, 30)),
        ("semanal", d(2026, 10, 1), RecurrenceRule(frequency: .weekly), d(2026, 10, 10), d(2026, 11, 20)),
        ("semanal a cada 2", d(2026, 10, 1), RecurrenceRule(frequency: .weekly, interval: 2), d(2026, 10, 1), d(2026, 12, 1)),
        ("anual 29/fev", d(2024, 2, 29), RecurrenceRule(frequency: .yearly), d(2024, 1, 1), d(2029, 12, 31)),
        ("max 5", d(2026, 1, 15), RecurrenceRule(frequency: .monthly, maxOccurrences: 5), d(2026, 1, 1), d(2030, 1, 1)),
        ("endDate", d(2026, 1, 15), RecurrenceRule(frequency: .monthly, endDate: d(2026, 6, 15)), d(2026, 1, 1), d(2030, 1, 1)),
        ("endDate dia anterior", d(2026, 1, 15), RecurrenceRule(frequency: .monthly, endDate: d(2026, 6, 14)), d(2026, 1, 1), d(2030, 1, 1)),
        ("janela no meio", d(2026, 1, 31), RecurrenceRule(frequency: .monthly), d(2026, 3, 1), d(2026, 5, 31)),
        ("interval 0", d(2026, 1, 31), RecurrenceRule(frequency: .monthly, interval: 0), d(2026, 1, 1), d(2026, 3, 31)),
    ]
    for (name, start, rule, from, to) in rules {
        add("recurrence.occurrences", "occurrences \(name)", input: ["start": iso(start), "rule": ruleJ(rule), "from": iso(from), "to": iso(to)],
            expected: RecurrenceEngine.occurrences(start: start, rule: rule, from: from, to: to).map(iso))
    }
    do {
        let tpl = tx(1, .expense, "99.90", d(2026, 1, 31), "Assinatura", status: .paid, account: 1, recurrence: RecurrenceRule(frequency: .monthly))
        let existing = [tx(2, .expense, "99.90", d(2026, 3, 31), "Assinatura", status: .paid, account: 1, parent: tpl.id)]
        let gen = RecurrenceEngine.generate(from: tpl, from: d(2026, 1, 1), to: d(2026, 6, 30), existing: existing)
        add("recurrence.generate", "generate with existing", input: ["template": ent(tpl), "from": "2026-01-01", "to": "2026-06-30", "existing": ents(existing)],
            expected: gen.map { ["date": iso($0.date), "status": $0.status.rawValue, "title": $0.title, "amount": S($0.amount), "parentIsTemplate": $0.recurrenceParentId == tpl.id] as J })
    }
}
