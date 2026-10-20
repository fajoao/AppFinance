import Foundation

// PIN próprio, sincronização (desligada por padrão), tarefas periódicas e atalho "adicionar despesa".

extension AppStore {
    // MARK: PIN

    private var pinRecord: PinRecord? {
        secrets.data(for: PinLock.keychainKey).flatMap { try? JSONDecoder().decode(PinRecord.self, from: $0) }
    }

    func setPin(_ pin: String) throws {
        guard PinLock.isValidFormat(pin) else { throw StoreError.pinInvalid }
        secrets.set(try JSONEncoder().encode(PinLock.makeRecord(pin: pin)), for: PinLock.keychainKey)
        updatePreferences { $0.pinEnabled = true; $0.pinFailedAttempts = 0; $0.pinLockedUntil = nil }
    }

    /// Desliga o PIN depois de conferir o código atual.
    @discardableResult
    func removePin(current: String, now: Date = Date()) -> PinResult {
        let result = verifyPin(current, now: now)
        if result == .ok || result == .notSet {
            secrets.set(nil, for: PinLock.keychainKey)
            updatePreferences { $0.pinEnabled = false; $0.pinFailedAttempts = 0; $0.pinLockedUntil = nil }
        }
        return result
    }

    /// Confere o PIN aplicando o bloqueio progressivo após tentativas erradas.
    func verifyPin(_ pin: String, now: Date = Date()) -> PinResult {
        guard preferences.pinEnabled, let record = pinRecord else { return .notSet }
        if let until = preferences.pinLockedUntil, until > now { return .locked(until: until) }
        if PinLock.verify(pin: pin, record: record) {
            updatePreferences { $0.pinFailedAttempts = 0; $0.pinLockedUntil = nil }
            return .ok
        }
        let failed = preferences.pinFailedAttempts + 1
        let wait = PinLock.lockoutSeconds(failedAttempts: failed)
        updatePreferences {
            $0.pinFailedAttempts = failed
            $0.pinLockedUntil = wait > 0 ? now.addingTimeInterval(wait) : nil
        }
        if wait > 0 { return .locked(until: now.addingTimeInterval(wait)) }
        return .wrong(remainingFreeAttempts: max(PinLock.freeAttempts - failed, 0))
    }

    /// Desbloqueia o app com o PIN.
    func unlock(withPin pin: String, now: Date = Date()) -> PinResult {
        let r = verifyPin(pin, now: now)
        if r == .ok { unlock() }
        return r
    }

    // MARK: Sincronização (opcional, desligada por padrão)

    /// true quando este build tem um `SyncService` configurado (CloudKit exige capability e container no Xcode).
    var syncConfigured: Bool { syncService != nil }

    func setSyncEnabled(_ on: Bool) {
        updatePreferences { $0.syncEnabled = on }
        syncStatus = on ? .idle(lastSync: preferences.syncState.lastSyncAt) : .disabled
        if !on { syncCoordinator = nil }
    }

    func syncNow(now: Date = Date()) async {
        guard preferences.syncEnabled else { syncStatus = .disabled; return }
        guard let service = syncService else { syncStatus = .failed(StoreError.syncUnavailable.message); return }
        syncStatus = .syncing
        let coordinator = syncCoordinator ?? SyncCoordinator(repository: repository, service: service, state: preferences.syncState)
        syncCoordinator = coordinator
        do {
            try await coordinator.sync(now: now)
            let state = await coordinator.state
            updatePreferences { $0.syncState = state }
            reload()
            syncStatus = .idle(lastSync: state.lastSyncAt)
        } catch let e as SyncError {
            syncStatus = .failed(e.message)
        } catch {
            syncStatus = .failed("Falha ao sincronizar: \(error.localizedDescription)")
        }
    }

    // MARK: Tarefas ao abrir o app

    /// Mesada devida e registro do patrimônio do mês. Idempotente; chamado ao iniciar e ao voltar ao primeiro plano.
    func runPeriodicTasks() {
        guard preferences.onboardingDone else { return }
        attempt {
            try payAllowancesDue()
            if !accounts.isEmpty { try recordNetWorthSnapshot() }
        }
    }

    // MARK: Atalho da Siri / App Intents

    /// "Adicionar despesa": usa a conta padrão do perfil ativo e a categoria sugerida. Passa pela regra de aprovação de dependentes.
    @discardableResult
    func quickAddExpense(title: String, amountText: String) throws -> String {
        guard let amount = Money.parse(amountText, style: .auto), amount > 0 else { throw DraftError.zeroAmount }
        guard let account = activeAccounts.first else { throw DraftError.missingSource }
        var draft = makeDraft(type: .expense)
        draft.keypad = AmountKeypad(value: amount)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.title = t.isEmpty ? "Despesa" : t
        draft.source = .account(account.id)
        draft.chooseCategory(suggestCategory(for: draft.title, type: .expense))
        let value = MoneyDisplay.text(amount)
        switch try submit(draft) {
        case .saved: return "Despesa de \(value) registrada em \(account.name)."
        case .awaitingApproval: return "Despesa de \(value) enviada para aprovação."
        }
    }

    /// Frase livre ("gastei 45,90 no mercado").
    @discardableResult
    func quickAddExpense(phrase: String) throws -> String {
        guard let q = QuickExpenseParser.parse(phrase) else { throw DraftError.zeroAmount }
        return try quickAddExpense(title: q.title, amountText: Money.plain(q.amount))
    }
}
