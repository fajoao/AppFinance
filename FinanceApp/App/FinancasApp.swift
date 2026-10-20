import SwiftUI

@main
struct FinancasApp: App {
    @State private var store: AppStore
    @State private var router: Router

    init() {
        let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        let store = Production.makeStore(options: options)
        #if canImport(AppIntents)
        AppStoreRegistry.store = store
        #endif
        _store = State(initialValue: store)
        let router = Router()
        router.apply(options)
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .tint(Color.brandPrimary)
        }
    }
}
