import Foundation

// Runner: executa todas as suítes; sai com código 1 se houver falhas.
let suites: [(String, [TestCase])] = [
    ("Foundation/Money", foundationTests()),
    ("Ledger", ledgerTests()),
    ("Installments", installmentTests()),
    ("Recurrence", recurrenceTests()),
    ("CreditCard", creditCardTests()),
    ("Planning", planningTests()),
    ("Debt/Goal", debtGoalTests()),
    ("Importing", importingTests()),
    ("Export/Suggest", exportSuggestTests()),
    ("Persistence", persistenceTests()),
    ("Investimentos/Patrimônio", investmentTests()),
    ("Divisão de despesas", splittingTests()),
    ("Família", familyTests()),
    ("Relatórios/IR", reportTests()),
    ("Sincronização", syncTests()),
    ("Widgets/Atalhos", widgetTests()),
    ("Fase 2: metas/dívidas/parcelas", goalsDebtsInstallmentTests()),
    ("Fase 3: insights", insightsTests()),
    ("Fase 3: Open Finance", openFinanceTests()),
    ("Fase 3: Apple Watch", watchTests()),
    ("Fase 3: NFC-e", nfceTests()),
    ("Fase 3: boleto", boletoTests()),
    ("Fase 3: OCR (texto de comprovantes)", receiptTextTests()),
    ("Fase 3: leitura de QR/texto", scanInterpreterTests()),
]

var passed = 0, failed = 0, assertions = 0
for (suite, tests) in suites {
    print("== \(suite)")
    for test in tests {
        let t = TestContext()
        do { try test.body(t) } catch { t.fail("erro inesperado: \(error)") }
        assertions += t.assertions
        if t.failures.isEmpty { passed += 1; print("  ok   \(test.name)") }
        else {
            failed += 1
            print("  FAIL \(test.name)")
            for f in t.failures { print("       - \(f)") }
        }
    }
}
print("\nResultado: \(passed) passaram, \(failed) falharam (\(assertions) asserções)")
exit(failed == 0 ? 0 : 1)
