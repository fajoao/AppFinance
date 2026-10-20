import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Face ID / Touch ID com o código do aparelho como alternativa ("PIN" do app = código do iPhone).
/// Em plataformas sem LocalAuthentication, autentica sempre (apenas para o typecheck no macOS).
@MainActor
enum BiometricAuth {
    enum Method { case faceID, touchID, passcodeOnly, unavailable }

    static var method: Method {
        #if canImport(LocalAuthentication)
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch ctx.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            default: return .passcodeOnly
            }
        }
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .passcodeOnly }
        return .unavailable
        #else
        return .unavailable
        #endif
    }

    /// "Face ID", "Touch ID" ou "código".
    static var displayName: String {
        switch method {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .passcodeOnly, .unavailable: return "código do aparelho"
        }
    }

    /// `biometricsOnly == false` permite o código do aparelho (botão "Usar código").
    static func authenticate(reason: String, biometricsOnly: Bool) async -> Bool {
        #if canImport(LocalAuthentication)
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancelar"
        var error: NSError?
        let policy: LAPolicy = (biometricsOnly && ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &error) else { return false }
        do { return try await ctx.evaluatePolicy(policy, localizedReason: reason) }
        catch { return false }
        #else
        return true
        #endif
    }
}
