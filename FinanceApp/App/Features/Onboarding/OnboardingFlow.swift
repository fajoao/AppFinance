import SwiftUI

/// Onboarding em 3 passos: onboarding.welcome, onboarding.account, onboarding.security.
struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store
    @State private var step = 1
    @State private var draft = OnboardingDraft()
    @State private var showNameError = false
    @State private var isFinishing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 1: welcome
                case 2: account
                default: security
                }
            }
            .transition(.opacity)
        }
        .background(Color.canvas.ignoresSafeArea())
        .animation(.easeOut(duration: Motion.standard), value: step)
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack {
            if step > 1 {
                Button { step -= 1 } label: { Label("Voltar", systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            Text("Passo \(step) de 3").font(.footnote).foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier("onboarding.progress")
        }
        .padding(.horizontal, Space.screenMargin)
        .frame(minHeight: Space.minTouchTarget)
    }

    // MARK: Passo 1

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Seu dinheiro, claro e só seu.").font(.largeTitle.bold()).foregroundStyle(Color.textPrimary)
                    Text("Controle contas, cartões, orçamento e metas em reais, sem complicação.")
                        .font(.body).foregroundStyle(Color.textSecondary)
                }
                HighlightBlock {
                    Text("Exemplo").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    SplitAmount(value: dec("3482.16"))
                    Text("Saldo em contas").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                .environment(\.valuesHidden, false)
                VStack(alignment: .leading, spacing: Space.lg) {
                    guarantee("lock.shield", "Privado por padrão", "Seus dados ficam só neste aparelho. Nada é enviado a servidores.")
                    guarantee("doc.text", "Importe seu extrato", "Traga lançamentos de arquivos OFX e CSV do seu banco, sem duplicar.")
                }
                Button("Começar") { step = 2 }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("onboarding.welcome.start")
            }
            .padding(Space.screenMargin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.welcome")
    }

    private func guarantee(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.brandPrimary).frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Passo 2

    private var account: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Sua primeira conta").font(.largeTitle.bold()).foregroundStyle(Color.textPrimary)
                    Text("Você poderá adicionar outras contas e cartões depois.").font(.body).foregroundStyle(Color.textSecondary)
                }
                LabeledField(label: "Nome da conta", text: $draft.accountName, prompt: "Ex.: Nubank, Carteira",
                             error: showNameError ? draft.nameError : nil, identifier: "onboarding.account.name")
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Tipo").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    FlowLayout(spacing: Space.sm) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Chip(title: type.displayName, systemImage: type.symbol, isSelected: draft.accountType == type) {
                                draft.accountType = type
                            }
                            .accessibilityIdentifier("onboarding.account.type.\(type.rawValue)")
                        }
                    }
                }
                LabeledField(label: "Saldo de hoje", text: $draft.balanceText, prompt: "0,00",
                             error: draft.balanceError, isDecimal: true, identifier: "onboarding.account.balance")
                Button("Continuar") {
                    if draft.nameError != nil { showNameError = true } else if draft.isValid { step = 3 }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("onboarding.account.continue")
            }
            .padding(Space.screenMargin)
        }
        .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.account")
    }

    // MARK: Passo 3

    private var security: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Proteção e lembretes").font(.largeTitle.bold()).foregroundStyle(Color.textPrimary)
                    Text("Você pode mudar isso a qualquer momento em Ajustes.").font(.body).foregroundStyle(Color.textSecondary)
                }
                ListGroup {
                    Toggle(isOn: faceIDBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bloquear com \(BiometricAuth.displayName)").font(.body).foregroundStyle(Color.textPrimary)
                            Text("Pede para desbloquear ao abrir o app.").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
                    .accessibilityIdentifier("onboarding.security.faceid")
                    RowSeparator()
                    Toggle(isOn: $draft.reminders) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lembrar de contas a pagar").font(.body).foregroundStyle(Color.textPrimary)
                            Text("Uma notificação um dia antes do vencimento.").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
                    .accessibilityIdentifier("onboarding.security.reminders")
                }
                Button("Concluir") { Task { await finish() } }
                    .buttonStyle(.primary)
                    .disabled(isFinishing)
                    .accessibilityIdentifier("onboarding.security.finish")
            }
            .padding(Space.screenMargin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.security")
    }

    /// Ao ligar, confirma uma vez para garantir que a biometria funciona (e dispara a permissão do Face ID).
    private var faceIDBinding: Binding<Bool> {
        Binding(get: { draft.faceID }, set: { newValue in
            guard newValue, !store.isUITesting else { draft.faceID = newValue; return }
            Task {
                let ok = await BiometricAuth.authenticate(reason: "Ativar o bloqueio do app", biometricsOnly: false)
                draft.faceID = ok
                if !ok { store.show("Não foi possível ativar o bloqueio.", warning: true) }
            }
        })
    }

    private func finish() async {
        isFinishing = true
        defer { isFinishing = false }
        var reminders = draft.reminders
        if reminders, !store.isUITesting { reminders = await store.reminders.requestAuthorization() }
        var d = draft
        d.reminders = reminders
        store.attempt { try store.completeOnboarding(d) }
    }
}

#Preview("Onboarding") {
    OnboardingFlow().previewing(PreviewData.fresh)
}

#Preview("Onboarding, escuro, texto grande") {
    OnboardingFlow().previewing(PreviewData.fresh, dark: true).dynamicTypeSize(.accessibility2)
}
