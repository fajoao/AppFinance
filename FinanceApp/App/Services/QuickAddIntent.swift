import Foundation
#if canImport(AppIntents)
import AppIntents

/// Ponte entre o App Intent (que roda no processo do app) e a store ativa. O `FinancasApp` registra a store ao iniciar;
/// se o atalho rodar antes, cai em uma store nova sobre os mesmos arquivos (o JSON é gravado de forma atômica).
@MainActor
enum AppStoreRegistry {
    static var store: AppStore?

    static func resolve() -> AppStore {
        if let store { return store }
        let created = Production.makeStore(options: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))
        store = created
        return created
    }
}

/// "Adicionar despesa" na Siri e no app Atalhos. O valor é texto (ex.: "45,90") para nunca passar por Double.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Adicionar despesa"
    static let description = IntentDescription("Registra uma despesa na sua conta principal.")
    static let openAppWhenRun = false

    @Parameter(title: "Valor", description: "Ex.: 45,90")
    var amount: String

    @Parameter(title: "Descrição", description: "Ex.: Padaria")
    var descriptionText: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Adicionar despesa de \(\.$amount) \(\.$descriptionText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStoreRegistry.resolve()
        guard !store.isLocked else { return .result(dialog: "Abra o app Finanças e desbloqueie para registrar despesas.") }
        do {
            let message = try store.quickAddExpense(title: descriptionText ?? "", amountText: amount)
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch let e as DraftError {
            return .result(dialog: IntentDialog(stringLiteral: e.message))
        } catch {
            return .result(dialog: "Não consegui registrar a despesa.")
        }
    }
}

struct FinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(), phrases: ["Adicionar despesa no \(.applicationName)", "Registrar gasto no \(.applicationName)"],
                    shortTitle: "Adicionar despesa", systemImageName: "minus.circle")
    }
}
#endif
