import Foundation
#if canImport(Security)
import Security

/// Segredos no Keychain (hash do PIN). `ThisDeviceOnly`: não vai para backups nem para outros aparelhos.
final class KeychainSecrets: SecretStoring {
    private let service: String
    init(service: String = "com.example.financas") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func data(for key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func set(_ data: Data?, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard let data else { return }
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
#endif

/// Keychain no app; memória onde não existir (typecheck em outras plataformas).
func makeSecretStore() -> SecretStoring {
    #if canImport(Security)
    return KeychainSecrets()
    #else
    return InMemorySecrets()
    #endif
}
