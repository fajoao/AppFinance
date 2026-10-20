import Foundation

func ledgerTests() -> [TestCase] {
    [
        TestCase("saldo: inicial + receitas - despesas") { t in
            let acc = Account(name: "Nubank", type: .checking, initialBalance: dec("1000.50"))
            let txs = [tx(.income, "500", D(2025, 1, 5), account: acc.id), tx(.expense, "200.25", D(2025, 1, 6), account: acc.id)]
            t.equal(BalanceEngine.balance(of: acc, transactions: txs), dec("1300.25"))
        },
        TestCase("saldo ignora pendentes por padrão e inclui com flag") { t in
            let acc = Account(name: "C", type: .checking, initialBalance: 100)
            let txs = [tx(.expense, "30", D(2025, 1, 5), status: .pending, account: acc.id)]
            t.equal(BalanceEngine.balance(of: acc, transactions: txs), 100)
            t.equal(BalanceEngine.balance(of: acc, transactions: txs, includePending: true), 70)
        },
        TestCase("saldo ignora lançamentos de outras contas") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 10), b = Account(name: "B", type: .wallet)
            let txs = [tx(.income, "5", D(2025, 1, 1), account: b.id)]
            t.equal(BalanceEngine.balance(of: a, transactions: txs), 10)
            t.equal(BalanceEngine.balance(of: b, transactions: txs), 5)
        },
        TestCase("saldo asOf (inclusivo, por dia) e virada de ano") { t in
            let a = Account(name: "A", type: .checking)
            let txs = [tx(.income, "100", D(2024, 12, 31), account: a.id), tx(.income, "50", D(2025, 1, 1), account: a.id)]
            t.equal(BalanceEngine.balance(of: a, transactions: txs, asOf: D(2024, 12, 31)), 100)
            t.equal(BalanceEngine.balance(of: a, transactions: txs, asOf: D(2025, 1, 1)), 150)
            t.equal(BalanceEngine.balance(of: a, transactions: txs, asOf: D(2024, 12, 30)), 0)
        },
        TestCase("saldo pode ficar negativo; centavos exatos") { t in
            let a = Account(name: "A", type: .checking, initialBalance: dec("0.10"))
            let txs = [tx(.expense, "0.30", D(2025, 1, 1), account: a.id)]
            t.equal(BalanceEngine.balance(of: a, transactions: txs), dec("-0.20"))
        },
        TestCase("despesa negativa (estorno) aumenta o saldo; receita negativa reduz") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 100)
            let txs = [tx(.expense, "-25", D(2025, 1, 1), account: a.id), tx(.income, "-5", D(2025, 1, 2), account: a.id)]
            t.equal(BalanceEngine.balance(of: a, transactions: txs), 120)
        },
        TestCase("transferência move entre contas e preserva o total") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 1000), b = Account(name: "B", type: .savings, initialBalance: 50)
            let tr = try BalanceEngine.makeTransfer(from: a.id, to: b.id, amount: dec("333.33"), date: D(2025, 3, 1))
            let all = [tr]
            t.equal(BalanceEngine.balance(of: a, transactions: all), dec("666.67"))
            t.equal(BalanceEngine.balance(of: b, transactions: all), dec("383.33"))
            t.equal(BalanceEngine.totalBalance(accounts: [a, b], transactions: all), 1050)
            t.equal(tr.type, .transfer)
        },
        TestCase("transferência inválida") { t in
            let a = UUID()
            t.throwsError(.sameAccount) { try BalanceEngine.makeTransfer(from: a, to: a, amount: 10, date: D(2025, 1, 1)) }
            t.throwsError(.invalidAmount) { try BalanceEngine.makeTransfer(from: a, to: UUID(), amount: 0, date: D(2025, 1, 1)) }
            t.throwsError(.invalidAmount) { try BalanceEngine.makeTransfer(from: a, to: UUID(), amount: -5, date: D(2025, 1, 1)) }
        },
        TestCase("transferência pendente não move saldo até ser paga") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 100), b = Account(name: "B", type: .wallet)
            let tr = try BalanceEngine.makeTransfer(from: a.id, to: b.id, amount: 40, date: D(2025, 1, 1), status: .pending)
            t.equal(BalanceEngine.balance(of: a, transactions: [tr]), 100)
            t.equal(BalanceEngine.balance(of: b, transactions: [tr], includePending: true), 40)
        },
        TestCase("compras de cartão não afetam saldo de conta; pagamento de fatura sim") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 500)
            let card = CreditCard(name: "Visa", limit: 1000, closingDay: 5, dueDay: 12)
            let purchase = Transaction(type: .expense, amount: 100, date: D(2025, 1, 10), title: "Loja", creditCardId: card.id)
            let payment = Transaction(type: .transfer, amount: 100, date: D(2025, 2, 12), title: "Fatura", accountId: a.id, creditCardId: card.id, invoiceId: UUID())
            t.equal(BalanceEngine.balance(of: a, transactions: [purchase]), 500)
            t.equal(BalanceEngine.balance(of: a, transactions: [purchase, payment]), 400)
        },
        TestCase("saldo total ignora arquivadas e filtra tipos") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 100)
            let b = Account(name: "B", type: .investment, initialBalance: 900)
            let c = Account(name: "C", type: .wallet, initialBalance: 5, isArchived: true)
            t.equal(BalanceEngine.totalBalance(accounts: [a, b, c], transactions: []), 1000)
            t.equal(BalanceEngine.totalBalance(accounts: [a, b, c], transactions: [], types: [.checking, .wallet]), 100)
        },
        TestCase("conciliação: diferença e ajuste") { t in
            let a = Account(name: "A", type: .checking, initialBalance: 100)
            let txs = [tx(.expense, "30", D(2025, 1, 5), account: a.id)]
            t.equal(BalanceEngine.reconciliationDifference(account: a, statementBalance: dec("75.50"), transactions: txs), dec("5.50"))
            let adj = BalanceEngine.reconciliationAdjustment(account: a, statementBalance: dec("75.50"), transactions: txs, date: D(2025, 1, 31))!
            t.equal(adj.type, .income); t.equal(adj.amount, dec("5.50"))
            t.equal(BalanceEngine.balance(of: a, transactions: txs + [adj]), dec("75.50"))
            let adj2 = BalanceEngine.reconciliationAdjustment(account: a, statementBalance: 60, transactions: txs, date: D(2025, 1, 31))!
            t.equal(adj2.type, .expense); t.equal(adj2.amount, 10)
            t.isNil(BalanceEngine.reconciliationAdjustment(account: a, statementBalance: 70, transactions: txs, date: D(2025, 1, 31)))
        },
        TestCase("Transaction.signedAmount") { t in
            t.equal(tx(.income, "10", D(2025, 1, 1)).signedAmount, 10)
            t.equal(tx(.expense, "10", D(2025, 1, 1)).signedAmount, -10)
            t.equal(tx(.transfer, "10", D(2025, 1, 1)).signedAmount, 0)
            t.equal(tx(.expense, "-10", D(2025, 1, 1)).signedAmount, 10)
        },
    ]
}

func installmentTests() -> [TestCase] {
    [
        TestCase("10x de 100,01: 9 x 10,00 + 10,01") { t in
            let tpl = tx(.expense, "100.01", D(2025, 1, 15), "TV")
            let parts = try InstallmentEngine.makeInstallments(from: tpl, count: 10)
            t.equal(parts.count, 10)
            t.equal(parts.map(\.amount).reduce(0, +), dec("100.01"))
            t.equal(parts[0].amount, dec("10.00")); t.equal(parts[9].amount, dec("10.01"))
            t.equal(parts[0].installment?.label, "1/10"); t.equal(parts[9].installment?.label, "10/10")
            t.equal(Set(parts.compactMap { $0.installment?.groupId }).count, 1)
            t.equal(Set(parts.map(\.id)).count, 10)
            t.equal(parts[0].title, "TV (1/10)")
        },
        TestCase("parcelas: datas mensais, virada de ano") { t in
            let parts = try InstallmentEngine.makeInstallments(from: tx(.expense, "300", D(2024, 11, 20)), count: 4)
            t.equal(ymds(parts.map(\.date)), ["2024-11-20", "2024-12-20", "2025-01-20", "2025-02-20"])
        },
        TestCase("parcelas: dia 31 e fevereiro bissexto sem deriva") { t in
            let parts = try InstallmentEngine.makeInstallments(from: tx(.expense, "400", D(2024, 1, 31)), count: 4)
            t.equal(ymds(parts.map(\.date)), ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"])
            let p2 = try InstallmentEngine.makeInstallments(from: tx(.expense, "200", D(2023, 1, 31)), count: 2)
            t.equal(ymds(p2.map(\.date)), ["2023-01-31", "2023-02-28"])
        },
        TestCase("parcelas: status futuro pendente em conta; cartão mantém") { t in
            let parts = try InstallmentEngine.makeInstallments(from: tx(.expense, "30", D(2025, 1, 1)), count: 3)
            t.equal(parts.map(\.status), [.paid, .pending, .pending])
            var tpl = tx(.expense, "30", D(2025, 1, 1)); tpl.creditCardId = UUID()
            let c = try InstallmentEngine.makeInstallments(from: tpl, count: 3)
            t.equal(c.map(\.status), [.paid, .paid, .paid])
        },
        TestCase("parcelas: 1x, 0x e negativo") { t in
            let one = try InstallmentEngine.makeInstallments(from: tx(.expense, "50", D(2025, 1, 1)), count: 1)
            t.equal(one.count, 1); t.equal(one[0].amount, 50)
            t.throwsError(.invalidInstallmentCount) { try InstallmentEngine.makeInstallments(from: tx(.expense, "50", D(2025, 1, 1)), count: 0) }
            t.throwsError(.invalidInstallmentCount) { try InstallmentEngine.split(total: 10, count: -2) }
            let neg = try InstallmentEngine.makeInstallments(from: tx(.expense, "-100", D(2025, 1, 1)), count: 3)
            t.equal(neg.map(\.amount), [dec("-33.33"), dec("-33.33"), dec("-33.34")])
        },
        TestCase("split de valores variados soma sempre o total") { t in
            for total in ["1000", "999.99", "0.07", "12345.67"] {
                for n in [2, 3, 6, 7, 12, 18, 24] {
                    let p = try InstallmentEngine.split(total: dec(total), count: n)
                    t.equal(p.reduce(0, +), dec(total))
                    t.check(p.dropLast().allSatisfy { $0 == p[0] }, "parcelas iguais exceto a última")
                    t.check(p.last! >= p[0], "última >= demais")
                }
            }
        },
    ]
}

func recurrenceTests() -> [TestCase] {
    [
        TestCase("mensal: ocorrências no intervalo, inclusive nas pontas") { t in
            let r = RecurrenceRule(frequency: .monthly)
            let o = RecurrenceEngine.occurrences(start: D(2025, 1, 10), rule: r, from: D(2025, 1, 10), to: D(2025, 4, 10))
            t.equal(ymds(o), ["2025-01-10", "2025-02-10", "2025-03-10", "2025-04-10"])
            let o2 = RecurrenceEngine.occurrences(start: D(2025, 1, 10), rule: r, from: D(2025, 2, 11), to: D(2025, 4, 9))
            t.equal(ymds(o2), ["2025-03-10"])
        },
        TestCase("mensal: dia 31 ajusta para o fim do mês e volta, ano bissexto") { t in
            let r = RecurrenceRule(frequency: .monthly)
            let o = RecurrenceEngine.occurrences(start: D(2024, 1, 31), rule: r, from: D(2024, 1, 1), to: D(2024, 6, 30))
            t.equal(ymds(o), ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30", "2024-05-31", "2024-06-30"])
            let o2 = RecurrenceEngine.occurrences(start: D(2023, 1, 31), rule: r, from: D(2023, 1, 1), to: D(2023, 3, 31))
            t.equal(ymds(o2), ["2023-01-31", "2023-02-28", "2023-03-31"])
        },
        TestCase("mensal: dia 30 e 29 em fevereiro") { t in
            let r = RecurrenceRule(frequency: .monthly)
            t.equal(ymds(RecurrenceEngine.occurrences(start: D(2025, 1, 30), rule: r, from: D(2025, 2, 1), to: D(2025, 3, 31))), ["2025-02-28", "2025-03-30"])
            t.equal(ymds(RecurrenceEngine.occurrences(start: D(2024, 1, 29), rule: r, from: D(2024, 2, 1), to: D(2024, 2, 29))), ["2024-02-29"])
        },
        TestCase("mensal: virada de ano e intervalo de 2 meses") { t in
            let r = RecurrenceRule(frequency: .monthly, interval: 2)
            let o = RecurrenceEngine.occurrences(start: D(2024, 11, 5), rule: r, from: D(2024, 11, 1), to: D(2025, 5, 31))
            t.equal(ymds(o), ["2024-11-05", "2025-01-05", "2025-03-05", "2025-05-05"])
        },
        TestCase("semanal: cruza mês/ano e intervalo quinzenal") { t in
            let r = RecurrenceRule(frequency: .weekly)
            let o = RecurrenceEngine.occurrences(start: D(2024, 12, 23), rule: r, from: D(2024, 12, 1), to: D(2025, 1, 14))
            t.equal(ymds(o), ["2024-12-23", "2024-12-30", "2025-01-06", "2025-01-13"])
            let q = RecurrenceRule(frequency: .weekly, interval: 2)
            t.equal(ymds(RecurrenceEngine.occurrences(start: D(2025, 2, 20), rule: q, from: D(2025, 2, 1), to: D(2025, 3, 31))), ["2025-02-20", "2025-03-06", "2025-03-20"])
        },
        TestCase("anual: 29/fev vira 28/fev em ano comum e volta em bissexto") { t in
            let r = RecurrenceRule(frequency: .yearly)
            let o = RecurrenceEngine.occurrences(start: D(2024, 2, 29), rule: r, from: D(2024, 1, 1), to: D(2028, 12, 31))
            t.equal(ymds(o), ["2024-02-29", "2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29"])
        },
        TestCase("limites: endDate e maxOccurrences") { t in
            let end = RecurrenceRule(frequency: .monthly, endDate: D(2025, 3, 10))
            t.equal(RecurrenceEngine.occurrences(start: D(2025, 1, 10), rule: end, from: D(2025, 1, 1), to: D(2026, 1, 1)).count, 3)
            let maxn = RecurrenceRule(frequency: .monthly, maxOccurrences: 2)
            t.equal(RecurrenceEngine.occurrences(start: D(2025, 1, 10), rule: maxn, from: D(2025, 1, 1), to: D(2026, 1, 1)).count, 2)
            // maxOccurrences conta desde o início, mesmo com a janela começando depois
            t.equal(ymds(RecurrenceEngine.occurrences(start: D(2025, 1, 10), rule: maxn, from: D(2025, 2, 1), to: D(2026, 1, 1))), ["2025-02-10"])
        },
        TestCase("intervalo antes do início ou vazio") { t in
            let r = RecurrenceRule(frequency: .monthly)
            t.equal(RecurrenceEngine.occurrences(start: D(2025, 6, 1), rule: r, from: D(2025, 1, 1), to: D(2025, 5, 31)).count, 0)
            t.equal(RecurrenceEngine.occurrences(start: D(2025, 1, 1), rule: r, from: D(2025, 5, 1), to: D(2025, 4, 1)).count, 0)
            let bad = RecurrenceRule(frequency: .monthly, interval: 0)  // interval inválido vira 1
            t.equal(RecurrenceEngine.occurrences(start: D(2025, 1, 1), rule: bad, from: D(2025, 1, 1), to: D(2025, 3, 1)).count, 3)
        },
        TestCase("generate: cria pendentes ligados ao modelo, sem duplicar 1ª nem existentes") { t in
            var tpl = tx(.expense, "1200", D(2025, 1, 5), "Aluguel")
            tpl.recurrence = RecurrenceRule(frequency: .monthly)
            let first = RecurrenceEngine.generate(from: tpl, from: D(2025, 1, 1), to: D(2025, 3, 31))
            t.equal(ymds(first.map(\.date)), ["2025-02-05", "2025-03-05"])
            t.check(first.allSatisfy { $0.status == .pending && $0.recurrenceParentId == tpl.id && $0.recurrence == nil && $0.amount == 1200 })
            t.equal(Set(first.map(\.id)).count, 2)
            let again = RecurrenceEngine.generate(from: tpl, from: D(2025, 1, 1), to: D(2025, 4, 30), existing: first)
            t.equal(ymds(again.map(\.date)), ["2025-04-05"])
            var noRule = tpl; noRule.recurrence = nil
            t.equal(RecurrenceEngine.generate(from: noRule, from: D(2025, 1, 1), to: D(2025, 12, 31)).count, 0)
        },
    ]
}
