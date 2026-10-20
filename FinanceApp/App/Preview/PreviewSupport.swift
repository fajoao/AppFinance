import SwiftUI

/// Dados para #Preview. Usa InMemoryStore: nada é gravado em disco.
@MainActor
enum PreviewData {
    static let today = FinanceCalendar.date(2026, 10, 19)

    private static func make(seed: Bool, onboarded: Bool = true) -> AppStore {
        let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(),
                             reminders: NoopReminderScheduler(), clock: { today })
        if seed { try? store.loadDemoData() }
        else if onboarded {
            var d = OnboardingDraft(); d.accountName = "Nubank"; d.balanceText = "0"
            try? store.completeOnboarding(d)
        }
        return store
    }

    /// Dados de demonstração completos.
    static var demo: AppStore { make(seed: true) }
    /// Demonstração com o grupo familiar (Ana, Bruno e Caio).
    static var family: AppStore {
        let store = make(seed: false, onboarded: false)
        try? store.loadDemoData(family: true)
        return store
    }
    /// Demonstração com o provedor de Open Finance FICTÍCIO e o consentimento dado.
    static var openFinanceMock: AppStore {
        let store = make(seed: true)
        store.openFinance.provider = MockBankProvider(anchor: today)
        store.setOpenFinanceEnabled(true)
        return store
    }
    /// Conta criada, sem lançamentos (estado vazio).
    static var empty: AppStore { make(seed: false) }
    /// Sem nada (onboarding).
    static var fresh: AppStore { make(seed: false, onboarded: false) }

    /// Valores extremos: saldo gigante, negativo e nome longo.
    static var extremes: AppStore {
        let store = make(seed: false)
        try? store.addAccount(name: "Conta corrente do banco com um nome absurdamente longo para testar truncamento", type: .checking, balance: dec("98765432.10"))
        try? store.addAccount(name: "Cheque especial", type: .checking, balance: dec("-12345.67"))
        return store
    }
}

extension View {
    /// Envolve a View com o store e o esquema de cor para previews.
    func previewing(_ store: AppStore, dark: Bool = false) -> some View {
        environment(store)
            .environment(\.valuesHidden, store.preferences.hideValues)
            .preferredColorScheme(dark ? .dark : .light)
    }
}
