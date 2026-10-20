import Foundation

enum RefreshResult: Equatable, Sendable {
    /// Atualizou tudo.
    case updated
    /// Não rodou: já havia uma atualização em andamento ou o app está bloqueado.
    case skipped
    /// Rodou, mas a sincronização falhou (os dados locais foram recarregados mesmo assim).
    case failed
}

extension AppStore {
    /// Atualização manual (botão e puxar para atualizar): recarrega do Repository (recalcula derivados e republica o
    /// resumo dos widgets, via `reload()`), roda as tarefas idempotentes de abertura, reagenda lembretes e, se a
    /// sincronização estiver ligada e configurada, sincroniza. Não roda em paralelo nem com o app bloqueado.
    /// `announcesSuccess: false` (puxar para atualizar) não mostra o toast de sucesso; erros sempre aparecem.
    /// Toast: "Atualizado" (no máximo um a cada 3 s) ou "Não foi possível atualizar" em caso de erro.
    /// `minimumDuration` mantém o indicador visível por um instante, já que o trabalho local é quase imediato.
    @discardableResult
    func refresh(now: Date = Date(), minimumDuration: TimeInterval = 0.5, announcesSuccess: Bool = true) async -> RefreshResult {
        guard !isLocked, !isRefreshing else { return .skipped }
        isRefreshing = true
        defer { isRefreshing = false }
        let started = Date()
        reload()
        runPeriodicTasks()
        await rescheduleReminders()
        var failed = false
        if preferences.syncEnabled && syncConfigured {
            await syncNow(now: now)
            if case .failed = syncStatus { failed = true }
        }
        let remaining = minimumDuration - Date().timeIntervalSince(started)
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        if failed {
            show("Não foi possível atualizar. Tente de novo.", warning: true)
            return .failed
        }
        lastRefreshAt = now
        // No puxar para atualizar o próprio indicador e o háptico são o retorno: um toast no topo apareceria sobre a
        // barra de navegação no meio do movimento do scroll (visto como textos sobrepostos).
        guard announcesSuccess else { return .updated }
        if lastRefreshToastAt.map({ now.timeIntervalSince($0) >= 3 || now < $0 }) ?? true {
            lastRefreshToastAt = now
            show("Atualizado")
        }
        return .updated
    }
}
