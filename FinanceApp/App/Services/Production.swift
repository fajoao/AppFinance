import Foundation

/// Monta a store de produção com os serviços reais (Keychain, App Group/WidgetKit, notificações e, se habilitado,
/// CloudKit). A lógica em si (`AppStore.bootstrap`) não conhece esses serviços para continuar testável com swiftc.
@MainActor
enum Production {
    static func makeStore(options: LaunchOptions) -> AppStore {
        var publishers: [WidgetPublishing] = [makeWidgetPublisher()]
        #if canImport(WatchConnectivity) && os(iOS)
        let watch = WatchConnectivityBridge()
        if !options.uiTesting { publishers.append(watch) }
        #endif
        let store = AppStore.bootstrap(options: options, reminders: makeReminderScheduler(), widgets: CompositeWidgetPublisher(targets: publishers),
                                       secrets: makeSecretStore(), syncService: makeSyncService())
        #if canImport(WatchConnectivity) && os(iOS)
        if !options.uiTesting {
            watch.onQuickAdd = { [weak store] request in store?.addFromWatch(request) }
            watch.activate()
        }
        #endif
        return store
    }
}
