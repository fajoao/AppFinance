import Foundation

/// Launch arguments reconhecidos pelo app (usados por testes de UI e capturas de tela).
///
/// - `-seedDemo`: carrega os dados de demonstração e pula o onboarding.
/// - `-seedFamily`: como `-seedDemo`, mais o grupo familiar de demonstração (Ana, Bruno e Caio).
/// - `-uiTesting`: usa um armazenamento temporário e vazio, preferências em memória e não pede biometria.
/// - `-skipOnboarding`: marca o onboarding como concluído (sem dados, a menos que `-seedDemo`).
/// - `-fixedToday yyyy-MM-dd`: congela "hoje" (capturas determinísticas).
/// - `-appearance light|dark|system`: força a aparência.
/// - `-hideValues`: inicia com valores ocultos.
/// - `-lockOnLaunch`: inicia bloqueado (para testar `auth.lock`).
/// - `-mockOpenFinance`: provedor de Open Finance fictício (nunca em produção).
/// - `-startScreen <id>`: abre direto em uma tela (capturas com simctl): home, transactions, new, plan.budget,
///   plan.bills, plan.goals, plan.more, plan.debts, plan.cashflow, reports, tax, wallet.accounts, wallet.cards,
///   wallet.investments, wallet.networth, family, insights, settings.openfinance, scan.
struct LaunchOptions: Equatable, Sendable {
    var seedDemo = false
    var seedFamily = false
    var uiTesting = false
    var skipOnboarding = false
    var fixedToday: Date? = nil
    var appearance: AppearancePreference? = nil
    var hideValues = false
    var lockOnLaunch = false
    var startScreen: String? = nil
    /// `-mockOpenFinance`: usa o `MockBankProvider` (dados fictícios) na tela de Open Finance. Só para testes e capturas.
    var mockOpenFinance = false

    init() {}

    init(arguments: [String]) {
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "-seedDemo": seedDemo = true
            case "-seedFamily": seedFamily = true; seedDemo = true
            case "-uiTesting": uiTesting = true
            case "-skipOnboarding": skipOnboarding = true
            case "-hideValues": hideValues = true
            case "-lockOnLaunch": lockOnLaunch = true
            case "-mockOpenFinance": mockOpenFinance = true
            case "-fixedToday":
                if i + 1 < arguments.count { fixedToday = DateParsing.parse(arguments[i + 1]); i += 1 }
            case "-startScreen":
                if i + 1 < arguments.count { startScreen = arguments[i + 1]; i += 1 }
            case "-appearance":
                if i + 1 < arguments.count { appearance = AppearancePreference(rawValue: arguments[i + 1]); i += 1 }
            default: break
            }
            i += 1
        }
    }
}

/// Flags de execução da UI (não persistidas).
@MainActor
enum UIRuntime {
    /// true com `-uiTesting`: sem animação de contagem, para os testes lerem valores finais.
    static var skipsAnimations = false
    /// A contagem do saldo roda uma vez por sessão.
    static var countUpPlayed = false
}

/// Dados digitados no passo 2 do onboarding.
struct OnboardingDraft: Equatable, Sendable {
    var accountName = ""
    var accountType: AccountType = .checking
    var balanceText = ""
    var faceID = true
    var reminders = true

    var trimmedName: String { accountName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var nameError: String? { trimmedName.isEmpty ? "Dê um nome para a conta." : nil }

    /// Vazio = zero. Texto inválido = nil.
    var balance: Decimal? {
        let t = balanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? 0 : Money.parse(t, style: .comma)
    }

    var balanceError: String? { balance == nil ? "Valor inválido. Exemplo: 1.250,00" : nil }

    var isValid: Bool { nameError == nil && balanceError == nil }
}
