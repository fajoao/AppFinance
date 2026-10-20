import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

private final class Box: @unchecked Sendable { var done = false; var results: [RefreshResult] = [] }

private func runMain(_ op: @escaping @MainActor @Sendable () async -> Void) {
    let box = Box()
    Task { @MainActor in await op(); box.done = true }
    let deadline = Date().addingTimeInterval(10)
    while !box.done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func refreshTests() -> [TestCase] {
    [
        TestCase("refresh: recarrega do repositório, mostra 'Atualizado' e libera o estado") { t in onMain {
            let store = makeStore()
            // grava direto no repositório (como outro aparelho/sync faria) sem passar pelo store
            try! store.repository.save(Tag(name: "externa"))
            t.check(!store.tags.contains { $0.name == "externa" })
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0); t.equal(r, .updated) }
            t.check(store.tags.contains { $0.name == "externa" }, "refresh relê o repositório")
            t.equal(store.toast?.text, "Atualizado"); t.check(store.toast?.isWarning == false)
            t.check(!store.isRefreshing)
            t.equal(store.lastRefreshAt, t0)
        } },
        TestCase("refresh: puxar para atualizar (announcesSuccess false) não mostra toast, mas registra a atualização") { t in onMain {
            let store = makeStore()
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0, announcesSuccess: false); t.equal(r, .updated) }
            t.isNil(store.toast); t.equal(store.lastRefreshAt, t0)
        } },
        TestCase("refresh: toast de sucesso no máximo uma vez a cada 3 s") { t in onMain {
            let store = makeStore()
            runMain { await store.refresh(now: t0, minimumDuration: 0) }
            let first = store.toast?.id
            store.toast = nil
            runMain { await store.refresh(now: t0.addingTimeInterval(1), minimumDuration: 0) }
            t.isNil(store.toast, "dentro de 3 s: sem novo toast")
            runMain { await store.refresh(now: t0.addingTimeInterval(3.5), minimumDuration: 0) }
            t.equal(store.toast?.text, "Atualizado"); t.check(store.toast?.id != first)
        } },
        TestCase("refresh: não roda duas vezes ao mesmo tempo") { t in onMain {
            let store = makeStore()
            let box = Box()
            runMain {
                async let a = store.refresh(now: t0, minimumDuration: 0.1)
                async let b = store.refresh(now: t0, minimumDuration: 0.1)
                box.results = [await a, await b]
            }
            t.equal(box.results.filter { $0 == .updated }.count, 1)
            t.equal(box.results.filter { $0 == .skipped }.count, 1)
            t.check(!store.isRefreshing, "volta a liberar depois de terminar")
            runMain { let r = await store.refresh(now: t0.addingTimeInterval(10), minimumDuration: 0); t.equal(r, .updated) }
        } },
        TestCase("refresh: respeita o bloqueio do app") { t in onMain {
            let store = makeStore()
            store.lockNow()
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0); t.equal(r, .skipped) }
            t.isNil(store.toast); t.check(!store.isRefreshing)
            store.unlock()
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0); t.equal(r, .updated) }
        } },
        TestCase("refresh: sincronização ligada sincroniza; erro vira toast em português e não trava") { t in onMain {
            let server = InMemorySyncService()
            let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                                 clock: { testToday }, syncService: server)
            store.setSyncEnabled(true)
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0); t.equal(r, .updated) }
            t.check(store.preferences.syncState.lastSyncAt != nil, "sincronizou")
            server.failNext = .network("sem rede")
            runMain { let r = await store.refresh(now: t0.addingTimeInterval(10), minimumDuration: 0); t.equal(r, .failed) }
            t.equal(store.toast?.text, "Não foi possível atualizar. Tente de novo."); t.check(store.toast?.isWarning == true)
            t.check(!store.isRefreshing)
            runMain { let r = await store.refresh(now: t0.addingTimeInterval(20), minimumDuration: 0); t.equal(r, .updated) }
        } },
        TestCase("refresh: sincronização desligada (padrão) não toca no serviço") { t in onMain {
            let server = InMemorySyncService()
            server.failNext = .network("não deveria ser chamado")
            let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(), reminders: NoopReminderScheduler(),
                                 clock: { testToday }, syncService: server)
            runMain { let r = await store.refresh(now: t0, minimumDuration: 0); t.equal(r, .updated) }
            t.check(server.failNext != nil, "falha pendente não foi consumida")
        } },
    ]
}
