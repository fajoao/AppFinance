import Foundation

private final class ResultBox<V: Sendable>: @unchecked Sendable { var result: Result<V, Error>? }

/// Executa uma operação assíncrona de forma bloqueante (o runner de testes é síncrono).
func runBlocking<V: Sendable>(_ op: @escaping @Sendable () async throws -> V) throws -> V {
    let box = ResultBox<V>()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await op()) } catch { box.result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try box.result!.get()
}

private func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

private func account(_ name: String, id: UUID = UUID(), updated: Double) -> Account {
    var a = Account(id: id, name: name, type: .checking)
    a.createdAt = at(0); a.updatedAt = at(updated)
    return a
}

func syncTests() -> [TestCase] {
    return [
        TestCase("merge: vence o updatedAt mais recente, em qualquer lado") { t in
            let id = UUID()
            var local = FinanceSnapshot(), remote = FinanceSnapshot()
            local.accounts = [account("Local novo", id: id, updated: 200)]
            remote.accounts = [account("Remoto velho", id: id, updated: 100)]
            let r1 = SyncEngine.merge(local: local, remote: remote)
            t.equal(r1.snapshot.accounts.map(\.name), ["Local novo"]); t.equal(r1.report.keptLocal, 1)
            local.accounts = [account("Local velho", id: id, updated: 50)]
            let r2 = SyncEngine.merge(local: local, remote: remote)
            t.equal(r2.snapshot.accounts.map(\.name), ["Remoto velho"]); t.equal(r2.report.applied, 1)
        },
        TestCase("merge: empate tem desempate determinístico (mesmo resultado nos dois dispositivos)") { t in
            let id = UUID()
            var a = FinanceSnapshot(), b = FinanceSnapshot()
            a.accounts = [account("Alfa", id: id, updated: 100)]
            b.accounts = [account("Beta", id: id, updated: 100)]
            let x = SyncEngine.merge(local: a, remote: b).snapshot.accounts
            let y = SyncEngine.merge(local: b, remote: a).snapshot.accounts
            t.equal(x, y); t.equal(x.count, 1)
        },
        TestCase("merge: registros novos de cada lado são unidos, de todos os tipos") { t in
            var local = FinanceSnapshot(), remote = FinanceSnapshot()
            local.accounts = [account("A", updated: 1)]
            remote.accounts = [account("B", updated: 1)]
            local.goals = [Goal(name: "G", targetAmount: 10)]
            remote.investments = [Investment(name: "I", assetClass: .stock, quantity: 1, averagePrice: 1)]
            remote.transactions = [tx(.expense, "5", D(2026, 1, 1))]
            let m = SyncEngine.merge(local: local, remote: remote)
            t.equal(Set(m.snapshot.accounts.map(\.name)), ["A", "B"])
            t.equal(m.snapshot.goals.count, 1); t.equal(m.snapshot.investments.count, 1); t.equal(m.snapshot.transactions.count, 1)
            t.equal(m.report.applied, 3, "B, investimento e lançamento vieram do remoto")
        },
        TestCase("merge: exclusão (tombstone) vence edição anterior, mas não edição posterior") { t in
            let doomed = account("Apagada", updated: 100)
            let revived = account("Editada depois", updated: 300)
            var local = FinanceSnapshot(), remote = FinanceSnapshot()
            local.accounts = [doomed, revived]
            remote.tombstones = [Tombstone(entityType: "Account", entityId: doomed.id, deletedAt: at(200)),
                                 Tombstone(entityType: "Account", entityId: revived.id, deletedAt: at(200))]
            let m = SyncEngine.merge(local: local, remote: remote)
            t.equal(m.snapshot.accounts.map(\.name), ["Editada depois"])
            t.equal(m.report.deleted, 1)
            t.equal(m.snapshot.tombstones.count, 2, "tombstones são mantidos para propagar")
        },
        TestCase("changes: só o que mudou desde a última sincronização") { t in
            var s = FinanceSnapshot()
            s.accounts = [account("Velha", updated: 100), account("Nova", updated: 300)]
            s.tombstones = [Tombstone(entityType: "Goal", entityId: UUID(), deletedAt: at(400))]
            let c = SyncEngine.changes(in: s, since: at(200))
            t.equal(c.accounts.map(\.name), ["Nova"]); t.equal(c.tombstones.count, 1)
            t.equal(SyncEngine.changes(in: s, since: nil).accounts.count, 2)
            t.equal(SyncEngine.changes(in: s, since: at(500)).accounts.count, 0)
        },
        TestCase("coordenador: dois dispositivos convergem (edição mais nova e exclusão propagam)") { t in
            let remote = InMemorySyncService()
            let repoA = InMemoryStore(), repoB = InMemoryStore()
            let shared = account("Conta", updated: 100)
            try repoA.save(shared)
            let a = SyncCoordinator(repository: repoA, service: remote)
            let b = SyncCoordinator(repository: repoB, service: remote)

            let r1 = try runBlocking { try await a.sync(now: at(1000)) }
            t.equal(r1.pushed, 1)
            let r2 = try runBlocking { try await b.sync(now: at(1001)) }
            t.equal(r2.pulled, 1)
            t.equal(try repoB.all(Account.self).map(\.name), ["Conta"])

            // A edita (t=2000), B edita depois (t=3000): vence B
            var ea = shared; ea.name = "Editada em A"; ea.updatedAt = at(2000); try repoA.save(ea)
            var eb = shared; eb.name = "Editada em B"; eb.updatedAt = at(3000); try repoB.save(eb)
            _ = try runBlocking { try await a.sync(now: at(3100)) }
            _ = try runBlocking { try await b.sync(now: at(3200)) }
            _ = try runBlocking { try await a.sync(now: at(3300)) }
            t.equal(try repoA.all(Account.self).map(\.name), ["Editada em B"])
            t.equal(try repoB.all(Account.self).map(\.name), ["Editada em B"])

            // B apaga; A recebe a exclusão
            try repoB.delete(Account.self, id: shared.id)
            try repoB.save(Tombstone(entityType: "Account", entityId: shared.id, deletedAt: at(4000), updatedAt: at(4000)))
            _ = try runBlocking { try await b.sync(now: at(4100)) }
            _ = try runBlocking { try await a.sync(now: at(4200)) }
            t.equal(try repoA.all(Account.self).count, 0)
        },
        TestCase("coordenador: falha do serviço não altera os dados nem avança lastSync") { t in
            let remote = InMemorySyncService()
            remote.failNext = SyncError.network("sem rede")
            let repo = InMemoryStore()
            try repo.save(account("Local", updated: 10))
            let c = SyncCoordinator(repository: repo, service: remote)
            do { _ = try runBlocking { try await c.sync(now: at(100)) }; t.fail("deveria falhar") }
            catch { t.equal(error as? SyncError, SyncError.network("sem rede")) }
            t.equal(try repo.all(Account.self).count, 1)
            let last = try runBlocking { await c.state.lastSyncAt }
            t.isNil(last)
            let ok = try runBlocking { try await c.sync(now: at(200)) }
            t.equal(ok.pushed, 1)
            t.equal(try runBlocking { await c.state.lastSyncAt }, Optional(at(200)))
        },
        TestCase("coordenador: conta iCloud indisponível não sincroniza") { t in
            let remote = InMemorySyncService()
            remote.status = .noAccount
            let c = SyncCoordinator(repository: InMemoryStore(), service: remote)
            do { _ = try runBlocking { try await c.sync(now: at(100)) }; t.fail("deveria falhar") }
            catch { t.equal(error as? SyncError, SyncError.accountUnavailable(SyncAccountStatus.noAccount.explanation)) }
            t.check(!SyncAccountStatus.noAccount.isAvailable && SyncAccountStatus.available.isAvailable)
        },
        TestCase("exclusão rastreada: deleteTracked remove e grava o tombstone") { t in
            let repo = InMemoryStore()
            let a = account("X", updated: 1)
            try repo.save(a)
            try repo.deleteTracked(Account.self, id: a.id, now: at(500))
            t.equal(try repo.all(Account.self).count, 0)
            let ts = try repo.all(Tombstone.self)
            t.equal(ts.count, 1); t.equal(ts[0].entityType, "Account"); t.equal(ts[0].entityId, a.id); t.equal(ts[0].deletedAt, at(500))
            t.equal(try repo.deleteTracked(Account.self, id: a.id, now: at(600)), false)
            t.equal(try repo.all(Tombstone.self).count, 1)
        },
    ]
}
