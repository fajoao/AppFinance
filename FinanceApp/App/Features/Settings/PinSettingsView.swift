import SwiftUI

/// Campo de código numérico (4 a 6 dígitos), mascarado.
struct PinField: View {
    let label: String
    @Binding var text: String
    var identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
            SecureField("••••", text: $text)
                .numberKeyboard()
                .font(.body.monospacedDigit())
                .padding(.horizontal, Space.md)
                .frame(minHeight: Space.minTouchTarget)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .onChange(of: text) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(PinLock.maxLength))
                    if digits != new { text = digits }
                }
                .accessibilityIdentifier(identifier)
        }
    }
}

/// settings.pin: código próprio do app (opcional), além de Face ID e do código do aparelho.
struct PinSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var currentPin = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("O código do app é opcional e vale só aqui. Ele fica protegido no Keychain deste aparelho. Se você esquecer, será preciso apagar os dados do app.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                if store.preferences.pinEnabled { enabled } else { disabled }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger)
                        .accessibilityIdentifier("settings.pin.error")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .background(Color.canvas)
        .navigationTitle("Código do app")
        .inlineNavigationTitle()
        .accessibilityIdentifier("settings.pin")
    }

    private var disabled: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PinField(label: "Novo código (4 a 6 números)", text: $newPin, identifier: "settings.pin.new")
            PinField(label: "Repita o código", text: $confirmPin, identifier: "settings.pin.confirm")
            Button("Ativar código") {
                guard newPin == confirmPin else { error = "Os códigos não são iguais."; return }
                if store.attempt({ try store.setPin(newPin) }) {
                    newPin = ""; confirmPin = ""; error = nil; store.show("Código ativado.")
                }
            }
            .buttonStyle(.primary).disabled(!PinLock.isValidFormat(newPin)).accessibilityIdentifier("settings.pin.enable")
        }
    }

    private var enabled: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Label("Código ativo", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(Color.income)
            PinField(label: "Código atual", text: $currentPin, identifier: "settings.pin.current")
            Button("Desativar código") {
                switch store.removePin(current: currentPin) {
                case .ok, .notSet: currentPin = ""; error = nil; store.show("Código desativado.")
                case .wrong(let remaining): error = "Código incorreto. Restam \(remaining) tentativas antes do bloqueio temporário."
                case .locked(let until): error = "Muitas tentativas. Tente de novo \(PinLockMessage.waitText(until: until, now: Date()))."
                }
            }
            .buttonStyle(.secondary).disabled(currentPin.isEmpty).accessibilityIdentifier("settings.pin.disable")
        }
    }
}

enum PinLockMessage {
    /// "em 30 segundos", "em 2 minutos".
    static func waitText(until: Date, now: Date) -> String {
        let s = max(Int(until.timeIntervalSince(now).rounded(.up)), 1)
        if s < 60 { return "em \(s) \(s == 1 ? "segundo" : "segundos")" }
        let m = (s + 59) / 60
        return "em \(m) \(m == 1 ? "minuto" : "minutos")"
    }
}

#Preview("Código do app") {
    NavigationStack { PinSettingsView() }.previewing(PreviewData.demo)
}
