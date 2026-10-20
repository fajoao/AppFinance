import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

private final class DoneBox: @unchecked Sendable { var done = false }

private func awaitMain(_ op: @escaping @MainActor @Sendable () async -> Void) {
    let box = DoneBox()
    Task { @MainActor in await op(); box.done = true }
    let deadline = Date().addingTimeInterval(10)
    while !box.done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
}

private let nfceKey = "35261011222333000181650010000123451876543210"

func phase3Tests() -> [TestCase] {
    [
        TestCase("Open Finance e launch option nascem desligados; preferências antigas continuam válidas") { t in
            t.check(!AppPreferences().openFinanceEnabled); t.isNil(AppPreferences().openFinanceConsentAt)
            let old = #"{"onboardingDone":true,"syncEnabled":false}"#
            let p = try JSONDecoder().decode(AppPreferences.self, from: Data(old.utf8))
            t.check(!p.openFinanceEnabled)
            t.check(!LaunchOptions(arguments: []).mockOpenFinance)
            t.check(LaunchOptions(arguments: ["-mockOpenFinance", "-startScreen", "insights"]).mockOpenFinance)
        },
        TestCase("rascunho: QR de NFC-e pré-preenche valor, data, título, nota e externalId, e salva com o externalId") { t in try onMain {
            let store = makeStore()
            let url = "https://x.sefaz.gov.br/q?p=\(nfceKey)|2|1|15|152.90|dg|1|H"
            guard let prefill = store.interpretScan(url).prefill else { t.fail("sem prefill"); return }
            var d = store.makeDraft(applying: prefill)
            t.equal(d.amount, dec("152.90")); t.equal(ymd(d.date), "2026-10-15"); t.equal(d.title, "Compra (NFC-e SP)")
            t.check(d.note.contains("11.222.333/0001-81")); t.equal(d.externalId, "nfce:" + nfceKey)
            t.check(!store.isAlreadyRecorded(externalId: d.externalId))
            _ = try store.save(d)
            t.equal(store.transactions.filter { $0.externalId == "nfce:" + nfceKey }.count, 1)
            t.check(store.isAlreadyRecorded(externalId: "nfce:" + nfceKey), "a segunda leitura é detectada")
            d.title = ""; t.equal(d.effectiveTitle, "Despesa")
        } },
        TestCase("rascunho: PIX recebido vira receita; data absurda e valor zero são ignorados") { t in onMain {
            let store = makeStore()
            let pix = ReceiptPrefill(type: .income, amount: dec("2350.00"), date: D(2026, 10, 12), title: "João", note: nil, externalId: "pix:E1")
            let d = store.makeDraft(applying: pix)
            t.equal(d.type, .income); t.equal(d.amount, dec("2350")); t.equal(ymd(d.date), "2026-10-12")
            let odd = store.makeDraft(applying: ReceiptPrefill(type: .expense, amount: 0, date: D(2031, 1, 1), title: "X"))
            t.equal(ymd(odd.date), "2026-10-19", "data a mais de 400 dias é ignorada"); t.equal(odd.amount, 0)
        } },
        TestCase("rascunho: cupom lido por texto sugere categoria pelo histórico") { t in onMain {
            let store = makeStore(seed: true)
            let text = "SUPERMERCADO BOM PREÇO LTDA\nCNPJ: 11.222.333/0001-81\nVALOR TOTAL R$ 60,00\nEmissão: 18/10/2026"
            let out = store.interpretScan(text)
            guard case .receipt(let r) = out else { t.fail("esperava receipt"); return }
            t.equal(r.amount, 60)
            let d = store.makeDraft(applying: out.prefill!)
            t.equal(d.amount, 60); t.equal(ymd(d.date), "2026-10-18")
        } },
        TestCase("insights na store: relatório com dados de demonstração é determinístico e explicável") { t in onMain {
            let store = makeStore(seed: true)
            let a = store.insightsReport(), b = store.insightsReport()
            t.equal(a, b)
            t.check(a.insights.allSatisfy { !$0.explanation.isEmpty })
            t.equal(a.forecast30.startingBalance, store.liquidBalance)
            let empty = makeStore().insightsReport()
            t.check(!empty.hasEnoughHistory)
        } },
        TestCase("Apple Watch: despesa ditada vira lançamento na conta padrão, uma vez só") { t in onMain {
            let store = makeStore()
            let req = WatchQuickAddRequest(text: "gastei 45,90 no mercado", createdAt: Date())
            guard case .created(let tx) = store.addFromWatch(req) else { t.fail("created"); return }
            t.equal(tx.amount, dec("45.90")); t.equal(store.liquidBalance, dec("954.10"))
            t.equal(store.addFromWatch(req), .duplicate); t.equal(store.liquidBalance, dec("954.10"))
            t.equal(store.addFromWatch(WatchQuickAddRequest(text: "sem valor")), .invalid(WatchQuickAdd.invalidMessage))
        } },
        TestCase("Open Finance sem provedor: indisponível e com mensagem") { t in
            awaitMain {
                let store = makeStore()
                t.check(!store.openFinance.isAvailable)
                await store.openFinance.loadInstitutions()
                t.equal(store.openFinance.errorText, BankProviderError.notConfigured.message)
            }
        },
        TestCase("Open Finance com provedor fictício: conecta, importa, não duplica e revoga") { t in
            awaitMain {
                let store = makeStore()
                store.openFinance.provider = MockBankProvider(anchor: testToday)
                await store.openFinance.loadInstitutions()
                t.equal(store.openFinance.institutions.count, 2)
                await store.openFinance.connect(institutionId: "mock-azul")
                t.equal(store.openFinance.connection?.status, .active); t.equal(store.openFinance.accounts.count, 2)
                let before = store.transactions.count
                await store.openFinance.syncNow(into: store)
                t.isNil(store.openFinance.errorText)
                t.equal(store.openFinance.lastOutcome?.imported.count, 5)   // 4 do corrente + 1 da poupança
                t.equal(store.transactions.count, before + 5)
                t.check(store.accounts.contains { $0.name == "Banco Azul (fictício) · Conta corrente" })
                await store.openFinance.syncNow(into: store)
                t.equal(store.openFinance.lastOutcome?.imported.count, 0, "segunda sincronização não duplica")
                t.equal(store.transactions.count, before + 5)
                await store.openFinance.revoke()
                t.equal(store.openFinance.connection?.status, .revoked)
                await store.openFinance.syncNow(into: store)
                t.equal(store.openFinance.errorText, BankProviderError.consentRevoked.message)
                t.equal(store.transactions.count, before + 5, "dados importados continuam; nada novo entra")
            }
        },
        TestCase("consentimento do Open Finance: liga e desliga guardando a data") { t in onMain {
            let store = makeStore()
            store.setOpenFinanceEnabled(true)
            t.check(store.preferences.openFinanceEnabled); t.equal(ymd(store.preferences.openFinanceConsentAt!), "2026-10-19")
            store.setOpenFinanceEnabled(false)
            t.check(!store.preferences.openFinanceEnabled); t.isNil(store.preferences.openFinanceConsentAt)
        } },
    ]
}

func scanSummaryTests() -> [TestCase] {
    [
        TestCase("resumo da leitura: NFC-e online avisa que o valor não consta e que a consulta não existe") { t in
            let out = ScanInterpreter.interpret("https://x.gov.br/q?p=\(nfceKey)|2|1|1|H", today: testToday)
            let s = ScanSummaryBuilder.make(out, alreadyRecorded: false)
            t.equal(s.title, "Nota fiscal (NFC-e)"); t.check(s.canUse)
            t.equal(s.rows.first { $0.identifier == "scan.result.amount" }?.value, "Não consta no QR Code")
            t.equal(s.rows.first { $0.identifier == "scan.result.uf" }?.value, "SP")
            t.check(s.warnings.contains { $0.contains("SEFAZ") })
            t.check(ScanSummaryBuilder.make(out, alreadyRecorded: true).warnings.contains { $0.contains("já foi lançado") })
        },
        TestCase("resumo da leitura: boleto mostra vencimento e validade; falha não pode ser usada") { t in
            let out = ScanInterpreter.interpret("Beneficiário: Escola Aprender\n23791.23454 67890.123457 67890.123457 1 16260000015075", today: testToday)
            let s = ScanSummaryBuilder.make(out, alreadyRecorded: false)
            t.equal(s.title, "Boleto")
            t.equal(s.rows.first { $0.identifier == "scan.result.date" }?.value, "10/11/2026")
            t.check(s.rows.first { $0.identifier == "scan.result.line" }?.value.hasSuffix("(válida)") == true)
            let fail = ScanSummaryBuilder.make(ScanInterpreter.interpret("???", today: testToday), alreadyRecorded: false)
            t.check(!fail.canUse); t.equal(fail.title, "Não foi possível ler")
        },
        TestCase("valores ocultos: textos prontos do Core têm os reais mascarados") { t in
            t.equal(InsightsPresentation.maskMoney(in: "Saldo R$\u{00A0}1.234,56 em 31/10/2026."), "Saldo R$\u{00A0}•••• em 31/10/2026.")
            t.equal(InsightsPresentation.maskMoney(in: "gasta R$\u{00A0}20,00, ou -R$\u{00A0}5,00."), "gasta R$\u{00A0}••••, ou -R$\u{00A0}••••.")
            t.equal(InsightsPresentation.maskMoney(in: "10% a mais"), "10% a mais")
        },
    ]
}
