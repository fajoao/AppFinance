import Foundation

/// Publica o resumo para os widgets. A implementação real (App Group + WidgetKit) está em `App/Services`.
protocol WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot)
}

struct NoopWidgetPublisher: WidgetPublishing {
    init() {}
    func publish(_ snapshot: WidgetSnapshot) {}
}

/// Guarda segredos pequenos (hash do PIN). A implementação real usa o Keychain.
protocol SecretStoring {
    func data(for key: String) -> Data?
    func set(_ data: Data?, for key: String)
}

final class InMemorySecrets: SecretStoring {
    private var values: [String: Data] = [:]
    init() {}
    func data(for key: String) -> Data? { values[key] }
    func set(_ data: Data?, for key: String) { values[key] = data }
}
