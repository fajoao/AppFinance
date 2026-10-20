import Foundation

private struct Fam {
    let house: Household
    let admin: FamilyMember
    let spouse: FamilyMember
    let kid: FamilyMember
}

private func family() throws -> Fam {
    let (house, admin) = FamilyEngine.createHousehold(name: "Silva", adminName: "Ana", email: "ana@example.com")
    let spouse = try FamilyEngine.addMember(to: house, name: "Bruno", role: .member, by: admin)
    var kid = try FamilyEngine.addMember(to: house, name: "Caio", role: .dependent, by: admin)
    kid = try FamilyEngine.setSpendingLimit(kid, limit: 100, by: admin)
    return Fam(house: house, admin: admin, spouse: spouse, kid: kid)
}

func familyTests() -> [TestCase] {
    return [
        TestCase("família: criação gera o primeiro admin") { t in
            let (house, admin) = FamilyEngine.createHousehold(name: " Silva ", adminName: " Ana ", email: nil)
            t.equal(house.name, "Silva"); t.equal(admin.name, "Ana"); t.equal(admin.role, .admin); t.equal(admin.householdId, house.id)
        },
        TestCase("papéis: matriz de permissões") { t in
            t.check(FamilyEngine.can(.admin, .manageMembers) && FamilyEngine.can(.admin, .manageAllowances) && FamilyEngine.can(.admin, .approveSpending))
            t.check(!FamilyEngine.can(.member, .manageMembers))
            t.check(FamilyEngine.can(.member, .approveSpending) && FamilyEngine.can(.member, .splitExpenses) && FamilyEngine.can(.member, .viewFamilyView))
            t.check(!FamilyEngine.can(.dependent, .approveSpending) && !FamilyEngine.can(.dependent, .viewFamilyView))
            t.check(!FamilyEngine.can(.dependent, .manageMembers) && !FamilyEngine.can(.dependent, .splitExpenses))
            t.check(FamilyEngine.can(.dependent, .addTransactions))
        },
        TestCase("membros: só admin adiciona; nome obrigatório; outra casa não vale") { t in
            let f = try family()
            t.throwsError(.permissionDenied) { try FamilyEngine.addMember(to: f.house, name: "X", role: .member, by: f.spouse) }
            t.throwsError(.permissionDenied) { try FamilyEngine.addMember(to: f.house, name: "X", role: .member, by: f.kid) }
            t.throwsError(.invalidState("Informe um nome.")) { try FamilyEngine.addMember(to: f.house, name: "  ", role: .member, by: f.admin) }
            let other = Household(name: "Outra")
            t.throwsError(.permissionDenied) { try FamilyEngine.addMember(to: other, name: "X", role: .member, by: f.admin) }
        },
        TestCase("limite do dependente: só admin define; só dependente tem limite") { t in
            let f = try family()
            t.equal(f.kid.monthlySpendingLimit, 100)
            t.throwsError(.permissionDenied) { try FamilyEngine.setSpendingLimit(f.kid, limit: 999, by: f.spouse) }
            t.throwsError(.invalidState("Só dependentes têm limite de gastos.")) { try FamilyEngine.setSpendingLimit(f.spouse, limit: 10, by: f.admin) }
            t.throwsError(.invalidAmount) { try FamilyEngine.setSpendingLimit(f.kid, limit: -1, by: f.admin) }
            t.isNil(try FamilyEngine.setSpendingLimit(f.kid, limit: nil, by: f.admin).monthlySpendingLimit)
        },
        TestCase("papéis: não remove nem rebaixa o último admin") { t in
            let f = try family()
            let all = [f.admin, f.spouse, f.kid]
            t.throwsError(.lastAdmin) { try FamilyEngine.validateRemoval(of: f.admin, members: all, by: f.admin) }
            t.throwsError(.lastAdmin) { try FamilyEngine.changeRole(f.admin, to: .member, members: all, by: f.admin) }
            try FamilyEngine.validateRemoval(of: f.kid, members: all, by: f.admin)
            let promoted = try FamilyEngine.changeRole(f.spouse, to: .admin, members: all, by: f.admin)
            t.equal(promoted.role, .admin)
            let two = [f.admin, promoted, f.kid]
            try FamilyEngine.validateRemoval(of: f.admin, members: two, by: promoted)
            t.throwsError(.permissionDenied) { try FamilyEngine.validateRemoval(of: f.kid, members: all, by: f.spouse) }
            let demoted = try FamilyEngine.changeRole(f.admin, to: .member, members: two, by: promoted)
            t.equal(demoted.role, .member)
        },
        TestCase("contas privadas: só o dono vê; compartilhadas aparecem para todos") { t in
            let f = try family()
            let shared = Account(name: "Conjunta", type: .checking, visibility: .shared, ownerId: f.admin.id)
            let privA = Account(name: "Pessoal Ana", type: .checking, visibility: .personal, ownerId: f.admin.id)
            let privB = Account(name: "Pessoal Bruno", type: .wallet, visibility: .personal, ownerId: f.spouse.id)
            let all = [shared, privA, privB]
            t.equal(FamilyEngine.visibleAccounts(all, viewer: f.admin.id, scope: .family).map(\.name), ["Conjunta"])
            t.equal(FamilyEngine.visibleAccounts(all, viewer: f.admin.id, scope: .member(f.admin.id)).map(\.name), ["Conjunta", "Pessoal Ana"])
            t.equal(FamilyEngine.visibleAccounts(all, viewer: f.admin.id, scope: .member(f.spouse.id)).map(\.name), ["Conjunta"], "admin não enxerga conta privada de outro")
            t.equal(FamilyEngine.visibleAccounts(all, viewer: f.spouse.id, scope: .member(f.spouse.id)).map(\.name), ["Conjunta", "Pessoal Bruno"])
        },
        TestCase("categorias privadas: visíveis só ao dono") { t in
            let f = try family()
            let shared = Category(name: "Mercado", kind: .expense)
            let mine = Category(name: "Presentes", kind: .expense, visibility: .personal, ownerId: f.admin.id)
            t.equal(FamilyEngine.visibleCategories([shared, mine], viewer: f.admin.id).map(\.name), ["Mercado", "Presentes"])
            t.equal(FamilyEngine.visibleCategories([shared, mine], viewer: f.spouse.id).map(\.name), ["Mercado"])
        },
        TestCase("visão família × individual: lançamentos filtrados por privacidade e membro") { t in
            let f = try family()
            let joint = Account(name: "Conjunta", type: .checking, visibility: .shared)
            let privA = Account(name: "Pessoal Ana", type: .checking, visibility: .personal, ownerId: f.admin.id)
            let secret = Category(name: "Surpresa", kind: .expense, visibility: .personal, ownerId: f.spouse.id)
            var t1 = tx(.expense, "100", D(2026, 10, 1), "Mercado", account: joint.id); t1.memberId = f.admin.id
            var t2 = tx(.expense, "50", D(2026, 10, 2), "Cinema", account: joint.id); t2.memberId = f.spouse.id
            var t3 = tx(.expense, "30", D(2026, 10, 3), "Salão", account: privA.id); t3.memberId = f.admin.id
            var t4 = tx(.expense, "70", D(2026, 10, 4), "Presente", account: joint.id, category: secret.id); t4.memberId = f.spouse.id
            var t5 = Transaction(type: .expense, amount: 20, date: D(2026, 10, 5), title: "Cartão", creditCardId: UUID()); t5.memberId = f.kid.id
            let txs = [t1, t2, t3, t4, t5]
            let accts = [joint, privA], cats = [secret]
            func titles(_ viewer: FamilyMember, _ scope: FamilyScope) -> [String] {
                FamilyEngine.visibleTransactions(txs, accounts: accts, categories: cats, viewer: viewer.id, scope: scope).map(\.title)
            }
            t.equal(titles(f.admin, .family), ["Mercado", "Cinema", "Cartão"], "família: só o compartilhado e não-privado")
            t.equal(titles(f.admin, .member(f.admin.id)), ["Mercado", "Salão"])
            t.equal(titles(f.spouse, .member(f.spouse.id)), ["Cinema", "Presente"], "dono vê a própria categoria privada")
            t.equal(titles(f.admin, .member(f.spouse.id)), ["Cinema"], "outros não veem a categoria privada")
            t.equal(titles(f.admin, .member(f.kid.id)), ["Cartão"])
        },
        TestCase("dependente: abaixo do limite passa; acima vira pedido de aprovação") { t in
            let f = try family()
            var spent = tx(.expense, "80", D(2026, 10, 3), "Lanche"); spent.memberId = f.kid.id
            var other = tx(.expense, "500", D(2026, 10, 3), "Do pai"); other.memberId = f.admin.id
            var lastMonth = tx(.expense, "90", D(2026, 9, 30), "Setembro"); lastMonth.memberId = f.kid.id
            let txs = [spent, other, lastMonth]
            t.equal(ApprovalEngine.spent(memberId: f.kid.id, month: YearMonth(year: 2026, month: 10), transactions: txs), 80)
            t.equal(ApprovalEngine.evaluate(member: f.kid, amount: 20, date: D(2026, 10, 10), transactions: txs), .allowed)
            t.equal(ApprovalEngine.evaluate(member: f.kid, amount: dec("20.01"), date: D(2026, 10, 10), transactions: txs),
                    .needsApproval(limit: 100, spent: 80))
            t.equal(ApprovalEngine.evaluate(member: f.spouse, amount: 9999, date: D(2026, 10, 10), transactions: txs), .allowed)
            var noLimit = f.kid; noLimit.monthlySpendingLimit = nil
            t.equal(ApprovalEngine.evaluate(member: noLimit, amount: 9999, date: D(2026, 10, 10), transactions: txs), .allowed)
        },
        TestCase("aprovação: admin/membro aprova (cria despesa), dependente não; só pendentes") { t in
            let f = try family()
            let account = UUID()
            let req = ApprovalEngine.request(member: f.kid, title: "Jogo", amount: 150, date: D(2026, 10, 12), accountId: account, categoryId: nil)
            t.equal(req.status, .pending)
            let ok = try ApprovalEngine.approve(req, by: f.admin)
            t.equal(ok.request.status, .approved); t.equal(ok.request.decidedBy, f.admin.id); t.equal(ok.request.transactionId, ok.transaction.id)
            t.equal(ok.transaction.type, .expense); t.equal(ok.transaction.amount, 150); t.equal(ok.transaction.memberId, f.kid.id)
            t.equal(ok.transaction.accountId, account); t.equal(ok.transaction.title, "Jogo")
            t.throwsError(.permissionDenied) { try ApprovalEngine.approve(req, by: f.kid) }
            t.throwsError(.invalidState("Este pedido já foi decidido.")) { try ApprovalEngine.approve(ok.request, by: f.admin) }
            let no = try ApprovalEngine.reject(req, by: f.spouse)
            t.equal(no.status, .rejected); t.equal(no.decidedBy, f.spouse.id)
            t.throwsError(.permissionDenied) { try ApprovalEngine.reject(req, by: f.kid) }
            t.equal(ApprovalEngine.pending([req, no, ok.request]).count, 1)
        },
        TestCase("mesada: meses devidos, sem pagar duas vezes, com recuperação limitada") { t in
            let f = try family()
            var al = Allowance(memberId: f.kid.id, amount: 80, dayOfMonth: 5, fromAccountId: UUID(), toAccountId: UUID(), startMonth: YearMonth(year: 2026, month: 8))
            t.equal(AllowanceEngine.dueMonths(al, asOf: D(2026, 8, 4)), [], "ainda não chegou o dia 5")
            t.equal(AllowanceEngine.dueMonths(al, asOf: D(2026, 8, 5)), [YearMonth(year: 2026, month: 8)])
            t.equal(AllowanceEngine.dueMonths(al, asOf: D(2026, 10, 19)).count, 3)
            let r = AllowanceEngine.pay(al, asOf: D(2026, 10, 19))
            t.equal(r.transactions.count, 3)
            t.equal(r.transactions.map { ymd($0.date) }, ["2026-08-05", "2026-09-05", "2026-10-05"])
            t.check(r.transactions.allSatisfy { $0.type == .transfer && $0.amount == 80 && $0.status == .paid && $0.memberId == f.kid.id })
            t.equal(r.transactions[0].accountId, al.fromAccountId); t.equal(r.transactions[0].destinationAccountId, al.toAccountId)
            t.equal(r.allowance.lastPaidMonth, YearMonth(year: 2026, month: 10))
            t.equal(AllowanceEngine.pay(r.allowance, asOf: D(2026, 10, 25)).transactions.count, 0, "idempotente")
            t.equal(AllowanceEngine.pay(r.allowance, asOf: D(2026, 11, 5)).transactions.count, 1)
            al.isActive = false
            t.equal(AllowanceEngine.pay(al, asOf: D(2026, 10, 19)).transactions.count, 0)
            var old = al; old.isActive = true; old.startMonth = YearMonth(year: 2020, month: 1)
            t.equal(AllowanceEngine.dueMonths(old, asOf: D(2026, 10, 19)).count, 12, "recupera no máximo 12 meses")
        },
        TestCase("mesada: dia 31 em mês curto cai no último dia; validação") { t in
            let al = Allowance(memberId: UUID(), amount: 50, dayOfMonth: 31, fromAccountId: UUID(), toAccountId: UUID(), startMonth: YearMonth(year: 2026, month: 2))
            let r = AllowanceEngine.pay(al, asOf: D(2026, 2, 28))
            t.equal(r.transactions.map { ymd($0.date) }, ["2026-02-28"])
            let f = try family()
            let a = UUID(), b = UUID()
            let made = try AllowanceEngine.make(for: f.kid, amount: 60, dayOfMonth: 10, from: a, to: b, startMonth: YearMonth(year: 2026, month: 10), by: f.admin)
            t.equal(made.memberId, f.kid.id)
            t.throwsError(.permissionDenied) { try AllowanceEngine.make(for: f.kid, amount: 60, dayOfMonth: 10, from: a, to: b, startMonth: YearMonth(year: 2026, month: 10), by: f.kid) }
            t.throwsError(.invalidAmount) { try AllowanceEngine.make(for: f.kid, amount: 0, dayOfMonth: 10, from: a, to: b, startMonth: YearMonth(year: 2026, month: 10), by: f.admin) }
            t.throwsError(.invalidDay) { try AllowanceEngine.make(for: f.kid, amount: 5, dayOfMonth: 32, from: a, to: b, startMonth: YearMonth(year: 2026, month: 10), by: f.admin) }
            t.throwsError(.sameAccount) { try AllowanceEngine.make(for: f.kid, amount: 5, dayOfMonth: 3, from: a, to: a, startMonth: YearMonth(year: 2026, month: 10), by: f.admin) }
            t.throwsError(.invalidState("A mesada é para dependentes.")) { try AllowanceEngine.make(for: f.spouse, amount: 5, dayOfMonth: 3, from: a, to: b, startMonth: YearMonth(year: 2026, month: 10), by: f.admin) }
        },
    ]
}
