import Foundation

enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }
}

/// Bloquear após: minutos em segundo plano (0 = imediatamente).
enum LockDelay: Int, Codable, CaseIterable, Sendable, Identifiable {
    case immediately = 0, oneMinute = 1, fiveMinutes = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: return "Imediatamente"
        case .oneMinute: return "1 minuto"
        case .fiveMinutes: return "5 minutos"
        }
    }
}

/// Visão dos dados quando existe um grupo familiar.
enum ViewScopePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case family, individual
    var id: String { rawValue }
    var title: String { self == .family ? "Família" : "Individual" }
}

/// Preferências do app (não são dados financeiros): ficam em UserDefaults, não no JSON de dados.
/// A decodificação é tolerante: preferências gravadas por versões anteriores continuam válidas.
struct AppPreferences: Codable, Equatable, Sendable {
    var onboardingDone = false
    var hideValues = false
    var faceIDEnabled = false
    var lockDelay: LockDelay = .immediately
    var appearance: AppearancePreference = .system
    var remindersEnabled = false
    /// Antecedência dos lembretes de vencimento, em dias (0 = no dia).
    var reminderDaysBefore = 1
    /// Alertas de orçamento já emitidos ("<categoria>|<mês>|warning|exceeded"), para avisar uma vez só.
    var budgetAlertsSent: Set<String> = []

    // Fase 2
    /// Perfil ativo (FamilyMember). nil = sem grupo familiar.
    var activeMemberId: UUID? = nil
    var viewScope: ViewScopePreference = .family
    /// PIN próprio do app (o hash fica no Keychain; aqui só o estado). Desligado por padrão.
    var pinEnabled = false
    var pinFailedAttempts = 0
    var pinLockedUntil: Date? = nil
    /// Sincronização com o iCloud. DESLIGADA por padrão; ver docs/cloudkit-setup.md.
    var syncEnabled = false
    var syncState = SyncState()

    // Fase 3
    /// Open Finance: DESLIGADO por padrão. Só liga depois da tela de consentimento (e só funciona com um provedor configurado).
    var openFinanceEnabled = false
    var openFinanceConsentAt: Date? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        onboardingDone = get(.onboardingDone, false)
        hideValues = get(.hideValues, false)
        faceIDEnabled = get(.faceIDEnabled, false)
        lockDelay = get(.lockDelay, LockDelay.immediately)
        appearance = get(.appearance, AppearancePreference.system)
        remindersEnabled = get(.remindersEnabled, false)
        reminderDaysBefore = get(.reminderDaysBefore, 1)
        budgetAlertsSent = get(.budgetAlertsSent, Set<String>())
        activeMemberId = try? c.decodeIfPresent(UUID.self, forKey: .activeMemberId)
        viewScope = get(.viewScope, ViewScopePreference.family)
        pinEnabled = get(.pinEnabled, false)
        pinFailedAttempts = get(.pinFailedAttempts, 0)
        pinLockedUntil = try? c.decodeIfPresent(Date.self, forKey: .pinLockedUntil)
        syncEnabled = get(.syncEnabled, false)
        syncState = get(.syncState, SyncState())
        openFinanceEnabled = get(.openFinanceEnabled, false)
        openFinanceConsentAt = try? c.decodeIfPresent(Date.self, forKey: .openFinanceConsentAt)
    }
}

protocol PreferencesStoring: AnyObject {
    func load() -> AppPreferences
    func save(_ prefs: AppPreferences)
}

final class UserDefaultsPreferences: PreferencesStoring {
    private let defaults: UserDefaults
    private let key: String
    init(defaults: UserDefaults = .standard, key: String = "financeapp.preferences.v1") {
        self.defaults = defaults; self.key = key
    }
    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return AppPreferences() }
        return p
    }
    func save(_ prefs: AppPreferences) {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: key) }
    }
}

final class InMemoryPreferences: PreferencesStoring {
    private var value: AppPreferences
    init(_ initial: AppPreferences = AppPreferences()) { value = initial }
    func load() -> AppPreferences { value }
    func save(_ prefs: AppPreferences) { value = prefs }
}
