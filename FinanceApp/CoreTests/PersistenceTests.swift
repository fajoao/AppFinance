import Foundation

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("financecore-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("data.json")
}
private func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

private func sampleData() -> (Account, Category, Transaction, CreditCard, Budget, Goal, Debt, Household, FamilyMember, Invoice, Tag) {
    let owner = UUID()
    let acc = Account(name: "Conta", type: .checking, initialBalance: dec("1234.56"), ownerId: owner,
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000.123), updatedAt: Date(timeIntervalSince1970: 1_700_000_100.5))
    let cat = Category(name: "Mercado", kind: .expense, parentId: UUID())
    let tag = Tag(name: "casa")
    var t = Transaction(type: .expense, amount: dec("100.01"), date: D(2024, 2, 29), title: "Compra", accountId: acc.id, categoryId: cat.id)
    t.installment = InstallmentInfo(number: 1, total: 10, groupId: UUID())
    t.recurrence = RecurrenceRule(frequency: .monthly, interval: 2, endDate: D(2030, 1, 1), maxOccurrences: 5)
    t.attachmentPath = "Attachments/abc.jpg"; t.tagIds = [tag.id]
    let card = CreditCard(name: "Visa", limit: dec("9999999999.99"), closingDay: 10, dueDay: 20, paymentAccountId: acc.id)
    let budget = Budget(categoryId: cat.id, month: YearMonth(year: 2025, month: 1), limit: dec("0.01"))
    let goal = Goal(name: "Viagem", targetAmount: 5000, currentAmount: dec("1000.5"), deadline: D(2026, 1, 1))
    let debt = Debt(name: "Empréstimo", balance: 1000, monthlyInterestRate: dec("0.0199"), minimumPayment: 50)
    let house = Household(name: "Silva")
    let member = FamilyMember(householdId: house.id, name: "Ana", role: .admin, email: "ana@example.com")
    let inv = Invoice(cardId: card.id, month: YearMonth(year: 2025, month: 1), closingDate: D(2025, 1, 10), dueDate: D(2025, 1, 20), paidAmount: dec("12.34"))
    return (acc, cat, t, card, budget, goal, debt, house, member, inv, tag)
}

/// Mesmas verificações de contrato para qualquer implementação de Repository.
private func contract(_ t: TestContext, _ repo: any Repository) throws {
    t.equal(try repo.all(Account.self).count, 0)
    var a = Account(name: "A", type: .wallet)
    let b = Account(name: "B", type: .savings, initialBalance: dec("10.10"))
    try repo.save(a); try repo.save(b)
    t.equal(try repo.all(Account.self).count, 2)
    t.equal(try repo.get(Account.self, id: a.id), a)
    t.isNil(try repo.get(Account.self, id: UUID()))
    // upsert
    a.name = "A2"; try repo.save(a)
    t.equal(try repo.all(Account.self).count, 2)
    t.equal(try repo.get(Account.self, id: a.id)?.name, "A2")
    // tipos isolados
    t.equal(try repo.all(Category.self).count, 0)
    try repo.saveAll([Tag(name: "x"), Tag(name: "y"), Tag(name: "z")])
    t.equal(try repo.all(Tag.self).count, 3)
    // delete
    t.equal(try repo.delete(Account.self, id: a.id), true)
    t.equal(try repo.delete(Account.self, id: a.id), false)
    t.equal(try repo.all(Account.self).map(\.id), [b.id])
    // touch
    let before = b.updatedAt
    try repo.save(touching: b, now: before.addingTimeInterval(60))
    t.equal(try repo.get(Account.self, id: b.id)?.updatedAt, before.addingTimeInterval(60))
    // snapshot / restore
    let snap = try repo.snapshot()
    try repo.delete(Account.self, id: b.id)
    t.equal(try repo.all(Account.self).count, 0)
    try repo.restore(snap)
    t.equal(try repo.all(Account.self).count, 1)
    t.equal(try repo.all(Tag.self).count, 3)
}

func persistenceTests() -> [TestCase] {
    [
        TestCase("InMemoryStore: contrato de repositório") { t in try contract(t, InMemoryStore()) },
        TestCase("JSONFileStore: contrato de repositório") { t in
            let url = tempURL(); defer { cleanup(url) }
            try contract(t, try JSONFileStore(url: url))
        },
        TestCase("InMemoryStore: todos os tipos de entidade") { t in
            let (acc, cat, tr, card, budget, goal, debt, house, member, inv, tag) = sampleData()
            let s = InMemoryStore()
            try s.save(acc); try s.save(cat); try s.save(tr); try s.save(card); try s.save(budget); try s.save(goal)
            try s.save(debt); try s.save(house); try s.save(member); try s.save(inv); try s.save(tag)
            t.equal(try s.get(Transaction.self, id: tr.id), tr); t.equal(try s.get(CreditCard.self, id: card.id), card)
            t.equal(try s.get(Budget.self, id: budget.id), budget); t.equal(try s.get(Goal.self, id: goal.id), goal)
            t.equal(try s.get(Debt.self, id: debt.id), debt); t.equal(try s.get(FamilyMember.self, id: member.id), member)
            t.equal(try s.get(Household.self, id: house.id), house); t.equal(try s.get(Invoice.self, id: inv.id), inv)
        },
        TestCase("JSONFileStore: round-trip fiel (Decimal, datas, ids, opcionais) após reabrir") { t in
            let url = tempURL(); defer { cleanup(url) }
            let (acc, cat, tr, card, budget, goal, debt, house, member, inv, tag) = sampleData()
            do {
                let s = try JSONFileStore(url: url)
                try s.save(acc); try s.save(cat); try s.save(tr); try s.save(card); try s.save(budget); try s.save(goal)
                try s.save(debt); try s.save(house); try s.save(member); try s.save(inv); try s.save(tag)
            }
            let r = try JSONFileStore(url: url)
            t.equal(try r.get(Account.self, id: acc.id), acc)
            t.equal(try r.get(Account.self, id: acc.id)?.initialBalance, dec("1234.56"))
            t.equal(try r.get(Account.self, id: acc.id)?.ownerId, acc.ownerId)
            t.equal(try r.get(Account.self, id: acc.id)?.createdAt, acc.createdAt)
            t.equal(try r.get(Transaction.self, id: tr.id), tr)
            t.equal(try r.get(Transaction.self, id: tr.id)?.amount, dec("100.01"))
            t.equal(try r.get(CreditCard.self, id: card.id)?.limit, dec("9999999999.99"))
            t.equal(try r.get(Budget.self, id: budget.id)?.limit, dec("0.01"))
            t.equal(try r.get(Debt.self, id: debt.id)?.monthlyInterestRate, dec("0.0199"))
            t.equal(try r.get(Category.self, id: cat.id), cat)
            t.equal(try r.get(Goal.self, id: goal.id), goal)
            t.equal(try r.get(Household.self, id: house.id), house)
            t.equal(try r.get(FamilyMember.self, id: member.id), member)
            t.equal(try r.get(Invoice.self, id: inv.id), inv)
            t.equal(try r.get(Tag.self, id: tag.id), tag)
        },
        TestCase("JSONFileStore: arquivo ausente começa vazio; cria diretórios; sem arquivos temporários residuais") { t in
            let url = tempURL(); defer { cleanup(url) }
            let s = try JSONFileStore(url: url)
            t.check(!FileManager.default.fileExists(atPath: url.path))
            try s.save(Tag(name: "a"))
            t.check(FileManager.default.fileExists(atPath: url.path))
            let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            t.equal(files, ["data.json"])
        },
        TestCase("JSONFileStore: arquivo corrompido lança erro e não é sobrescrito") { t in
            let url = tempURL(); defer { cleanup(url) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{ não é json".utf8).write(to: url)
            var threw = false
            do { _ = try JSONFileStore(url: url) } catch { threw = true }
            t.check(threw, "deveria lançar")
            t.equal(try Data(contentsOf: url), Data("{ não é json".utf8))
        },
        TestCase("JSONFileStore: falha de escrita reverte o estado em memória") { t in
            let url = tempURL(); defer { cleanup(url) }
            let s = try JSONFileStore(url: url)
            try s.save(Tag(name: "ok"))
            // substitui o arquivo por um diretório não vazio: a escrita atômica falha
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url.appendingPathComponent("x"), withIntermediateDirectories: true)
            var threw = false
            do { try s.save(Tag(name: "falha")) } catch { threw = true }
            t.check(threw, "deveria lançar")
            t.equal(try s.all(Tag.self).map(\.name), ["ok"])
        },
        TestCase("JSONFileStore: delete e restore persistem") { t in
            let url = tempURL(); defer { cleanup(url) }
            let s = try JSONFileStore(url: url)
            let a = Tag(name: "a"), b = Tag(name: "b")
            try s.saveAll([a, b]); try s.delete(Tag.self, id: a.id)
            t.equal(try JSONFileStore(url: url).all(Tag.self).map(\.name), ["b"])
            var snap = FinanceSnapshot(); snap.tags = [Tag(name: "novo")]
            try s.restore(snap)
            t.equal(try JSONFileStore(url: url).all(Tag.self).map(\.name), ["novo"])
        },
        TestCase("JSON legível: Decimal sem perda e chaves ordenadas") { t in
            let url = tempURL(); defer { cleanup(url) }
            let s = try JSONFileStore(url: url)
            try s.save(Account(name: "X", type: .checking, initialBalance: dec("0.1")))
            let text = try String(contentsOf: url, encoding: .utf8)
            t.check(text.contains("\"initialBalance\""), text)
            t.equal(try JSONFileStore(url: url).all(Account.self).first?.initialBalance, dec("0.1"))
        },
        TestCase("uso concorrente do InMemoryStore não perde gravações") { t in
            let s = InMemoryStore()
            DispatchQueue.concurrentPerform(iterations: 200) { _ in try? s.save(Tag(name: "t")) }
            t.equal(try s.all(Tag.self).count, 200)
        },
        TestCase("integração: fluxo completo com repositório") { t in
            let repo = InMemoryStore()
            let acc = Account(name: "Conta", type: .checking, initialBalance: 1000)
            let card = CreditCard(name: "Visa", limit: 2000, closingDay: 10, dueDay: 20, paymentAccountId: acc.id)
            try repo.save(acc); try repo.save(card)
            try repo.saveAll(try CreditCardEngine.makePurchase(card: card, title: "Geladeira", total: dec("1000.01"), date: D(2025, 1, 5), installments: 4))
            let summary = CreditCardEngine.summary(card: card, month: YearMonth(year: 2025, month: 1), transactions: try repo.all(Transaction.self), asOf: D(2025, 1, 12))
            let (inv, pay) = try CreditCardEngine.pay(summary, card: card, from: acc.id, on: D(2025, 1, 20))
            try repo.save(inv); try repo.save(pay)
            let txs = try repo.all(Transaction.self)
            t.equal(BalanceEngine.balance(of: acc, transactions: txs), dec("750"))
            t.equal(CreditCardEngine.availableLimit(card: card, transactions: txs), dec("1249.99"))
            t.equal(try repo.all(Invoice.self).first?.paidAmount, dec("250"))
        },
    ]
}
