import XCTest

/// Fluxos críticos em XCUITest. Só rodam no Xcode (Simulador iOS); as Command Line Tools não trazem XCTest/Simulador.
/// Cada passo anexa uma captura de tela ao .xcresult (extraia com `scripts/extract-screenshots.sh`).
/// O app é aberto com `-uiTesting` (armazenamento temporário, sem biometria) e `-fixedToday 2026-10-19`.
final class FinanceAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        step = 0
    }

    // MARK: Helpers

    private func launch(_ extra: [String] = [], appearance: String = "light") {
        app.launchArguments = ["-uiTesting", "-fixedToday", "2026-10-19", "-appearance", appearance,
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"] + extra
        app.launch()
    }

    /// Qualquer elemento pelo accessibilityIdentifier (botão, campo, contêiner...).
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    @discardableResult
    private func waitFor(_ id: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Elemento '\(id)' não apareceu", file: file, line: line)
        return e
    }

    /// Toca no elemento. Se ele não está visível (lista longa), rola até ele e espera a rolagem assentar antes do toque:
    /// o "scroll to visible" automático do XCUITest toca no meio da animação e erra o alvo (visto no iOS 26).
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = waitFor(id, file: file, line: line)
        if !e.isHittable {
            for _ in 0..<4 where !e.isHittable { app.swipeUp(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.6)
        }
        e.tap()
    }

    private func type(_ text: String, into id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = waitFor(id, file: file, line: line)
        e.tap()
        e.typeText(text)
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 8), "Aba '\(name)' não apareceu")
        b.tap()
    }

    private func segment(_ control: String, _ title: String) {
        let seg = app.segmentedControls[control]
        XCTAssertTrue(seg.waitForExistence(timeout: 8), "Seletor '\(control)' não apareceu")
        seg.buttons[title].tap()
    }

    private func snap(_ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%02d-%@", step, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapKeys(_ keys: String) {
        for ch in keys {
            switch ch {
            case ",": tap("keypad.comma")
            case "<": tap("keypad.delete")
            default: tap("keypad.\(ch)")
            }
        }
    }

    // MARK: 1. Onboarding

    func testOnboardingCreatesFirstAccount() throws {
        launch()
        waitFor("onboarding.welcome")
        snap("onboarding-boas-vindas")
        tap("onboarding.welcome.start")

        waitFor("onboarding.account")
        // Nome é obrigatório: erro inline
        tap("onboarding.account.continue")
        waitFor("onboarding.account.name.error")
        snap("onboarding-conta-erro")

        type("Nubank", into: "onboarding.account.name")
        tap("onboarding.account.type.checking")
        type("1250,50", into: "onboarding.account.balance")
        snap("onboarding-conta-preenchida")
        // fecha o teclado antes de continuar
        app.staticTexts["Sua primeira conta"].tap()
        tap("onboarding.account.continue")

        waitFor("onboarding.security")
        snap("onboarding-seguranca")
        tap("onboarding.security.finish")

        waitFor("home.dashboard")
        let balance = waitFor("home.balance")
        XCTAssertTrue(balance.label.contains("mil duzentos e cinquenta reais"), "Saldo inicial incorreto: \(balance.label)")
        snap("inicio-apos-onboarding")
    }

    // MARK: 2. Novo lançamento

    func testNewTransactionWithCategorySuggestion() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Novo")
        waitFor("transaction.new")
        snap("novo-lancamento-vazio")

        tapKeys("45,9")
        XCTAssertTrue(waitFor("transaction.new.amount").label.contains("quarenta e cinco reais e noventa centavos"))

        type("Padaria Real", into: "transaction.new.title")
        let suggestion = waitFor("transaction.new.suggestion")
        XCTAssertTrue(suggestion.label.contains("Mercado"), "Sugestão inesperada: \(suggestion.label)")
        snap("novo-lancamento-sugestao")

        tap("transaction.new.save")
        waitFor("home.dashboard")

        tab("Lançamentos")
        waitFor("transactions.list")
        type("Padaria Real", into: "transactions.search")
        XCTAssertTrue(app.staticTexts["Padaria Real"].waitForExistence(timeout: 5)
                      || el("transactions.row").waitForExistence(timeout: 5), "Lançamento salvo não apareceu na lista")
        snap("lancamentos-busca")
    }

    /// Regressão: um gesto simultâneo no contêiner fechava o teclado assim que o campo ganhava foco (iOS 26).
    func testTextFieldKeepsFocusAndTapOutsideDismissesKeyboard() throws {
        launch(["-seedDemo"])
        tab("Novo")
        waitFor("transaction.new")
        type("Café", into: "transaction.new.title")
        XCTAssertTrue(app.keyboards.firstMatch.exists || el("transaction.new.title").value as? String == "Café", "o campo deveria manter o texto digitado")
        XCTAssertEqual(el("transaction.new.title").value as? String, "Café")
        waitFor("transaction.new.amount").tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "tocar fora deveria fechar o teclado")
        snap("teclado-fechado")
    }

    /// Regressão de crash (SIGSEGV em `AddGestureModifier` ao abrir o PIN): percorre abas, segmentos e telas de Ajustes
    /// com cada massa de dados e confirma que o app continua em primeiro plano.
    func testAllTabsAndSettingsOpenWithoutCrashing() throws {
        for seed in [["-seedDemo"], ["-seedFamily"], ["-skipOnboarding"]] {
            launch(seed)
            waitFor("home.dashboard")
            for name in ["Lançamentos", "Planejar", "Carteira", "Início"] { tab(name); XCTAssertEqual(app.state, .runningForeground, "\(seed) \(name)") }
            tab("Planejar")
            for title in ["A pagar", "Metas", "Mais", "Orçamento"] { segment("plan.segment", title); XCTAssertEqual(app.state, .runningForeground, "\(seed) \(title)") }
            tab("Carteira")
            for title in ["Cartões", "Investimentos", "Contas"] { segment("wallet.segment", title); XCTAssertEqual(app.state, .runningForeground, "\(seed) \(title)") }
            tab("Início")
            tap("home.settings"); waitFor("settings")
            tap("settings.pin.link"); waitFor("settings.pin")
            XCTAssertEqual(app.state, .runningForeground, "\(seed) PIN")
            back()
            tap("settings.openfinance.link"); waitFor("openfinance")
            XCTAssertEqual(app.state, .runningForeground, "\(seed) Open Finance")
            app.terminate()
        }
    }

    func testNewTransactionValidationAndPanels() throws {
        launch(["-seedDemo"])
        tab("Novo")
        waitFor("transaction.new")
        XCTAssertFalse(el("transaction.new.save").isEnabled, "Salvar deve ficar desabilitado sem valor")
        tapKeys("120")
        XCTAssertTrue(el("transaction.new.save").isEnabled)
        tap("transaction.new.pill.repeat")
        waitFor("transaction.new.panel.repeatRule")
        tap("transaction.new.repeat.installments")
        waitFor("transaction.new.installmentSummary")
        snap("novo-lancamento-parcelado")
        tap("transaction.new.panel.done")
        tap("transaction.new.close")
        waitFor("home.dashboard")
    }

    // MARK: 3. Pagar fatura

    func testPayCreditCardInvoice() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Carteira")
        segment("wallet.segment", "Cartões")
        waitFor("wallet.cards")
        snap("cartoes")

        tap("wallet.cards.pay.0")
        waitFor("wallet.payInvoice")
        snap("pagar-fatura")
        // mínimo mostra aviso de rotativo
        tap("wallet.payInvoice.option.minimum")
        waitFor("wallet.payInvoice.revolvingWarning")
        snap("pagar-fatura-minimo")
        tap("wallet.payInvoice.option.full")
        tap("wallet.payInvoice.confirm")

        // fatura paga: botão muda e fica desabilitado
        let pay = waitFor("wallet.cards.pay.0")
        let deadline = Date().addingTimeInterval(8)
        while pay.label != "Fatura paga", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(pay.label, "Fatura paga")
        XCTAssertFalse(pay.isEnabled)
        snap("cartoes-fatura-paga")

        // detalhe da fatura
        tap("wallet.cards.invoice.0")
        waitFor("wallet.cardInvoice")
        snap("fatura-detalhe")
    }

    // MARK: 4. Criar orçamento

    func testCreateBudgetAndGetAlert() throws {
        launch(["-skipOnboarding"])
        waitFor("home.dashboard")
        tab("Planejar")
        waitFor("plan.budget")
        snap("orcamento-vazio")

        tap("plan.budget.add.empty")
        waitFor("plan.budget.edit")
        tap("plan.budget.edit.category.Mercado")
        type("500,00", into: "plan.budget.limit")
        snap("orcamento-novo")
        app.staticTexts["Novo orçamento"].tap()
        tap("plan.budget.save")

        waitFor("plan.budget.row.Mercado")
        snap("orcamento-criado")

        // gasto de 82% dispara o alerta
        tab("Novo")
        waitFor("transaction.new")
        tapKeys("410")
        tap("transaction.new.category.Mercado")
        tap("transaction.new.save")
        let toast = waitFor("toast")
        XCTAssertTrue(toast.label.contains("82%"), "Alerta inesperado: \(toast.label)")
        snap("orcamento-alerta")
    }

    // MARK: 5. Fase 2: dívidas, edição, parcelas, família, investimentos, planejamento

    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    private func openMore(_ id: String) {
        tab("Planejar")
        segment("plan.segment", "Mais")
        waitFor("plan.more")
        tap(id)
    }

    func testDebtSimulatorComparesStrategies() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        openMore("plan.more.debts")
        waitFor("plan.debts")
        snap("dividas")
        tap("plan.debts.simulate")
        waitFor("plan.debts.simulator")
        waitFor("plan.debts.simulator.avalanche")
        waitFor("plan.debts.simulator.snowball")
        waitFor("plan.debts.simulator.chart")
        snap("simulador-dividas")
    }

    func testCreateDebtFromForm() throws {
        launch(["-skipOnboarding"])
        waitFor("home.dashboard")
        openMore("plan.more.debts")
        tap("plan.debts.add.empty")
        waitFor("plan.debts.form")
        tap("plan.debts.form.save")
        waitFor("plan.debts.form.name.error")        // validação inline
        type("Carro", into: "plan.debts.form.name")
        type("5000", into: "plan.debts.form.balance")
        type("1,5", into: "plan.debts.form.rate")
        type("250", into: "plan.debts.form.minimum")
        tap("plan.debts.form.save")
        waitFor("plan.debts.row.Carro")
        snap("divida-criada")
    }

    func testEditTransaction() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Lançamentos")
        waitFor("transactions.list")
        type("Feira livre", into: "transactions.search")
        el("transactions.row").firstMatch.tap()
        waitFor("transaction.detail")
        tap("transaction.detail.edit")
        waitFor("transaction.edit")
        snap("editar-lancamento")
        tapKeys("<<<<<")
        tapKeys("99")
        tap("transaction.new.save")
        waitFor("transaction.detail")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "99")).firstMatch.waitForExistence(timeout: 5))
        snap("lancamento-editado")
    }

    func testDeleteInstallmentGroup() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Lançamentos")
        waitFor("transactions.list")
        type("Geladeira", into: "transactions.search")
        let row = el("transactions.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Excluir…"].tap()
        snap("excluir-parcelas")
        app.buttons["Todas as parcelas"].tap()
        waitFor("transactions.clearFilters")          // lista vazia: nenhuma parcela restou
    }

    func testFamilyOverviewAndSettlement() throws {
        launch(["-seedFamily"])
        waitFor("home.dashboard")
        waitFor("home.profile")
        openMore("plan.more.family")
        waitFor("family.home")
        waitFor("family.member.Caio")
        snap("familia")
        tap("family.link.settle")
        waitFor("family.settle")
        waitFor("family.settle.balance.Ana")
        snap("acerto-de-contas")
        tap("family.split.add")
        waitFor("family.split")
        type("Pizza", into: "family.split.title")
        type("90", into: "family.split.total")
        snap("dividir-despesa")
        tap("family.split.save")
        waitFor("family.settle.split.Pizza")
    }

    func testDependentApprovalFlow() throws {
        launch(["-seedFamily"])
        waitFor("home.dashboard")
        openMore("plan.more.family")
        waitFor("family.home")
        tap("family.link.approvals")
        waitFor("family.approvals")
        snap("aprovacoes")
        tap("family.approvals.approve.Jogo de videogame")
        XCTAssertTrue(app.staticTexts["Nada para aprovar"].waitForExistence(timeout: 5))
    }

    func testInvestmentsAndNetWorth() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Carteira")
        segment("wallet.segment", "Investimentos")
        waitFor("wallet.investments")
        waitFor("wallet.investments.allocation")
        snap("investimentos")
        tap("wallet.investments.networth")
        waitFor("wallet.networth")
        snap("patrimonio")
    }

    func testCashFlowReportsAndTax() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        openMore("plan.more.cashflow")
        waitFor("plan.cashflow")
        waitFor("plan.cashflow.headline")
        segment("plan.cashflow.horizon", "90 dias")
        snap("fluxo-de-caixa")
        back()
        tap("plan.more.reports")
        waitFor("reports.main")
        waitFor("reports.exportPDF")
        snap("relatorios")
        back()
        tap("plan.more.tax")
        waitFor("reports.tax")
        waitFor("reports.tax.disclaimer")
        snap("imposto-de-renda")
    }

    func testGoalEditHistoryAndProjection() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tab("Planejar")
        segment("plan.segment", "Metas")
        waitFor("plan.goals")
        tap("plan.goals.menu.0")
        app.buttons["Histórico e projeção"].tap()
        waitFor("plan.goals.history.projection")
        snap("historico-da-meta")
        app.buttons["OK"].tap()
        tap("plan.goals.menu.0")
        app.buttons["Editar meta"].tap()
        waitFor("plan.goals.edit")
        let name = waitFor("plan.goals.new.name")
        name.tap(); name.typeText(" 2")
        tap("plan.goals.new.save")
        waitFor("plan.goals")
    }

    func testOptionalPinLocksAndUnlocks() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tap("home.settings")
        tap("settings.pin.link")
        waitFor("settings.pin")
        type("2468", into: "settings.pin.new")
        type("2468", into: "settings.pin.confirm")
        tap("settings.pin.enable")
        back()
        tap("settings.lockNow")
        waitFor("auth.lock")
        type("0000", into: "auth.lock.pin")
        tap("auth.lock.pin.submit")
        waitFor("auth.lock.pin.error")
        snap("pin-incorreto")
        type("2468", into: "auth.lock.pin")
        tap("auth.lock.pin.submit")
        waitFor("settings")
    }

    // MARK: Extras

    func testLockScreenAndUnlock() throws {
        launch(["-seedDemo", "-lockOnLaunch"])
        waitFor("auth.lock")
        snap("bloqueio")
        tap("auth.lock.biometric")   // em -uiTesting desbloqueia direto (sem prompt de biometria)
        waitFor("home.dashboard")
    }

    // MARK: Fase 3

    func testInsightsShowForecastAndExplanation() throws {
        launch(["-seedDemo"])
        waitFor("home.insights")
        tap("home.insights.seeAll")
        waitFor("insights")
        waitFor("insights.forecast")
        snap("insights")
        tap("insights.explain.forecast")
        waitFor("insights.explanation.forecast")
        snap("insights-como-calculamos")
    }

    func testInsightsEmptyStateWithoutData() throws {
        launch(["-skipOnboarding", "-startScreen", "insights"])
        waitFor("insights")
        waitFor("insights.empty")
    }

    func testScanPastedBoletoPrefillsNewTransaction() throws {
        launch(["-seedDemo", "-startScreen", "scan"])
        waitFor("scan")
        tap("scan.paste")
        type("Beneficiário: Escola Aprender\n23791.23454 67890.123457 67890.123457 1 16260000015075", into: "scan.text")
        tap("scan.interpret")
        waitFor("scan.result")
        XCTAssertEqual(el("scan.result.amount").label.contains("150,75"), true, "valor do boleto: \(el("scan.result.amount").label)")
        snap("leitura-boleto")
        tap("scan.use")
        waitFor("transaction.new")
        let spoken = waitFor("transaction.new.amount").label
        XCTAssertTrue(spoken.contains("cento e cinquenta reais e setenta e cinco centavos"), "valor do boleto no novo lançamento: \(spoken)")
        snap("novo-lancamento-preenchido")
    }

    func testScanInvalidBoletoShowsWarningAndKeepsAmountEmpty() throws {
        launch(["-seedDemo", "-startScreen", "scan"])
        waitFor("scan")
        tap("scan.paste")
        type("23791.23454 67890.123457 67890.123457 9 16260000015075", into: "scan.text")
        tap("scan.interpret")
        waitFor("scan.result.warning")
        XCTAssertFalse(el("scan.result.amount").exists, "linha digitável inválida não deve preencher o valor")
    }

    func testOpenFinanceIsOffByDefaultAndExplainsConsent() throws {
        launch(["-seedDemo", "-startScreen", "settings.openfinance"])
        waitFor("openfinance")
        waitFor("openfinance.terms")
        waitFor("openfinance.unavailable")
        XCTAssertFalse(el("openfinance.toggle").isEnabled, "sem provedor o consentimento não pode ser ligado")
        snap("open-finance-desligado")
    }

    func testOpenFinanceMockFlowImportsOnce() throws {
        launch(["-seedDemo", "-mockOpenFinance", "-startScreen", "settings.openfinance"])
        waitFor("openfinance.mockBanner")
        tap("openfinance.toggle")
        tap("openfinance.load")
        tap("openfinance.institution.mock-azul")
        waitFor("openfinance.status")
        tap("openfinance.sync")
        waitFor("openfinance.result")
        XCTAssertTrue(el("openfinance.result").label.contains("Importadas: 5"), el("openfinance.result").label)
        snap("open-finance-importado")
        tap("openfinance.sync")
        let zero = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Importadas: 0'"), object: el("openfinance.result"))
        XCTAssertEqual(XCTWaiter().wait(for: [zero], timeout: 8), .completed, "segunda importação não deve duplicar")
    }

    // MARK: 7. Seletor global de período (mês/ano)

    private func periodTitle() -> String { waitFor("period.picker").label }

    func testPeriodPickerChangesDashboardBudgetAndTransactions() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        XCTAssertTrue(periodTitle().hasPrefix("Outubro de 2026"), periodTitle())
        XCTAssertTrue(periodTitle().hasSuffix("selecionar mês"))
        XCTAssertFalse(el("period.backToToday").exists, "no mês atual não há chip de retorno")
        let octResult = waitFor("home.result").label
        snap("period-inicio-outubro")

        tap("period.prev")
        XCTAssertTrue(periodTitle().hasPrefix("Setembro de 2026"), periodTitle())
        waitFor("period.backToToday")
        let sepResult = waitFor("home.result").label
        XCTAssertNotEqual(octResult, sepResult, "o resultado do mês deve mudar com o mês visualizado")
        snap("period-inicio-setembro")

        // Orçamento: o demo só tem limites em outubro, então setembro mostra o estado vazio.
        tab("Planejar")
        waitFor("plan.budget")
        XCTAssertTrue(periodTitle().hasPrefix("Setembro de 2026"), "o mês é global entre as telas")
        waitFor("plan.budget.add.empty")
        snap("period-orcamento-setembro")

        // Lançamentos: o resumo muda e o filtro de período mostra o mês.
        tab("Lançamentos")
        waitFor("transactions.list")
        XCTAssertTrue(periodTitle().hasPrefix("Setembro de 2026"))
        let sepSummary = waitFor("transactions.summary").label
        snap("period-lancamentos-setembro")

        // A pagar usa o mesmo mês.
        tab("Planejar"); segment("plan.segment", "A pagar"); waitFor("plan.bills")
        XCTAssertTrue(periodTitle().hasPrefix("Setembro de 2026"))
        tap("period.next")
        XCTAssertTrue(periodTitle().hasPrefix("Outubro de 2026"))

        tab("Lançamentos")
        XCTAssertNotEqual(waitFor("transactions.summary").label, sepSummary)
        tap("period.prev")
        tap("period.backToToday")
        XCTAssertTrue(periodTitle().hasPrefix("Outubro de 2026"))
        XCTAssertFalse(el("period.backToToday").exists)
        tab("Planejar"); segment("plan.segment", "Orçamento")
        waitFor("plan.budget.available")
    }

    func testPeriodSheetPicksYearMonthAndToday() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        tap("period.picker")
        waitFor("period.sheet")
        XCTAssertEqual(waitFor("period.year").label, "Ano 2026")
        snap("period-sheet-claro")
        tap("period.year.prev")
        XCTAssertEqual(waitFor("period.year").label, "Ano 2025")
        tap("period.month.3")
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: el("period.sheet"))
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 6), .completed, "a sheet fecha ao escolher o mês")
        XCTAssertTrue(periodTitle().hasPrefix("Março de 2025"), periodTitle())
        // Mês sem dados: estado vazio, sem quebrar os gráficos.
        waitFor("home.month.empty")
        snap("period-inicio-mes-vazio")

        tap("period.picker")
        waitFor("period.sheet")
        tap("period.today")
        XCTAssertTrue(periodTitle().hasPrefix("Outubro de 2026"), periodTitle())
        waitFor("home.incomeExpense")
    }

    func testPeriodScreenshotsDark() throws {
        launch(["-seedDemo"], appearance: "dark")
        waitFor("home.dashboard")
        tap("period.picker"); waitFor("period.sheet"); snap("period-sheet-escuro")
        tap("period.month.9")
        XCTAssertTrue(periodTitle().hasPrefix("Setembro de 2026"))
        snap("period-inicio-setembro-escuro")
        tab("Planejar"); waitFor("plan.budget"); snap("period-orcamento-setembro-escuro")
    }

    // MARK: 8. Atualizar (botão e puxar para baixo)

    private func pullToRefresh(_ element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0)
    }

    /// O toast some em 3,5 s e o XCUITest só volta do gesto depois disso; por isso a prova é o valor de acessibilidade do botão.
    private func expectRefreshed(after before: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH 'Atualizado às' AND value != %@", before),
                                                object: el("refresh.button"))
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "a atualização não aconteceu", file: file, line: line)
    }

    func testRefreshButtonUpdatesAndReenables() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        let button = waitFor("refresh.button")
        XCTAssertEqual(button.label, "Atualizar")
        XCTAssertTrue(button.isEnabled)
        button.tap()
        let toast = waitFor("toast")
        XCTAssertEqual(toast.label, "Atualizado")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: el("refresh.button"))
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 6), .completed, "o botão volta a habilitar")
        snap("refresh-botao")
        for name in ["Lançamentos", "Planejar", "Carteira"] { tab(name); waitFor("refresh.button") }
    }

    func testPullDownRefreshesTransactionsAndHome() throws {
        launch(["-seedDemo"])
        waitFor("home.dashboard")
        let before = waitFor("refresh.button").value as? String ?? ""
        XCTAssertFalse(before.hasPrefix("Atualizado às"), "ainda não atualizou")
        let anchor = waitFor("home.balance").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        anchor.press(forDuration: 0.1, thenDragTo: anchor.withOffset(CGVector(dx: 0, dy: 420)), withVelocity: .default, thenHoldForDuration: 0)
        expectRefreshed(after: before)
        snap("refresh-puxar-inicio")
        tab("Lançamentos")
        waitFor("transactions.row")
        let beforeList = waitFor("refresh.button").value as? String ?? ""
        Thread.sleep(forTimeInterval: 1.1)   // o valor tem segundos ("Atualizado às HH:mm:ss"): garante que a segunda atualização é distinguível
        pullToRefresh(app.collectionViews.firstMatch)
        expectRefreshed(after: beforeList)
        XCTAssertTrue(el("transactions.row").exists, "a lista continua com os dados")
    }

    // MARK: 9. Puxar para atualizar sem sobreposição (rajada de capturas durante o arrasto)

    /// Arrasto lento e longo para baixo a partir de `anchor`, com capturas em rajada (~80 ms) durante e depois do gesto.
    /// Os quadros viram anexos `burst-<nome>-NN`; devolve quantos quadros foram capturados.
    @discardableResult
    private func burstPull(_ name: String, from anchor: XCUIElement, distance: CGFloat = 420) -> Int {
        let lock = NSLock()
        var frames: [XCUIScreenshot] = []
        var running = true
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            while true {
                lock.lock(); let go = running; lock.unlock()
                if !go { break }
                let shot = XCUIScreen.main.screenshot()
                lock.lock(); frames.append(shot); lock.unlock()
                Thread.sleep(forTimeInterval: 0.08)
            }
            group.leave()
        }
        let start = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: .slow, thenHoldForDuration: 1.0)
        Thread.sleep(forTimeInterval: 1.2)
        lock.lock(); running = false; lock.unlock()
        group.wait()
        // guarda no máximo 14 quadros espaçados, para o xcresult não crescer demais
        let stride = max(1, frames.count / 14)
        for (i, f) in frames.enumerated() where i % stride == 0 {
            let a = XCTAttachment(screenshot: f)
            a.name = String(format: "burst-%@-%02d", name, i)
            a.lifetime = .keepAlways
            add(a)
        }
        return frames.count
    }

    private func count(_ id: String) -> Int { app.descendants(matching: .any).matching(identifier: id).count }

    /// Puxa para atualizar e confere que o texto-âncora existe uma única vez (sem linhas duplicadas), que o seletor de
    /// mês (quando a tela tem um) não ficou sobre a âncora e que o botão voltou a habilitar. Deixa a rajada anexada.
    private func pullAndCheck(_ screen: String, anchor id: String, hasPicker: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let anchor = waitFor(id, file: file, line: line)
        let frames = burstPull(screen, from: anchor)
        XCTAssertGreaterThan(frames, 3, "rajada de capturas de \(screen)", file: file, line: line)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: el("refresh.button"))
        _ = XCTWaiter().wait(for: [enabled], timeout: 6)
        XCTAssertEqual(count(id), 1, "\(screen): âncora '\(id)' deve existir uma única vez depois de puxar", file: file, line: line)
        if hasPicker {
            XCTAssertEqual(count("period.picker"), 1, "\(screen): seletor de mês único", file: file, line: line)
            let picker = el("period.picker").frame, a = el(id).frame
            XCTAssertFalse(picker.intersects(a), "\(screen): o seletor não pode ficar sobre o texto", file: file, line: line)
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testRefreshPullKeepsEveryScreenClean() throws {
        launch(["-seedFamily"])
        waitFor("home.dashboard")
        pullAndCheck("inicio", anchor: "home.balance")
        tab("Lançamentos"); waitFor("transactions.row")
        pullAndCheck("lancamentos", anchor: "transactions.summary")
        tab("Planejar"); waitFor("plan.budget.available")
        pullAndCheck("orcamento", anchor: "plan.budget.available")
        segment("plan.segment", "A pagar"); waitFor("plan.bills")
        pullAndCheck("apagar", anchor: "plan.bills.totalPay")
        segment("plan.segment", "Metas"); waitFor("plan.goals")
        pullAndCheck("metas", anchor: "plan.goals", hasPicker: false)
        segment("plan.segment", "Mais"); waitFor("plan.more")
        pullAndCheck("mais", anchor: "plan.more", hasPicker: false)
        tap("plan.more.networth"); waitFor("wallet.networth")
        pullAndCheck("patrimonio", anchor: "wallet.networth.total", hasPicker: false)
        back()
        tap("plan.more.insights"); waitFor("insights")
        pullAndCheck("insights", anchor: "insights", hasPicker: false)
        back()
        tap("plan.more.reports"); waitFor("reports.main")
        pullAndCheck("relatorios", anchor: "reports.net")
        back()
        tap("plan.more.family"); waitFor("family.home")
        pullAndCheck("familia", anchor: "family.member.Caio", hasPicker: false)
        back()
        tab("Carteira"); waitFor("wallet.accounts")
        pullAndCheck("contas", anchor: "wallet.accounts.total", hasPicker: false)
        segment("wallet.segment", "Cartões"); waitFor("wallet.cards")
        pullAndCheck("cartoes", anchor: "wallet.cards", hasPicker: false)
        tap("wallet.cards.invoice.0"); waitFor("wallet.cardInvoice")
        pullAndCheck("fatura", anchor: "wallet.cardInvoice.total")
        back()
        segment("wallet.segment", "Investimentos"); waitFor("wallet.investments")
        pullAndCheck("investimentos", anchor: "wallet.investments.total", hasPicker: false)
    }

    /// Percorre as telas principais para gerar as capturas do critério de aceite visual
    /// (rode com o dispositivo/tamanho e o Dynamic Type desejados; veja o README).
    func testScreenshotTourLight() throws { try screenshotTour(appearance: "light") }
    func testScreenshotTourDark() throws { try screenshotTour(appearance: "dark") }

    private func screenshotTour(appearance: String) throws {
        launch(["-seedDemo"], appearance: appearance)
        waitFor("home.dashboard")
        snap("\(appearance)-inicio")
        el("home.dashboard").swipeUp()
        snap("\(appearance)-inicio-rolagem")

        tab("Lançamentos"); waitFor("transactions.list"); snap("\(appearance)-lancamentos")
        tap("transactions.filters"); waitFor("transactions.filters.sheet"); snap("\(appearance)-filtros")
        tap("transactions.filters.ok")

        tab("Novo"); waitFor("transaction.new"); tapKeys("1234,56"); snap("\(appearance)-novo-lancamento")
        tap("transaction.new.close")

        tab("Planejar")
        waitFor("plan.budget"); snap("\(appearance)-orcamento")
        segment("plan.segment", "A pagar"); waitFor("plan.bills"); snap("\(appearance)-a-pagar")
        segment("plan.segment", "Metas"); waitFor("plan.goals"); snap("\(appearance)-metas")

        tab("Carteira")
        waitFor("wallet.accounts"); snap("\(appearance)-contas")
        segment("wallet.segment", "Cartões"); waitFor("wallet.cards"); snap("\(appearance)-cartoes")

        tab("Planejar")
        segment("plan.segment", "Mais"); waitFor("plan.more"); snap("\(appearance)-mais")
        tap("plan.more.debts"); waitFor("plan.debts"); snap("\(appearance)-dividas")
        tap("plan.debts.simulate"); waitFor("plan.debts.simulator"); snap("\(appearance)-simulador")
        back(); back()
        tap("plan.more.cashflow"); waitFor("plan.cashflow"); snap("\(appearance)-fluxo-de-caixa")
        back()
        tap("plan.more.reports"); waitFor("reports.main"); snap("\(appearance)-relatorios")
        back()
        tap("plan.more.networth"); waitFor("wallet.networth"); snap("\(appearance)-patrimonio")

        tab("Carteira")
        segment("wallet.segment", "Investimentos"); waitFor("wallet.investments"); snap("\(appearance)-investimentos")

        tab("Início")
        tap("home.settings"); waitFor("settings"); snap("\(appearance)-ajustes")
        tap("settings.openfinance.link"); waitFor("openfinance"); snap("\(appearance)-open-finance")
        back(); back()

        // Fase 3: insights e leitura de nota
        tab("Início")
        el("home.dashboard").swipeUp()
        tap("home.insights.seeAll"); waitFor("insights"); snap("\(appearance)-insights")
        back()
        tab("Novo"); waitFor("transaction.new")
        tap("transaction.new.scan"); waitFor("scan"); snap("\(appearance)-ler-nota")
    }

    // MARK: 10. Cabeçalho do dia fixo na lista de Lançamentos

    /// Rola a lista devagar: o cabeçalho do dia fica fixo no topo e precisa ter fundo opaco. Anexa a rajada de quadros
    /// (`burst-rolagem-lancamentos-NN`) para conferência visual e confere que a lista segue com linhas visíveis.
    func testTransactionsStickyHeaderStaysOpaqueWhileScrolling() throws {
        launch(["-seedDemo", "-skipOnboarding"])
        waitFor("home.dashboard")
        tab("Lançamentos")
        waitFor("transactions.list")
        let row = waitFor("transactions.row")
        burstPull("rolagem-lancamentos", from: row, distance: -320)
        XCTAssertTrue(el("transactions.row").exists, "A lista ficou sem linhas depois de rolar")
    }
}
