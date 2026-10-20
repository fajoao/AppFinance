import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

private final class DoneBox: @unchecked Sendable { var done = false }

/// Executa uma operação assíncrona do MainActor girando o run loop (o runner roda na thread principal).
private func awaitMain(_ op: @escaping @MainActor @Sendable () async -> Void) {
    let box = DoneBox()
    Task { @MainActor in await op(); box.done = true }
    let deadline = Date().addingTimeInterval(10)
    while !box.done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
}

@MainActor private func typed(_ store: AppStore, _ amount: String, title: String, category: UUID? = nil,
                              source: TransactionDraft.Source? = nil, date: Date? = nil, type: TransactionType = .expense) -> TransactionDraft {
    var d = store.makeDraft(type: type, date: date)
    for ch in amount { if ch == "," { d.keypad.press(.comma) } else if let n = ch.wholeNumberValue { d.keypad.press(.digit(n)) } }
    d.title = title
    d.chooseCategory(category)
    if let source { d.source = source }
    return d
}

private final class RecordingPublisher: WidgetPublishing, @unchecked Sendable {
    var last: WidgetSnapshot?
    var count = 0
    func publish(_ snapshot: WidgetSnapshot) { last = snapshot; count += 1 }
}

func formsTests() -> [TestCase] {
    [
        TestCase("preferências antigas (sem campos da Fase 2) continuam válidas e o sync nasce desligado") { t in
            let old = #"{"onboardingDone":true,"hideValues":true,"faceIDEnabled":true,"reminderDaysBefore":3}"#
            let p = try JSONDecoder().decode(AppPreferences.self, from: Data(old.utf8))
            t.check(p.onboardingDone && p.hideValues && p.faceIDEnabled); t.equal(p.reminderDaysBefore, 3)
            t.check(!p.syncEnabled && !p.pinEnabled); t.isNil(p.activeMemberId); t.equal(p.viewScope, .family)
            t.check(!AppPreferences().syncEnabled, "sincronização desligada por padrão")
        },
        TestCase("dívida: validação inline e juros em % ao mês viram fração") { t in
            var d = DebtDraft()
            t.check(!d.isValid); t.equal(d.nameError, "Dê um nome para a dívida.")
            d.name = "Cartão"; d.balanceText = "2.400,00"; d.rateText = "14,5"; d.minimumText = "360"; d.dueDayText = "5"
            t.check(d.isValid)
            let debt = try d.build()
            t.equal(debt.balance, 2400); t.equal(debt.monthlyInterestRate, dec("0.145")); t.equal(debt.minimumPayment, 360); t.equal(debt.dueDay, 5)
            d.rateText = "150"; t.check(d.rateError != nil)
            d.rateText = "2"; d.minimumText = "99999"; t.equal(d.minimumError, "O mínimo não pode passar do saldo.")
            d.minimumText = "10"; d.dueDayText = "40"; t.equal(d.dueDayError, "Dia inválido. Use de 1 a 31.")
            let edit = DebtDraft(editing: debt)
            t.equal(edit.rateText, "14,5"); t.equal(edit.editingId, debt.id)
            t.equal(try edit.build(existing: debt).id, debt.id)
        },
        TestCase("meta: rascunho de criação e edição") { t in
            var g = GoalDraft(today: testToday)
            t.check(!g.isValid); g.name = "Casa"; g.targetText = "10.000,50"
            t.check(g.isValid); t.equal(g.target, dec("10000.50")); t.check(g.effectiveDeadline != nil)
            g.hasDeadline = false; t.isNil(g.effectiveDeadline)
            let goal = Goal(name: "Viagem", targetAmount: 6000, deadline: D(2027, 3, 1))
            let e = GoalDraft(editing: goal, today: testToday)
            t.equal(e.name, "Viagem"); t.equal(e.targetText, "6000,00"); t.check(e.hasDeadline)
        },
        TestCase("investimento: renda fixa usa quantidade 1; ação exige quantidade; cotação opcional") { t in
            var d = InvestmentDraft()
            d.name = "CDB"; d.assetClass = .fixedIncome; d.priceText = "5.000,00"; d.quoteText = "5.230,40"
            t.check(d.isValid)
            let cdb = try d.build(today: testToday)
            t.equal(cdb.quantity, 1); t.equal(cdb.averagePrice, 5000); t.equal(cdb.quote, dec("5230.40")); t.equal(ymd(cdb.quoteDate!), "2026-10-19")
            d.assetClass = .stock; d.name = "PETR4"; d.ticker = "petr4"
            t.equal(d.quantityError, "Informe a quantidade.")
            d.quantityText = "100"; d.priceText = "32,40"; d.quoteText = ""
            let stock = try d.build(today: testToday)
            t.equal(stock.ticker, "PETR4"); t.isNil(stock.quote); t.equal(InvestmentEngine.marketValue(stock), dec("3240.00"))
            d.quoteText = "abc"; t.equal(d.quoteError, "Cotação inválida.")
            d.assetClass = .crypto; d.quantityText = "0,0042"; d.quoteText = ""
            t.equal(try d.build(today: testToday).quantity, dec("0.0042"))
        },
        TestCase("divisão: rascunho igual e percentual com prévia") { t in
            let a = FamilyMember(householdId: UUID(), name: "Ana", role: .admin)
            let b = FamilyMember(householdId: a.householdId, name: "Bruno", role: .member)
            var d = SplitDraft(date: testToday, members: [a, b], paidBy: a.id)
            t.equal(d.titleError, "Dê um nome para a despesa."); t.equal(d.totalError, "Informe o valor.")
            d.title = "Mercado"; d.totalText = "100,01"
            t.equal(d.preview(members: [a, b]).map(\.amount), [dec("50.00"), dec("50.01")])
            d.mode = .percentage
            t.equal(d.preview(members: [a, b]).count, 0, "sem percentuais a prévia é vazia")
            d.fillEvenPercentages([a, b]); t.equal(d.percentSum([a, b]), 100)
            d.percentTexts[a.id] = "70"; d.percentTexts[b.id] = "30"
            t.equal(d.preview(members: [a, b]).map(\.amount), [dec("70.01"), dec("30.00")])
            d.participants = []; t.equal(d.participantsError, "Escolha quem divide.")
        },
        TestCase("mesada: validação do formulário") { t in
            var d = AllowanceDraft()
            t.check(!d.isValid)
            d.memberId = UUID(); d.amountText = "80"; d.dayText = "5"; d.fromAccountId = UUID(); d.toAccountId = d.fromAccountId
            t.equal(d.accountsError, "As contas devem ser diferentes.")
            d.toAccountId = UUID(); t.check(d.isValid)
            d.dayText = "0"; t.equal(d.dayError, "Dia inválido. Use de 1 a 31.")
        },
        TestCase("simulador de dívidas: comparação, recomendação, datas e série do gráfico") { t in
            let debts = [Debt(name: "Pequena e barata", balance: 1000, monthlyInterestRate: dec("0.02"), minimumPayment: 100),
                         Debt(name: "Grande e cara", balance: 8000, monthlyInterestRate: dec("0.05"), minimumPayment: 680)]
            t.equal(DebtSimulation.minimumBudget(debts), 780)
            let c = try DebtSimulation.run(debts: debts, monthlyBudget: 1500)
            t.equal(c.recommended, .avalanche); t.check(c.interestSavedByAvalanche > 0); t.check(c.isFeasible)
            t.equal(c.initialTotal, 9000)
            t.check(c.avalanche.months <= c.snowball.months + 1)
            t.equal(c.payoffDate(.avalanche, today: testToday), FinanceCalendar.addMonths(testToday, c.avalanche.months))
            let pts = c.chartPoints
            t.equal(pts.filter { $0.month == 0 }.count, 2)
            t.equal(pts.filter { $0.strategy == .avalanche }.count, c.avalanche.months + 1)
            t.equal(Set(pts.map(\.id)).count, pts.count, "ids únicos para o Charts")
            t.throwsError(FinanceError.budgetBelowMinimums(required: 780)) { try DebtSimulation.run(debts: debts, monthlyBudget: 700) }
            // quando só uma estratégia quita, ela é a recomendada (o "menos juros" da outra seria enganoso)
            let seed = [Debt(name: "Rotativo", balance: 6500, monthlyInterestRate: dec("0.145"), minimumPayment: 650),
                        Debt(name: "Empréstimo", balance: 8000, monthlyInterestRate: dec("0.032"), minimumPayment: 420),
                        Debt(name: "Notebook", balance: 3100, monthlyInterestRate: dec("0.0189"), minimumPayment: 310)]
            let hard = try DebtSimulation.run(debts: seed, monthlyBudget: 1656)
            t.check(hard.avalanche.feasible && !hard.snowball.feasible)
            t.equal(hard.recommended, .avalanche); t.equal(hard.onlyOneFeasible, .avalanche); t.check(!hard.isFeasible)
            t.isNil(c.onlyOneFeasible)
            t.equal(DebtSimulation.durationText(months: 15), "1 ano e 3 meses")
            t.equal(DebtSimulation.durationText(months: 8), "8 meses")
            t.equal(DebtSimulation.durationText(months: 24), "2 anos")
            t.equal(DebtSimulation.durationText(months: 1), "1 mês")
        },
        TestCase("fluxo de caixa: manchete e pontos do gráfico") { t in
            let ok = CashFlowEngine.project(startingBalance: 1000, from: testToday, days: 30, transactions: [])
            let s = CashFlowModel.summary(ok)
            t.check(!s.goesNegative); t.equal(s.headline, "O saldo se mantém positivo nos próximos 30 dias.")
            let bill = Transaction(type: .expense, amount: 1500, date: D(2026, 10, 25), title: "Aluguel", status: .pending, accountId: UUID())
            let bad = CashFlowEngine.project(startingBalance: 1000, from: testToday, days: 30, transactions: [bill])
            let b = CashFlowModel.summary(bad)
            t.check(b.goesNegative); t.check(b.headline.hasPrefix("Atenção")); t.equal(b.lowestBalance, -500)
            t.equal(CashFlowModel.chartPoints(bad, today: testToday).count, 31)
        },
        TestCase("períodos de relatório") { t in
            let today = testToday
            t.equal(ymd(ReportPeriod.thisMonth.range(today: today).from), "2026-10-01")
            t.equal(ymd(ReportPeriod.thisMonth.range(today: today).to), "2026-10-31")
            t.equal(ymd(ReportPeriod.lastMonth.range(today: today).to), "2026-09-30")
            t.equal(ymd(ReportPeriod.last3Months.range(today: today).from), "2026-08-01")
            t.equal(ymd(ReportPeriod.thisYear.range(today: today).from), "2026-01-01")
            t.equal(ymd(ReportPeriod.thisYear.range(today: today).to), "2026-12-31")
            t.equal(ymd(ReportPeriod.custom.range(today: today, custom: (D(2026, 2, 3), D(2026, 2, 9))).to), "2026-02-09")
        },
    ]
}

func phase2StoreTests() -> [TestCase] {
    [
        TestCase("dívidas: cadastrar, editar, simular e excluir pela store") { t in try onMain {
            let store = makeStore(seed: true)
            t.equal(store.debts.count, 3)
            var d = DebtDraft(); d.name = "Carro"; d.balanceText = "5000"; d.rateText = "1,5"; d.minimumText = "250"
            try store.saveDebt(d)
            t.equal(store.debts.count, 4); t.equal(store.totalDebt, 6500 + 8000 + 3100 + 5000)
            let c = try store.simulateDebts(monthlyBudget: DebtSimulation.minimumBudget(store.debts) + 600)
            t.check(c.isFeasible)
            var e = DebtDraft(editing: store.debts.last!); e.balanceText = "4000"
            try store.saveDebt(e)
            t.equal(store.debts.count, 4); t.equal(store.debts.last?.balance, 4000)
            try store.deleteDebt(id: store.debts.last!.id)
            t.equal(store.debts.count, 3)
            t.equal(try store.repository.all(Tombstone.self).count, 1, "exclusão rastreada para a sincronização")
        } },
        TestCase("metas: editar, histórico de aportes, projeção e desfazer aporte") { t in try onMain {
            let store = makeStore()
            try store.addGoal(name: "Viagem", target: 1200, deadline: D(2027, 4, 1))
            let goal = store.goals[0]
            let acc = store.activeAccounts[0]
            try store.contribute(goalId: goal.id, amount: 200, from: acc.id)
            try store.contribute(goalId: goal.id, amount: 100, from: acc.id)
            t.equal(store.history(of: store.goals[0]).count, 2)
            t.equal(store.goals[0].currentAmount, 300); t.equal(store.liquidBalance, 700)
            let p = store.projection(of: store.goals[0])
            t.equal(p.averageMonthlyContribution, 300); t.equal(p.monthsToComplete, 3); t.equal(p.onTrack, true)
            var g = GoalDraft(editing: store.goals[0], today: store.today)
            g.name = "Viagem ao Japão"; g.targetText = "3000,00"
            try store.updateGoal(id: goal.id, g)
            t.equal(store.goals[0].name, "Viagem ao Japão"); t.equal(store.goals[0].targetAmount, 3000); t.equal(store.goals[0].currentAmount, 300)
            t.equal(store.projection(of: store.goals[0]).onTrack, false)
            let last = store.history(of: store.goals[0]).first!
            try store.revertContribution(id: last.id)
            t.equal(store.goals[0].currentAmount, 300 - last.amount)
            t.equal(store.history(of: store.goals[0]).count, 1)
            t.equal(store.liquidBalance, 1000 - 300 + last.amount, "a saída da conta também foi desfeita")
            try store.deleteGoal(id: goal.id)
            t.equal(store.goals.count, 0); t.equal(store.goalContributions.count, 0)
        } },
        TestCase("família: criar grupo, membros, papéis e permissões") { t in try onMain {
            let store = makeStore()
            t.check(!store.hasHousehold); t.isNil(store.activeMember)
            t.throwsError(StoreError.noHousehold) { try store.addMember(name: "X", role: .member) }
            try store.createHousehold(name: "Silva", adminName: "Ana")
            t.check(store.hasHousehold); t.equal(store.activeMember?.name, "Ana"); t.equal(store.activeMember?.role, .admin)
            t.equal(store.accounts[0].ownerId, store.activeMember?.id, "contas existentes passam ao administrador")
            t.throwsError(StoreError.householdExists) { try store.createHousehold(name: "Outra", adminName: "Z") }
            let bruno = try store.addMember(name: "Bruno", role: .member)
            let caio = try store.addMember(name: "Caio", role: .dependent, monthlyLimit: 150)
            t.equal(store.members.count, 3); t.equal(store.members.last?.monthlySpendingLimit, 150)
            store.setActiveMember(bruno.id)
            t.throwsError(FinanceError.permissionDenied) { try store.addMember(name: "Y", role: .member) }
            store.setActiveMember(caio.id)
            t.check(!store.canViewFamily); t.equal(store.viewScope, .member(caio.id), "dependente só tem visão individual")
            store.setActiveMember(store.members[0].id)
            t.throwsError(FinanceError.lastAdmin) { try store.removeMember(id: store.members[0].id) }
            try store.removeMember(id: caio.id)
            t.equal(store.members.count, 2)
        } },
        TestCase("família: lançamento atribuído ao perfil ativo e visão família × individual") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let ana = store.members.first { $0.name == "Ana" }!, bruno = store.members.first { $0.name == "Bruno" }!
            let familyExpense = store.summary(for: store.currentMonth).expense
            store.setViewScope(.individual)
            let anaExpense = store.summary(for: store.currentMonth).expense
            t.check(anaExpense > 0 && anaExpense < familyExpense, "individual \(anaExpense) < família \(familyExpense)")
            t.check(store.scopedTransactions.allSatisfy { $0.memberId == ana.id || ($0.memberId == nil && store.lookup.accounts[$0.accountId ?? UUID()]?.ownerId == ana.id) })
            store.setActiveMember(bruno.id)
            let brunoExpense = store.summary(for: store.currentMonth).expense
            t.check(brunoExpense > 0 && brunoExpense != anaExpense)
            _ = try store.save(typed(store, "10", title: "Café"))
            t.equal(store.transactions.first { $0.title == "Café" }?.memberId, bruno.id)
            store.setViewScope(.family)
            t.equal(store.summary(for: store.currentMonth).expense, familyExpense + 10)
        } },
        TestCase("família: contas privadas só aparecem para o dono e fora do total da família") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let ana = store.members.first { $0.name == "Ana" }!, bruno = store.members.first { $0.name == "Bruno" }!
            store.setActiveMember(ana.id)
            t.check(store.usableAccounts.contains { $0.name == "Reserva da Ana" })
            t.check(!store.scopedAccounts.contains { $0.name == "Reserva da Ana" }, "visão família: só compartilhado")
            let familyWealth = store.totalWealth
            store.setViewScope(.individual)
            t.check(store.scopedAccounts.contains { $0.name == "Reserva da Ana" })
            t.equal(store.totalWealth, familyWealth + 2300, "individual de Ana = compartilhadas + a conta privada dela")
            store.setActiveMember(bruno.id)
            t.check(!store.usableAccounts.contains { $0.name == "Reserva da Ana" })
            t.check(!store.activeAccounts.contains { $0.name == "Reserva da Ana" })
            t.throwsError(FinanceError.permissionDenied) { try store.setAccountVisibility(id: store.accounts.first { $0.name == "Reserva da Ana" }!.id, .shared) }
        } },
        TestCase("dependente: gasto acima do limite vira pedido; responsável aprova e vira despesa") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let caio = store.members.first { $0.name == "Caio" }!, ana = store.members.first { $0.name == "Ana" }!
            let kidAccount = store.accounts.first { $0.name == "Conta do Caio" }!
            store.setActiveMember(caio.id)
            t.equal(store.pendingApprovals.count, 1, "o seed já traz um pedido pendente")
            let before = store.balance(of: kidAccount)
            // já gastou 45 de 150; 100 passa (145), 10 a mais estoura
            var d = typed(store, "100", title: "Livro", source: .account(kidAccount.id))
            guard case .saved = try store.submit(d) else { t.fail("deveria salvar"); return }
            t.equal(store.balance(of: kidAccount), before - 100)
            d = typed(store, "10", title: "Doce", source: .account(kidAccount.id))
            guard case .awaitingApproval(let req) = try store.submit(d) else { t.fail("deveria aguardar aprovação"); return }
            t.equal(req.amount, 10); t.equal(store.balance(of: kidAccount), before - 100, "saldo não muda até aprovar")
            t.throwsError(FinanceError.permissionDenied) { try store.approve(requestId: req.id) }
            store.setActiveMember(ana.id)
            try store.approve(requestId: req.id)
            t.equal(store.balance(of: kidAccount), before - 110)
            t.equal(store.transactions.first { $0.title == "Doce" }?.memberId, caio.id)
            let other = store.pendingApprovals[0]
            try store.reject(requestId: other.id)
            t.equal(store.pendingApprovals.count, 0)
        } },
        TestCase("mesada: paga uma vez por mês e é idempotente; meta de filho listada") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let caio = store.members.first { $0.name == "Caio" }!
            let kidAccount = store.accounts.first { $0.name == "Conta do Caio" }!
            let before = store.balance(of: kidAccount)
            t.equal(try store.payAllowancesDue(), 1, "dia 5 já passou em 19/10 e o mês corrente estava em aberto")
            t.equal(store.balance(of: kidAccount), before + 80)
            t.equal(try store.payAllowancesDue(), 0)
            t.equal(store.goals(for: caio.id).map(\.name), ["Bicicleta do Caio"])
            t.equal(store.goals(for: nil).count, 3)
            let transfer = store.transactions.last { $0.title.hasPrefix("Mesada") }
            t.equal(transfer?.memberId, caio.id); t.equal(transfer?.destinationAccountId, kidAccount.id)
        } },
        TestCase("divisão de despesas e acerto de contas pela store") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let ana = store.members.first { $0.name == "Ana" }!, bruno = store.members.first { $0.name == "Bruno" }!
            let caio = store.members.first { $0.name == "Caio" }!
            t.equal(store.splits.count, 1)
            t.equal(store.splitBalances[ana.id], dec("213.34")); t.equal(store.splitBalances[bruno.id], dec("-106.66"))
            let plan = store.settlementPlan
            t.equal(plan.count, 2); t.check(plan.allSatisfy { $0.to == ana.id })
            try store.settle(plan.first { $0.from == bruno.id }!)
            t.equal(store.settlementPlan.map(\.from), [caio.id])
            var d = SplitDraft(date: store.today, members: store.members, paidBy: bruno.id)
            d.title = "Mercado"; d.totalText = "90"; d.participants = [ana.id, bruno.id]
            d.createsTransaction = true; d.accountId = store.accounts[0].id
            let split = try store.addSplit(d)
            t.check(split.transactionId != nil); t.equal(store.transactions.first { $0.id == split.transactionId }?.memberId, bruno.id)
            t.equal(store.splits.count, 2)
        } },
        TestCase("editar lançamento: valor, título, categoria e conta; fatura não edita; futuro vira pendente") { t in try onMain {
            let store = makeStore()
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            _ = try store.save(typed(store, "100", title: "Padaria", category: mercado))
            let tx = store.transactions[0]
            var d = try store.draft(editing: tx.id)
            t.equal(d.amount, 100); t.equal(d.title, "Padaria"); t.check(d.isEditing); t.equal(d.saveTitle, "Salvar alterações")
            d.keypad.clear(); for n in [2, 5] { d.keypad.press(.digit(n)) }
            d.title = "Padaria Real"
            try store.update(d)
            t.equal(store.transactions.count, 1); t.equal(store.transactions[0].amount, 25); t.equal(store.transactions[0].id, tx.id)
            t.equal(store.transactions[0].title, "Padaria Real"); t.equal(store.liquidBalance, 975)
            d.date = D(2026, 10, 30)
            try store.update(d)
            t.equal(store.transactions[0].status, .pending); t.equal(store.liquidBalance, 1000)
            d.keypad.clear()
            t.equal(d.validate(), .zeroAmount)
            t.throwsError(DraftError.zeroAmount) { try store.update(d) }
        } },
        TestCase("editar parcela preserva grupo e sufixo; excluir parcelas por escopo") { t in try onMain {
            let store = makeStore()
            var d = typed(store, "300", title: "TV")
            d.repeatRule = .installments(4)
            _ = try store.save(d)
            let ordered = store.transactions.sorted { $0.date < $1.date }
            t.equal(ordered.count, 4); t.equal(store.installmentCount(of: ordered[1].id), 4)
            var e = try store.draft(editing: ordered[1].id)
            t.equal(e.title, "TV"); e.title = "TV 55"
            try store.update(e)
            let edited = store.transactions.first { $0.id == ordered[1].id }!
            t.equal(edited.title, "TV 55 (2/4)"); t.equal(edited.installment?.groupId, ordered[1].installment?.groupId)
            try store.deleteInstallments(of: ordered[2].id, scope: .thisAndFuture)
            t.equal(store.transactions.count, 2)
            try store.deleteInstallments(of: ordered[0].id, scope: .all)
            t.equal(store.transactions.count, 0)
            t.check(try store.repository.all(Tombstone.self).count == 4)
        } },
        TestCase("pagamento de fatura não pode ser editado") { t in onMain {
            let store = makeStore(seed: true)
            let payment = store.transactions.first { $0.isInvoicePayment }!
            t.throwsError(StoreError.cannotEditInvoicePayment) { _ = try store.draft(editing: payment.id) }
        } },
        TestCase("comprovante: salvar, ler, rejeitar caminho fora da pasta e limpar órfão ao excluir") { t in try onMain {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("att-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let storage = AttachmentStorage(directory: dir)
            let path = try storage.save(Data("foto".utf8))
            t.check(path.hasPrefix("Attachments/") && path.hasSuffix(".jpg")); t.equal(storage.load(path), Data("foto".utf8))
            t.isNil(storage.url(for: "../data.json")); t.isNil(storage.url(for: "Attachments/../x")); t.isNil(storage.url(for: "/etc/passwd"))
            t.isNil(storage.url(for: "Attachments/a/b.jpg"))
            let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                                 clock: { testToday }, attachments: storage)
            var o = OnboardingDraft(); o.accountName = "C"; o.balanceText = "0"; try store.completeOnboarding(o)
            var d = typed(store, "20", title: "Farmácia")
            d.attachmentPath = try store.attachImage(Data("recibo".utf8))
            _ = try store.save(d)
            let tx = store.transactions[0]
            t.equal(tx.attachmentPath, d.attachmentPath); t.equal(store.attachmentData(tx.attachmentPath), Data("recibo".utf8))
            try store.deleteTransaction(id: tx.id)
            t.check(!storage.exists(d.attachmentPath!), "arquivo órfão removido")
        } },
        TestCase("investimentos: cadastro, compra, venda, cotação, alocação e totais") { t in try onMain {
            let store = makeStore()
            var d = InvestmentDraft(); d.name = "MXRF11"; d.assetClass = .reit; d.quantityText = "100"; d.priceText = "10"
            try store.saveInvestment(d)
            d.name = "CDB"; d.assetClass = .fixedIncome; d.priceText = "1000"
            try store.saveInvestment(d)
            t.equal(store.investments.count, 2); t.equal(store.portfolio.value, 2000)
            let fii = store.investments[0]
            var buy = PositionChangeDraft(kind: .buy); buy.quantityText = "100"; buy.priceText = "12"
            try store.applyPositionChange(investmentId: fii.id, buy)
            t.equal(store.investments[0].quantity, 200); t.equal(store.investments[0].averagePrice, 11)
            try store.updateQuote(investmentId: fii.id, quoteText: "13,00")
            t.equal(store.portfolio.value, 2600 + 1000); t.equal(store.portfolio.cost, 2200 + 1000)
            var sell = PositionChangeDraft(kind: .sell); sell.quantityText = "500"; sell.priceText = "13"
            t.throwsError(FinanceError.insufficientQuantity) { try store.applyPositionChange(investmentId: fii.id, sell) }
            t.throwsError(StoreError.invalidQuote) { try store.updateQuote(investmentId: fii.id, quoteText: "xx") }
            t.equal(store.allocation.map(\.percent).reduce(0, +), 100)
            try store.deleteInvestment(id: store.investments[1].id)
            t.equal(store.investments.count, 1)
        } },
        TestCase("patrimônio líquido: ativos - passivos e evolução mensal por snapshots") { t in try onMain {
            let store = makeStore(seed: true)
            let nw = store.netWorth
            store.runPeriodicTasks()
            t.equal(nw.debts, 17600)
            t.equal(nw.assets - nw.liabilities, nw.netWorth)
            t.equal(nw.investmentsValue, dec("5230.40") + 3610 + dec("2062") + dec("1407"))
            t.check(nw.cardBalances > 0, "faturas e parcelas abertas entram como passivo")
            t.equal(store.netWorthSnapshots.count, 1, "o app registra o patrimônio do mês ao abrir")
            let first = store.netWorthSnapshots[0]
            let again = try store.recordNetWorthSnapshot()
            t.equal(again.id, first.id); t.equal(store.netWorthSnapshots.count, 1)
            _ = try store.save(typed(store, "500", title: "Extra"))
            let updated = try store.recordNetWorthSnapshot()
            t.equal(updated.id, first.id, "mesmo mês, mesmo registro"); t.equal(updated.netWorth, first.netWorth - 500)
            let series = store.netWorthEvolution(months: 6)
            t.equal(series.count, 6); t.equal(series.last?.netWorth, updated.netWorth); t.isNil(series.first?.netWorth)
        } },
        TestCase("fluxo de caixa 30/60/90 inclui pendências e faturas") { t in onMain {
            let store = makeStore(seed: true)
            let p30 = store.cashFlow(days: 30), p90 = store.cashFlow(days: 90)
            t.equal(p30.startingBalance, store.liquidBalance)
            t.equal(p30.points.count, 30); t.equal(p90.points.count, 90)
            t.check(p30.items.contains { $0.label.hasPrefix("Fatura") }); t.check(p30.totalOut > 0 && p30.totalIn > 0)
            t.check(p90.totalOut >= p30.totalOut)
        } },
        TestCase("relatórios: total do mês bate com o resumo; filtros e CSV") { t in try onMain {
            let store = makeStore(seed: true)
            let month = store.summary(for: store.currentMonth)
            let r = store.report(period: .thisMonth)
            t.equal(r.expense, month.expense); t.equal(r.income, month.income)
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            let rc = store.report(period: .thisMonth, categoryIds: [mercado])
            t.equal(rc.expense, month.expensesByCategory.first { $0.categoryId == mercado }?.amount)
            let doc = store.reportDocument(r)
            t.check(doc.csv().contains("Por categoria;Mercado;"))
            let url = try store.writeCSV(doc, baseName: "relatorio", directory: FileManager.default.temporaryDirectory.appendingPathComponent("rep-\(UUID().uuidString)"))
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let data = try Data(contentsOf: url)
            t.equal(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF]); t.check(url.lastPathComponent == "relatorio-2026-10-19.csv")
        } },
        TestCase("IR: saúde e educação do ano a partir das categorias marcadas") { t in try onMain {
            let store = makeStore(seed: true)
            let tax = store.taxSummary(year: 2026)
            t.equal(tax.healthTotal, dec("424.35"), "farmácia (mês passado), Drogasil e consulta")
            t.check(tax.educationTotal > 0); t.check(tax.totalIncome > 0)
            let saude = store.expenseCategories.first { $0.name == "Saúde" }!
            t.equal(saude.taxKind, .health)
            try store.setTaxKind(categoryId: saude.id, nil)
            t.equal(store.taxSummary(year: 2026).healthTotal, 0)
            let doc = store.taxDocument(tax)
            t.check(doc.title.contains("2026")); t.check(doc.footer.contains("não substitui"))
        } },
        TestCase("categorias: nova categoria privada some para outros perfis") { t in try onMain {
            let store = makeStore(seed: true)
            try store.loadDemoData(family: true)
            let ana = store.members.first { $0.name == "Ana" }!, bruno = store.members.first { $0.name == "Bruno" }!
            store.setActiveMember(ana.id)
            let c = try store.addCategory(name: "Presentes", kind: .expense, visibility: .personal)
            t.check(store.expenseCategories.contains { $0.id == c.id })
            store.setActiveMember(bruno.id)
            t.check(!store.expenseCategories.contains { $0.id == c.id })
        } },
        TestCase("PIN: formato, bloqueio progressivo e desbloqueio") { t in try onMain {
            let store = makeStore()
            t.throwsError(StoreError.pinInvalid) { try store.setPin("12") }
            t.throwsError(StoreError.pinInvalid) { try store.setPin("12ab") }
            t.equal(store.verifyPin("1234"), .notSet)
            try store.setPin("2468")
            t.check(store.preferences.pinEnabled); t.check(store.appLockEnabled)
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            t.equal(store.verifyPin("0000", now: t0), .wrong(remainingFreeAttempts: 4))
            for _ in 0..<3 { _ = store.verifyPin("0000", now: t0) }
            t.equal(store.verifyPin("0000", now: t0), .locked(until: t0.addingTimeInterval(30)))
            t.equal(store.verifyPin("2468", now: t0.addingTimeInterval(5)), .locked(until: t0.addingTimeInterval(30)), "bloqueado mesmo com o PIN certo")
            store.lockNow()
            t.equal(store.unlock(withPin: "2468", now: t0.addingTimeInterval(31)), .ok)
            t.check(!store.isLocked); t.equal(store.preferences.pinFailedAttempts, 0)
            t.equal(store.removePin(current: "1111", now: t0.addingTimeInterval(40)), .wrong(remainingFreeAttempts: 4))
            t.check(store.preferences.pinEnabled)
            t.equal(store.removePin(current: "2468", now: t0.addingTimeInterval(41)), .ok)
            t.check(!store.preferences.pinEnabled); t.equal(store.verifyPin("2468"), .notSet)
            t.equal(PinLock.lockoutSeconds(failedAttempts: 4), 0); t.equal(PinLock.lockoutSeconds(failedAttempts: 5), 30)
            t.equal(PinLock.lockoutSeconds(failedAttempts: 6), 60); t.equal(PinLock.lockoutSeconds(failedAttempts: 40), 900)
            let r1 = PinLock.makeRecord(pin: "1234", rounds: 10), r2 = PinLock.makeRecord(pin: "1234", rounds: 10)
            t.check(r1.hash != r2.hash, "sal diferente por registro")
            t.check(PinLock.verify(pin: "1234", record: r1) && !PinLock.verify(pin: "1235", record: r1))
        } },
        TestCase("apagar tudo remove também PIN, comprovantes e preferências da Fase 2") { t in try onMain {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let storage = AttachmentStorage(directory: dir)
            let secrets = InMemorySecrets()
            let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                                 clock: { testToday }, secrets: secrets, attachments: storage)
            var o = OnboardingDraft(); o.accountName = "C"; o.balanceText = "0"; try store.completeOnboarding(o)
            try store.setPin("2468"); store.setSyncEnabled(true)
            let path = try store.attachImage(Data("x".utf8))
            t.check(storage.exists(path)); t.check(secrets.data(for: PinLock.keychainKey) != nil)
            try store.eraseAllData()
            t.check(!storage.exists(path)); t.isNil(secrets.data(for: PinLock.keychainKey))
            t.check(!store.preferences.pinEnabled && !store.preferences.syncEnabled && !store.preferences.onboardingDone)
            t.equal(store.accounts.count, 0); t.equal(store.syncStatus, .disabled)
        } },
        TestCase("bloqueio por PIN vale mesmo sem Face ID") { t in try onMain {
            let store = makeStore()
            store.updatePreferences { $0.faceIDEnabled = false }
            try store.setPin("1357")
            let t0 = Date(timeIntervalSince1970: 5_000)
            store.sceneBackgrounded(at: t0); store.sceneActivated(at: t0.addingTimeInterval(1))
            t.check(store.isLocked)
        } },
        TestCase("atalho de voz: registra despesa na conta padrão com categoria sugerida") { t in try onMain {
            let store = makeStore()
            let msg = try store.quickAddExpense(phrase: "gastei 45,90 na padaria")
            t.equal(msg, "Despesa de R$\u{00A0}45,90 registrada em Nubank.")
            let tx = store.transactions[0]
            t.equal(tx.amount, dec("45.90")); t.equal(tx.title, "Padaria"); t.equal(store.lookup.categoryName(tx.categoryId), "Mercado")
            t.equal(store.liquidBalance, dec("954.10"))
            t.throwsError(DraftError.zeroAmount) { _ = try store.quickAddExpense(phrase: "sem valor") }
            t.throwsError(DraftError.zeroAmount) { _ = try store.quickAddExpense(title: "x", amountText: "0") }
        } },
        TestCase("widgets: cada recarga publica o resumo atualizado") { t in try onMain {
            let rec = RecordingPublisher()
            let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                                 clock: { testToday }, widgets: rec)
            var o = OnboardingDraft(); o.accountName = "C"; o.balanceText = "100"; try store.completeOnboarding(o)
            t.equal(rec.last?.balance, 100)
            _ = try store.save(typed(store, "30", title: "Padaria"))
            t.equal(rec.last?.balance, 70); t.equal(rec.last?.todaySpent, 30)
            store.updatePreferences { $0.hideValues = true }; store.reload()
            t.equal(rec.last?.hideValues, true)
        } },
        TestCase("sincronização: desligada por padrão; sem serviço informa que não está configurada") { t in onMain {
            let store = makeStore()
            t.equal(store.syncStatus, .disabled); t.check(!store.syncConfigured); t.check(!store.preferences.syncEnabled)
            awaitMain { await store.syncNow() }
            t.equal(store.syncStatus, .disabled, "desligada: não faz nada")
            store.setSyncEnabled(true)
            awaitMain { await store.syncNow() }
            t.equal(store.syncStatus, .failed(StoreError.syncUnavailable.message))
            store.setSyncEnabled(false); t.equal(store.syncStatus, .disabled)
        } },
        TestCase("sincronização: dois aparelhos pela store convergem (servidor em memória)") { t in onMain {
            let server = InMemorySyncService()
            @MainActor func device() -> AppStore {
                AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                         clock: { testToday }, syncService: server)
            }
            let a = device(), b = device()
            var o = OnboardingDraft(); o.accountName = "Conta A"; o.balanceText = "500"
            try! a.completeOnboarding(o)
            a.setSyncEnabled(true); b.setSyncEnabled(true)
            awaitMain { await a.syncNow(now: Date(timeIntervalSinceReferenceDate: 1_000)) }
            t.equal(a.syncStatus, .idle(lastSync: Date(timeIntervalSinceReferenceDate: 1_000)))
            awaitMain { await b.syncNow(now: Date(timeIntervalSinceReferenceDate: 2_000)) }
            t.equal(b.accounts.map(\.name), ["Conta A"]); t.equal(b.categories.count, 11)
            t.equal(b.preferences.syncState.lastSyncAt, Date(timeIntervalSinceReferenceDate: 2_000))
        } },
        TestCase("seed da Fase 2: dívidas, investimentos, histórico e família sem alterar o seed básico") { t in onMain {
            let basic = makeStore(seed: true)
            t.equal(basic.debts.count, 3); t.equal(basic.investments.count, 4); t.equal(basic.goalContributions.count, 9)
            t.check(!basic.hasHousehold, "o seed básico não cria família (invariantes da Fase 1)")
            let fam = makeStore(seed: true)
            try! fam.loadDemoData(family: true)
            t.equal(fam.members.map(\.name), ["Ana", "Bruno", "Caio"]); t.equal(fam.activeMember?.name, "Ana")
            t.equal(fam.household?.name, "Família Silva"); t.equal(fam.allowances.count, 1); t.equal(fam.splits.count, 1)
            t.equal(fam.totalWealth, basic.totalWealth + 155, "individual/família: privada fica de fora do consolidado")
        } },
        TestCase("launch arguments da Fase 2") { t in
            let o = LaunchOptions(arguments: ["-seedFamily", "-uiTesting"])
            t.check(o.seedFamily && o.seedDemo && o.uiTesting)
            t.check(!LaunchOptions(arguments: ["-seedDemo"]).seedFamily)
        },
    ]
}

func formattingTests() -> [TestCase] {
    [
        TestCase("formatação pt-BR de percentuais, juros e quantidades") { t in
            t.equal(Fmt.percent(dec("23"), scale: 1), "23,0%"); t.equal(Fmt.percent(dec("23.04"), scale: 1), "23,0%"); t.equal(Fmt.percent(dec("23.5"), scale: 0), "24%")
            t.equal(Fmt.percent(dec("15.5714")), "15,57%"); t.equal(Fmt.percent(20), "20,00%"); t.equal(Fmt.percent(dec("2.5")), "2,50%")
            t.equal(Fmt.percent(dec("-20")), "-20,00%"); t.equal(Fmt.signedPercent(dec("3.2")), "+3,20%"); t.equal(Fmt.signedPercent(-1), "-1,00%")
            t.equal(Fmt.monthlyRate(dec("0.145")), "14,5% ao mês"); t.equal(Fmt.monthlyRate(dec("0.02")), "2% ao mês")
            t.equal(Fmt.quantity(dec("0.0042")), "0,0042"); t.equal(Fmt.quantity(100), "100")
            t.equal(Fmt.date(D(2026, 3, 5)), "05/03/2026"); t.equal(Fmt.monthYearShort(D(2027, 10, 1)), "out. de 2027")
        },
    ]
}
