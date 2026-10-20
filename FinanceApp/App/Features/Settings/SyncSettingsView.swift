import SwiftUI

/// settings.sync: sincronização com o iCloud (desligada por padrão).
struct SyncSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ListGroup {
                    Toggle(isOn: Binding(get: { store.preferences.syncEnabled }, set: { store.setSyncEnabled($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sincronizar com o iCloud").font(.body).foregroundStyle(Color.textPrimary)
                            Text("Mantém seus aparelhos e a família em dia. Desligado por padrão.").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
                    .disabled(!store.syncConfigured)
                    .accessibilityIdentifier("settings.sync.toggle")
                    if store.preferences.syncEnabled {
                        RowSeparator()
                        HStack {
                            Text(statusText).font(.body).foregroundStyle(statusColor).accessibilityIdentifier("settings.sync.status")
                            Spacer()
                            Button("Sincronizar agora") { Task { await store.syncNow() } }
                                .buttonStyle(LinkButtonStyle()).disabled(store.syncStatus == .syncing)
                                .accessibilityIdentifier("settings.sync.now")
                        }
                        .padding(.horizontal, Space.lg).frame(minHeight: Space.rowMinHeight)
                    }
                }
                if !store.syncConfigured {
                    Label("Este build ainda não tem o iCloud configurado. Siga docs/cloudkit-setup.md no Xcode (capability, container e entitlements) e compile com CLOUDKIT_ENABLED.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("settings.sync.unconfigured")
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Como funciona")
                    Text("Os dados vão para o seu banco privado do iCloud, criptografado pela Apple. Em conflito, vale a alteração mais recente. Sem sincronizar, tudo continua somente neste aparelho.")
                        .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Convidar membros")
                    Text("O convite por link (CKShare) está apenas esboçado no código e ainda não foi testado. Hoje cada pessoa usa um perfil neste mesmo aparelho.")
                        .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Sincronização")
        .inlineNavigationTitle()
        .accessibilityIdentifier("settings.sync")
    }

    private var statusText: String {
        switch store.syncStatus {
        case .disabled: return "Desligada"
        case .syncing: return "Sincronizando…"
        case .failed(let m): return m
        case .idle(let last): return last.map { "Última vez: \(Fmt.date($0))" } ?? "Ainda não sincronizou"
        }
    }

    private var statusColor: Color {
        if case .failed = store.syncStatus { return .danger }
        return .textSecondary
    }
}

#Preview("Sincronização") {
    NavigationStack { SyncSettingsView() }.previewing(PreviewData.demo, dark: true)
}
