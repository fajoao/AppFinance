import SwiftUI

/// auth.lock: cobertura de bloqueio com Face ID/Touch ID e alternativa pelo código do aparelho.
struct LockView: View {
    @Environment(AppStore.self) private var store
    @State private var failed = false
    @State private var isAuthenticating = false
    @State private var pin = ""
    @State private var pinMessage: String?

    var body: some View {
        VStack(spacing: Space.xxl) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            VStack(spacing: Space.sm) {
                Text("App Finanças").font(.title2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Text(failed ? "Não foi possível desbloquear. Tente de novo." : "Seus dados estão protegidos.")
                    .font(.subheadline).foregroundStyle(failed ? Color.danger : Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if store.preferences.pinEnabled { pinEntry }
            Spacer()
            VStack(spacing: Space.sm) {
                if store.preferences.faceIDEnabled || !store.preferences.pinEnabled {
                    Button { Task { await unlock(biometricsOnly: true) } } label: {
                        Label("Desbloquear com \(unlockName)", systemImage: BiometricAuth.method == .touchID ? "touchid" : "faceid")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("auth.lock.biometric")
                }
                Button("Usar código do aparelho") { Task { await unlock(biometricsOnly: false) } }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("auth.lock.passcode")
            }
            .disabled(isAuthenticating)
        }
        .padding(Space.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("auth.lock")
        .task {
            // Tenta desbloquear sozinho ao abrir (não em teste de UI, para o fluxo ser determinístico).
            if !store.isUITesting && store.preferences.faceIDEnabled { await unlock(biometricsOnly: true) }
        }
    }

    private var pinEntry: some View {
        VStack(spacing: Space.sm) {
            PinField(label: "Código do app", text: $pin, identifier: "auth.lock.pin")
            if let pinMessage {
                Label(pinMessage, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger)
                    .accessibilityIdentifier("auth.lock.pin.error")
            }
            Button("Desbloquear com código") { submitPin() }
                .buttonStyle(.primary)
                .disabled(pin.count < PinLock.minLength)
                .accessibilityIdentifier("auth.lock.pin.submit")
        }
    }

    private func submitPin() {
        switch store.unlock(withPin: pin) {
        case .ok, .notSet: pinMessage = nil
        case .wrong(let remaining): pinMessage = "Código incorreto. Restam \(remaining) tentativas antes do bloqueio temporário."
        case .locked(let until): pinMessage = "Muitas tentativas. Tente de novo \(PinLockMessage.waitText(until: until, now: Date()))."
        }
        pin = ""
    }

    private var unlockName: String {
        let n = BiometricAuth.displayName
        return n == "código do aparelho" ? "biometria" : n
    }

    private func unlock(biometricsOnly: Bool) async {
        if store.isUITesting { store.unlock(); return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await BiometricAuth.authenticate(reason: "Desbloquear o App Finanças", biometricsOnly: biometricsOnly)
        if ok { failed = false; store.unlock() } else { failed = true }
    }
}

#Preview("Bloqueio") {
    LockView().previewing(PreviewData.demo)
}

#Preview("Bloqueio, escuro, texto grande") {
    LockView().previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility3)
}
