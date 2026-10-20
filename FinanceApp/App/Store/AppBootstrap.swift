import Foundation

extension AppStore {
    /// Monta o store de produção ou de teste de UI conforme os launch arguments.
    static func bootstrap(options: LaunchOptions, reminders: ReminderScheduling,
                          widgets: WidgetPublishing = NoopWidgetPublisher(), secrets: SecretStoring = InMemorySecrets(),
                          syncService: SyncService? = nil, fileManager: FileManager = .default) -> AppStore {
        let repository: Repository
        let preferences: PreferencesStoring
        let attachments: AttachmentStorage
        var startupWarning: String?

        if options.uiTesting {
            let dir = fileManager.temporaryDirectory.appendingPathComponent("financeapp-ui-\(UUID().uuidString)", isDirectory: true)
            repository = (try? JSONFileStore(url: dir.appendingPathComponent("data.json"))) ?? InMemoryStore()
            preferences = InMemoryPreferences()
            attachments = AttachmentStorage(directory: dir)
        } else {
            let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fileManager.temporaryDirectory
            let url = base.appendingPathComponent("FinanceApp", isDirectory: true).appendingPathComponent("data.json")
            do {
                repository = try JSONFileStore(url: url)
            } catch {
                // Arquivo ilegível: guarda uma cópia ao lado (nunca apaga) e começa vazio.
                let backup = url.deletingLastPathComponent().appendingPathComponent("data.corrompido-\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.moveItem(at: url, to: backup)
                repository = (try? JSONFileStore(url: url)) ?? InMemoryStore()
                startupWarning = "Os dados estavam ilegíveis. Uma cópia foi guardada em \(backup.lastPathComponent)."
            }
            preferences = UserDefaultsPreferences()
            attachments = AttachmentStorage(directory: base.appendingPathComponent("FinanceApp", isDirectory: true))
        }

        let clock: () -> Date
        if let fixed = options.fixedToday { clock = { fixed } } else { clock = { FinanceCalendar.normalize(Date()) } }

        // Em teste de UI nada sai do aparelho: sem widgets, sem Keychain, sem sincronização.
        let store = AppStore(repository: repository, preferences: preferences, reminders: reminders, clock: clock,
                             widgets: options.uiTesting ? NoopWidgetPublisher() : widgets,
                             secrets: options.uiTesting ? InMemorySecrets() : secrets,
                             attachments: attachments, syncService: options.uiTesting ? nil : syncService)

        store.isUITesting = options.uiTesting
        if options.mockOpenFinance { store.openFinance.provider = MockBankProvider(anchor: clock()) }
        UIRuntime.skipsAnimations = options.uiTesting
        if options.seedDemo { store.attempt { try store.loadDemoData(family: options.seedFamily) } }
        else if options.skipOnboarding && !store.preferences.onboardingDone {
            var draft = OnboardingDraft()
            draft.accountName = "Conta principal"; draft.faceID = false; draft.reminders = false
            store.attempt { try store.completeOnboarding(draft) }
        }
        if let appearance = options.appearance { store.updatePreferences { $0.appearance = appearance } }
        if options.hideValues { store.updatePreferences { $0.hideValues = true } }
        if options.uiTesting { store.updatePreferences { $0.faceIDEnabled = false } }
        if options.lockOnLaunch || (store.preferences.faceIDEnabled && store.preferences.onboardingDone && !options.uiTesting) {
            store.lockNow()
        }
        if let startupWarning { store.show(startupWarning, warning: true) }
        store.runPeriodicTasks()
        return store
    }
}
