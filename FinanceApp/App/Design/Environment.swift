import SwiftUI

private struct ValuesHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// true quando o usuário ocultou os valores (olho no Início). Componentes de valor leem isto.
    var valuesHidden: Bool {
        get { self[ValuesHiddenKey.self] }
        set { self[ValuesHiddenKey.self] = newValue }
    }
}

extension AppStore {
    /// Binding para uma preferência persistida.
    func binding<V>(_ keyPath: WritableKeyPath<AppPreferences, V>) -> Binding<V> {
        Binding(get: { self.preferences[keyPath: keyPath] },
                set: { newValue in self.updatePreferences { $0[keyPath: keyPath] = newValue } })
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
