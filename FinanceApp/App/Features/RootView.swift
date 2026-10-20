import SwiftUI

/// Raiz: onboarding ou abas, cobertura de bloqueio, escudo de privacidade e toast.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if store.preferences.onboardingDone {
                MainTabView()
            } else {
                OnboardingFlow()
            }
            if store.isLocked {
                LockView().transition(.opacity).zIndex(2)
            } else if scenePhase != .active && store.appLockEnabled && store.preferences.onboardingDone {
                // Esconde os valores no seletor de apps.
                Color.canvas.ignoresSafeArea().overlay { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Color.textTertiary) }
                    .zIndex(3).accessibilityHidden(true)
            }
        }
        .environment(\.valuesHidden, store.preferences.hideValues)
        .preferredColorScheme(store.preferences.appearance.colorScheme)
        .toastHost(announces: true)
        .animation(.easeOut(duration: Motion.standard), value: store.isLocked)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: store.sceneBackgrounded()
            case .active:
                store.sceneActivated(); store.reload(); store.runPeriodicTasks()
                Task { await store.syncNow() }
            default: break
            }
        }
        .task { await store.rescheduleReminders() }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var lastRealTab: MainTab = .home

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Início", systemImage: "house") }
                .tag(MainTab.home)
                .accessibilityIdentifier("tab.home")
            NavigationStack { TransactionsView() }
                .tabItem { Label("Lançamentos", systemImage: "list.bullet") }
                .tag(MainTab.transactions)
                .accessibilityIdentifier("tab.transactions")
            Color.canvas
                .tabItem { Label("Novo", systemImage: "plus.circle.fill") }
                .tag(MainTab.new)
                .accessibilityIdentifier("tab.new")
            NavigationStack(path: $router.planPath) { PlanView() }
                .tabItem { Label("Planejar", systemImage: "target") }
                .tag(MainTab.plan)
                .accessibilityIdentifier("tab.plan")
            NavigationStack { WalletView() }
                .tabItem { Label("Carteira", systemImage: "wallet.pass") }
                .tag(MainTab.wallet)
                .accessibilityIdentifier("tab.wallet")
        }
        .onChange(of: router.tab) { _, new in
            if new == .new {
                router.tab = lastRealTab
                router.presentNew()
            } else {
                lastRealTab = new
            }
        }
        .sheet(isPresented: $router.showsOpenFinance) {
            NavigationStack { OpenFinanceView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { router.showsOpenFinance = false } } } }
        }
        .sheet(isPresented: $router.showsNewTransaction) {
            NewTransactionView(type: router.newTransactionType, date: router.newTransactionDate)
                .presentationDetents([.large])
                .presentationCornerRadius(Radius.sheet)
        }
    }
}

#Preview("Abas com dados") {
    MainTabView().previewing(PreviewData.demo).environment(Router())
}

#Preview("Abas vazias, escuro") {
    MainTabView().previewing(PreviewData.empty, dark: true).environment(Router())
}
