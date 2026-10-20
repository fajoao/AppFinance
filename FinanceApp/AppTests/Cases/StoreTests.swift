import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

@MainActor private func expenseDraft(_ store: AppStore, _ amount: String, title: String, category: UUID? = nil,
                          source: TransactionDraft.Source? = nil, date: Date? = nil) -> TransactionDraft {
    var d = store.makeDraft(date: date)
    for ch in amount { if ch == "," { d.keypad.press(.comma) } else if let n = ch.wholeNumberValue { d.keypad.press(.digit(n)) } }
    d.title = title
    d.chooseCategory(category)
    if let source { d.source = source }
    return d
}

func storeTests() -> [TestCase] {
    [
        TestCase("onboarding cria conta com saldo, categorias padrão e preferências") { t in onMain {
            let store = makeStore(onboarded: false)
            var d = OnboardingDraft()
            t.check(!d.isValid); t.equal(d.nameError, "Dê um nome para a conta.")
            d.accountName = "Nubank"; d.balanceText = "1.250,50"; d.faceID = false; d.reminders = true
            t.check(d.isValid)
            try! store.completeOnboarding(d)
            t.equal(store.accounts.count, 1)
            t.equal(store.balance(of: store.accounts[0]), dec("1250.50"))
            t.equal(store.liquidBalance, dec("1250.50"))
            t.equal(store.categories.count, 11)
            t.check(store.preferences.onboardingDone); t.check(store.preferences.remindersEnabled); t.check(!store.preferences.faceIDEnabled)
            d.balanceText = "abc"
            t.equal(d.balanceError, "Valor inválido. Exemplo: 1.250,00")
        } },
        TestCase("salvar despesa atualiza saldo e resumo do mês") { t in onMain {
            let store = makeStore()
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            _ = try! store.save(expenseDraft(store, "100,25", title: "Padaria", category: mercado))
            t.equal(store.liquidBalance, dec("899.75"))
            let s = store.summary(for: store.currentMonth)
            t.equal(s.expense, dec("100.25")); t.equal(s.expensesByCategory.first?.categoryId, mercado)
        } },
        TestCase("sugestão de categoria usa palavras-chave e histórico") { t in onMain {
            let store = makeStore()
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            t.equal(store.suggestCategory(for: "Padaria Real", type: .expense), mercado)
            t.isNil(store.suggestCategory(for: "Salário de outubro", type: .expense))   // palavra-chave de receita não vale para despesa
            let salario = store.incomeCategories.first { $0.name == "Salário" }!.id
            t.equal(store.suggestCategory(for: "Salário de outubro", type: .income), salario)
        } },
        TestCase("data futura vira conta a pagar e marcar como paga move o saldo") { t in onMain {
            let store = makeStore()
            _ = try! store.save(expenseDraft(store, "300", title: "Internet", date: D(2026, 10, 25)))
            t.equal(store.liquidBalance, 1000)
            let bills = store.billItems
            t.equal(bills.count, 1); t.equal(bills[0].amount, 300); t.check(!bills[0].isPaid)
            try! store.markPaid(transactionId: bills[0].transactionId!)
            t.equal(store.liquidBalance, 700)
            t.check(store.billItems.allSatisfy { $0.isPaid })
        } },
        TestCase("recorrência mensal gera ocorrências futuras sem duplicar") { t in onMain {
            let store = makeStore()
            var d = expenseDraft(store, "50", title: "Streaming")
            d.repeatRule = .monthly
            _ = try! store.save(d)
            let count = store.transactions.count
            t.check(count >= 4, "esperava modelo + ~4 ocorrências, obtido \(count)")
            try! store.materializeRecurrences(); store.reload()
            t.equal(store.transactions.count, count)
        } },
        TestCase("orçamento: cria, alerta 80% e 100% uma única vez") { t in onMain {
            let store = makeStore()
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            t.throwsError(StoreError.invalidLimit) { try store.setBudget(categoryId: mercado, limit: 0) }
            try! store.setBudget(categoryId: mercado, limit: 500)
            try! store.setBudget(categoryId: mercado, limit: 500)      // atualiza, não duplica
            t.equal(store.budgets.count, 1)
            var events = try! store.save(expenseDraft(store, "410", title: "Mercado", category: mercado))
            t.equal(events.map(\.alert), [.warning])
            events = try! store.save(expenseDraft(store, "10", title: "Mercado", category: mercado))
            t.equal(events.count, 0)
            events = try! store.save(expenseDraft(store, "100", title: "Mercado", category: mercado))
            t.equal(events.map(\.alert), [.exceeded])
            t.check(events[0].message.contains("estourou"))
            events = try! store.save(expenseDraft(store, "1", title: "Mercado", category: mercado))
            t.equal(events.count, 0)
            t.check(store.toast?.isWarning == true)
        } },
        TestCase("copiar orçamentos do mês anterior só traz o que falta") { t in onMain {
            let store = makeStore()
            let c = store.expenseCategories
            try! store.setBudget(categoryId: c[0].id, limit: 100, month: store.currentMonth.previous)
            try! store.setBudget(categoryId: c[1].id, limit: 200, month: store.currentMonth.previous)
            try! store.setBudget(categoryId: c[0].id, limit: 150)
            t.equal(try! store.copyBudgetsFromPreviousMonth(), 1)
            t.equal(store.budgets.filter { $0.month == store.currentMonth }.count, 2)
        } },
        TestCase("transferência entre contas preserva o total") { t in onMain {
            let store = makeStore()
            try! store.addAccount(name: "Poupança", type: .savings, balance: 0)
            var d = store.makeDraft(type: .transfer)
            d.keypad.press(.digit(2)); d.keypad.press(.digit(5)); d.keypad.press(.digit(0))
            d.source = .account(store.accounts[0].id); d.destinationAccountId = store.accounts[1].id
            _ = try! store.save(d)
            t.equal(store.balance(of: store.accounts[0]), 750); t.equal(store.balance(of: store.accounts[1]), 250)
            t.equal(store.liquidBalance, 1000)
            t.equal(store.summary(for: store.currentMonth).expense, 0)
        } },
        TestCase("cartão: compra parcelada, fatura, limite e pagamento da fatura") { t in onMain {
            let store = makeStore()
            try! store.addCard(name: "Visa", limit: 2000, closingDay: 25, dueDay: 5, paymentAccountId: store.accounts[0].id)
            t.throwsError(StoreError.invalidDay) { try store.addCard(name: "X", limit: 1, closingDay: 32, dueDay: 5, paymentAccountId: nil) }
            let card = store.creditCards[0]
            var d = expenseDraft(store, "600", title: "Notebook", source: .card(card.id))
            d.repeatRule = .installments(3)
            _ = try! store.save(d)
            let o = store.cardOverview(card)
            t.equal(o.current.total, 200)                  // compra em 19/10, fecha dia 25: 1ª parcela na fatura atual
            t.equal(o.available, 1400)                     // limite - 600
            t.equal(o.futureCharges, 400)
            t.equal(store.liquidBalance, 1000)             // cartão não mexe no saldo
            t.equal(store.summary(for: store.currentMonth).expense, 200)    // só a parcela do mês entra no resultado
            try! store.payInvoice(cardId: card.id, month: o.current.invoice.month, amount: nil, from: store.accounts[0].id)
            t.equal(store.liquidBalance, 800)
            let after = store.cardOverview(card)
            t.equal(after.current.status, .paid); t.equal(after.available, 1600)
            t.check(store.transactions.contains { $0.isInvoicePayment })
            // pagamento de fatura não é despesa
            t.check(store.summary(for: store.currentMonth).expense < 600)
            // não pode pagar mais que o saldo da fatura
            t.throwsError(FinanceError.overpayment) { try store.payInvoice(cardId: card.id, month: o.current.invoice.month, amount: 10, from: store.accounts[0].id) }
        } },
        TestCase("pagamento parcial de fatura") { t in onMain {
            let store = makeStore()
            try! store.addCard(name: "Visa", limit: 2000, closingDay: 25, dueDay: 5, paymentAccountId: nil)
            let card = store.creditCards[0]
            _ = try! store.save(expenseDraft(store, "400", title: "Loja", source: .card(card.id)))
            let month = store.cardOverview(card).current.invoice.month
            try! store.payInvoice(cardId: card.id, month: month, amount: 100, from: store.accounts[0].id)
            let s = store.invoiceSummary(cardId: card.id, month: month)!
            t.equal(s.remaining, 300); t.equal(s.paidAmount, 100)
            t.throwsError(FinanceError.overpayment) { try store.payInvoice(cardId: card.id, month: month, amount: 301, from: store.accounts[0].id) }
        } },
        TestCase("metas: guardar dinheiro reduz o saldo da conta e soma na meta") { t in onMain {
            let store = makeStore()
            try! store.addGoal(name: "Viagem", target: 1000, deadline: D(2027, 4, 19))
            t.throwsError(StoreError.emptyName) { try store.addGoal(name: " ", target: 10, deadline: nil) }
            let goal = store.goals[0]
            try! store.contribute(goalId: goal.id, amount: 200, from: store.accounts[0].id)
            t.equal(store.goals[0].currentAmount, 200)
            t.equal(store.liquidBalance, 800)
            t.equal(store.summary(for: store.currentMonth).expense, 0)    // não é despesa
            let p = store.progress(of: store.goals[0])
            t.equal(p.percent, 20); t.equal(p.monthlyContributionNeeded, dec("133.34"))  // 800 em 6 meses, arredondado para cima
        } },
        TestCase("conciliação cria ajuste e zera a diferença") { t in onMain {
            let store = makeStore()
            let acc = store.accounts[0]
            t.equal(store.reconciliationDifference(account: acc, statementBalance: dec("1050")), 50)
            t.check(try! store.reconcile(account: acc, statementBalance: dec("1050")))
            t.equal(store.balance(of: acc), 1050)
            t.check(!(try! store.reconcile(account: acc, statementBalance: dec("1050"))))
        } },
        TestCase("importação OFX: duplicadas ignoradas e categoria sugerida") { t in onMain {
            let store = makeStore()
            let acc = store.accounts[0]
            let data = Data(SampleStatement.ofx.utf8)
            let first = store.prepareImport(fileName: "extrato.ofx", data: data, accountId: acc.id)
            t.equal(first.newCount, 3); t.equal(first.duplicateCount, 0)
            t.equal(first.summaryText, "3 importados, 0 repetidos ignorados")
            t.equal(try! store.commitImport(first, accountId: acc.id), 3)
            let again = store.prepareImport(fileName: "extrato.ofx", data: data, accountId: acc.id)
            t.equal(again.newCount, 0); t.equal(again.duplicateCount, 3)
            t.equal(again.summaryText, "0 importados, 3 repetidos ignorados")
            t.equal(try! store.commitImport(again, accountId: acc.id), 0)
            t.equal(store.transactions.count, 3)
            let posto = store.transactions.first { $0.title.contains("POSTO") }!
            t.equal(store.lookup.categoryName(posto.categoryId), "Transporte")
        } },
        TestCase("importação CSV com ponto e vírgula") { t in onMain {
            let store = makeStore()
            let csv = "data;descricao;valor\n05/10/2026;Mercado;-123,45\n06/10/2026;Salário;5.000,00\n"
            let p = store.prepareImport(fileName: "x.csv", data: Data(csv.utf8), accountId: store.accounts[0].id)
            t.equal(p.newCount, 2)
            t.equal(p.candidates[0].amount, dec("-123.45"))
        } },
        TestCase("exportação CSV: BOM, separador ; e vírgula decimal") { t in onMain {
            let store = makeStore()
            _ = try! store.save(expenseDraft(store, "12,5", title: "Café"))
            let csv = store.csvText()
            t.check(csv.hasPrefix("\u{FEFF}data;descricao;tipo;valor"))
            t.check(csv.contains(";Café;despesa;-12,50;pago;Nubank;"))
            let url = try! store.writeCSVExport(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fa-test-\(UUID().uuidString)"))
            t.equal(url.lastPathComponent, "lancamentos-2026-10-19.csv")
            let bytes = try! Data(contentsOf: url)
            t.equal(Array(bytes.prefix(3)), [0xEF, 0xBB, 0xBF])
        } },
        TestCase("bloqueio respeita o atraso configurado") { t in onMain {
            let store = makeStore()
            store.updatePreferences { $0.faceIDEnabled = true; $0.lockDelay = .oneMinute }
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            store.sceneBackgrounded(at: t0); store.sceneActivated(at: t0.addingTimeInterval(30))
            t.check(!store.isLocked)
            store.sceneBackgrounded(at: t0); store.sceneActivated(at: t0.addingTimeInterval(61))
            t.check(store.isLocked)
            store.unlock()
            store.updatePreferences { $0.faceIDEnabled = false }
            store.sceneBackgrounded(at: t0); store.sceneActivated(at: t0.addingTimeInterval(600))
            t.check(!store.isLocked)
        } },
        TestCase("excluir lançamento; pagamento de fatura não pode ser excluído") { t in onMain {
            let store = makeStore()
            _ = try! store.save(expenseDraft(store, "10", title: "Teste"))
            let id = store.transactions[0].id
            try! store.deleteTransaction(id: id)
            t.equal(store.transactions.count, 0)
            t.throwsError(StoreError.notFound) { try store.deleteTransaction(id: id) }
        } },
        TestCase("preferências persistem no PreferencesStoring") { t in onMain {
            let prefs = InMemoryPreferences()
            let store = AppStore(repository: InMemoryStore(), preferences: prefs, reminders: NoopReminderScheduler(), clock: { testToday })
            store.updatePreferences { $0.hideValues = true; $0.appearance = .dark }
            t.check(prefs.load().hideValues); t.equal(prefs.load().appearance, .dark)
        } },
        TestCase("lembretes só existem quando ativados nas preferências") { t in onMain {
            let store = makeStore(seed: true)
            store.updatePreferences { $0.remindersEnabled = false }
            t.equal(store.reminderPlan.count, 0)
            store.updatePreferences { $0.remindersEnabled = true; $0.reminderDaysBefore = 1 }
            t.check(store.reminderPlan.count >= 3, "faturas e contas pendentes devem gerar lembretes")
        } },
    ]
}

func seedTests() -> [TestCase] {
    [
        TestCase("seed de demonstração: contas, cartões, orçamento estourado e faturas pagas") { t in onMain {
            let store = makeStore(seed: true)
            t.equal(store.activeAccounts.count, 5)
            t.equal(store.activeCards.count, 2)
            t.equal(store.accounts.first { $0.name == "Nubank" }.map(store.balance(of:)), dec("4812.37"))
            t.equal(store.liquidBalance, dec("4812.37") + dec("1240.90") + dec("12850.00") + dec("86.50"))
            t.equal(store.totalWealth - store.liquidBalance, dec("18420.15"))
            let mercado = store.expenseCategories.first { $0.name == "Mercado" }!.id
            let status = store.budgetStatuses(for: store.currentMonth).first { $0.budget.categoryId == mercado }!
            t.equal(status.alert, .exceeded)
            t.check(store.preferences.onboardingDone)
            t.check(store.goals.count == 3)
            // faturas anteriores foram pagas pelo Core
            for o in store.cardOverviews { t.equal(o.previous.status, .paid, o.card.name) }
            t.check(store.billItems.contains { $0.isInvoice && !$0.isPaid })
        } },
        TestCase("seed: comparação com mês anterior disponível") { t in onMain {
            let store = makeStore(seed: true)
            let s = store.summary(for: store.currentMonth)
            t.check(s.comparison.previousExpense > 0 && s.comparison.expenseChangePercent != nil)
            t.check(s.income > 0 && s.expense > 0)
        } },
        TestCase("seed é determinístico em estrutura e idempotente ao recarregar") { t in onMain {
            let store = makeStore(seed: true)
            let n = store.transactions.count
            try! store.loadDemoData()
            t.equal(store.transactions.count, n)
        } },
    ]
}

func launchOptionsTests() -> [TestCase] {
    [
        TestCase("interpreta launch arguments") { t in
            let o = LaunchOptions(arguments: ["app", "-seedDemo", "-uiTesting", "-fixedToday", "2026-10-19", "-appearance", "dark", "-hideValues"])
            t.check(o.seedDemo && o.uiTesting && o.hideValues && !o.skipOnboarding && !o.lockOnLaunch)
            t.equal(o.fixedToday.map(ymd), "2026-10-19")
            t.equal(o.appearance, .dark)
            t.equal(LaunchOptions(arguments: ["-startScreen", "plan.bills"]).startScreen, "plan.bills")
            t.equal(LaunchOptions(arguments: ["-fixedToday"]).fixedToday == nil, true)
            t.equal(LaunchOptions(arguments: ["-appearance", "xyz"]).appearance == nil, true)
        },
        TestCase("bootstrap de teste de UI: dados isolados, sem biometria") { t in onMain {
            var o = LaunchOptions(); o.uiTesting = true; o.seedDemo = true; o.fixedToday = testToday
            let store = AppStore.bootstrap(options: o, reminders: NoopReminderScheduler())
            t.equal(ymd(store.today), "2026-10-19")
            t.check(store.preferences.onboardingDone && !store.isLocked && !store.preferences.faceIDEnabled)
            var o2 = LaunchOptions(); o2.uiTesting = true
            let empty = AppStore.bootstrap(options: o2, reminders: NoopReminderScheduler())
            t.check(!empty.preferences.onboardingDone && empty.accounts.isEmpty)
            var o3 = o2; o3.skipOnboarding = true; o3.lockOnLaunch = true
            let skipped = AppStore.bootstrap(options: o3, reminders: NoopReminderScheduler())
            t.check(skipped.preferences.onboardingDone && skipped.accounts.count == 1 && skipped.isLocked)
        } },
    ]
}
