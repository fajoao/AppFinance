import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

func allAppSuites() -> [(String, [TestCase])] {
    [
        ("MoneyDisplay", moneyDisplayTests()),
        ("AmountKeypad", keypadTests()),
        ("TransactionFilter", filterTests()),
        ("TransactionDraft", draftTests()),
        ("Bills/Lembretes", billsTests()),
        ("PayInvoice", payInvoiceTests()),
        ("Dashboard", dashboardTests()),
        ("AppStore", storeTests()),
        ("DemoSeed", seedTests()),
        ("LaunchOptions/Bootstrap", launchOptionsTests()),
        ("Fase 2: formulários e modelos", formsTests()),
        ("Fase 2: formatação", formattingTests()),
        ("Fase 2: AppStore", phase2StoreTests()),
        ("Fase 3: scan, insights, relógio, Open Finance", phase3Tests()),
        ("Fase 3: resumo da leitura e máscara", scanSummaryTests()),
        ("Seletor de período", periodTests()),
        ("Atualizar (refresh)", refreshTests()),
    ]
}
