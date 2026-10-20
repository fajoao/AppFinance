import SwiftUI

/// App do Apple Watch: saldo, gasto do dia, próximo vencimento e despesa rápida por ditado.
/// Lê o resumo que o iPhone envia (WatchConnectivity); não tem banco de dados nem regra financeira própria.
@main
struct FinanceWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchHomeView() }
                .environment(model)
                .task { model.start() }
        }
    }
}
