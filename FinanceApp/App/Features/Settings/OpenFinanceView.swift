import SwiftUI

/// settings.openfinance: explica o Open Finance e pede consentimento. DESLIGADO por padrão e sem provedor real:
/// a integração exige contrato, credenciais e um backend (docs/open-finance.md). Com `-mockOpenFinance` usa dados fictícios.
struct OpenFinanceView: View {
    @Environment(AppStore.self) private var store
    @State private var showsRevokeConfirm = false

    private var model: OpenFinanceModel { store.openFinance }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                intro
                consent
                if model.isAvailable && store.preferences.openFinanceEnabled { connection }
                if let text = model.errorText {
                    Label(text, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger)
                        .accessibilityIdentifier("openfinance.error")
                }
                rights
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Open Finance")
        .inlineNavigationTitle()
        .accessibilityIdentifier("openfinance")
        .confirmationDialog("Revogar o consentimento?", isPresented: $showsRevokeConfirm, titleVisibility: .visible) {
            Button("Revogar", role: .destructive) { Task { await model.revoke() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("O banco deixa de compartilhar dados com o app. Os lançamentos já importados continuam aqui.") }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label("Importar contas e extratos do seu banco", systemImage: "building.columns").font(.headline).foregroundStyle(Color.textPrimary)
            Text("O Open Finance é o sistema regulado pelo Banco Central em que você autoriza um banco a compartilhar seus dados. Com ele o app poderia trazer saldos e transações sem você importar arquivos OFX ou CSV.")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
            if !model.isAvailable {
                Label("Ainda não disponível neste app: nenhum provedor está integrado. A integração exige contrato com um provedor autorizado e um servidor próprio para guardar credenciais. Por enquanto, importe seu extrato em Ajustes > Importar (OFX ou CSV).",
                      systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("openfinance.unavailable")
            } else {
                Label("Modo demonstração: bancos e transações FICTÍCIOS, só para testar a tela.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Color.warning)
                    .accessibilityIdentifier("openfinance.mockBanner")
            }
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("O que você estaria autorizando")
            ListGroup {
                ForEach(Array(ConsentScope.allCases.enumerated()), id: \.element) { index, scope in
                    ListRow(title: scope.displayName) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                    } trailing: { EmptyView() }
                    if index < ConsentScope.allCases.count - 1 { RowSeparator(inset: 56) }
                }
            }
            Text("Finalidade: importar contas e transações para o seu controle financeiro pessoal. Validade padrão de 90 dias (o máximo permitido é 12 meses). Você pode revogar quando quiser, no app e no banco. Os dados ficam só neste aparelho; o app não vende nem usa para publicidade (LGPD).")
                .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                .accessibilityIdentifier("openfinance.terms")
            ListGroup {
                Toggle(isOn: Binding(get: { store.preferences.openFinanceEnabled }, set: { store.setOpenFinanceEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Li e autorizo o uso do Open Finance").font(.body).foregroundStyle(Color.textPrimary)
                        Text("Desligado por padrão.").font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
                .disabled(!model.isAvailable)
                .accessibilityIdentifier("openfinance.toggle")
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Bancos")
            if let c = model.connection {
                ListGroup {
                    ListRow(title: c.institutionName, subtitle: "\(c.status.displayName), válida até \(Fmt.date(c.expiresAt))") {
                        Image(systemName: "building.columns").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                    } trailing: { EmptyView() }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("openfinance.status")
                    if c.status == .active {
                        RowSeparator(inset: 56)
                        Button { Task { await model.syncNow(into: store) } } label: { actionRow("arrow.triangle.2.circlepath", "Importar últimos 30 dias") }
                            .buttonStyle(.plain).disabled(model.isWorking).accessibilityIdentifier("openfinance.sync")
                        RowSeparator(inset: 56)
                        Button { showsRevokeConfirm = true } label: { actionRow("hand.raised", "Revogar consentimento", color: .danger) }
                            .buttonStyle(.plain).accessibilityIdentifier("openfinance.revoke")
                    } else {
                        RowSeparator(inset: 56)
                        Button { model.forgetConnection() } label: { actionRow("xmark.circle", "Remover conexão") }
                            .buttonStyle(.plain).accessibilityIdentifier("openfinance.forget")
                    }
                }
                if let o = model.lastOutcome {
                    Text("Importadas: \(o.imported.count). Já existiam: \(o.duplicateCount). Prováveis duplicatas (não importadas): \(o.probableDuplicates.count). Ignoradas (pendentes ou em outra moeda): \(o.skippedCount).")
                        .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                        .accessibilityIdentifier("openfinance.result")
                }
            } else {
                ListGroup {
                    if model.institutions.isEmpty {
                        Button { Task { await model.loadInstitutions() } } label: { actionRow("magnifyingglass", "Buscar bancos") }
                            .buttonStyle(.plain).accessibilityIdentifier("openfinance.load")
                    } else {
                        ForEach(Array(model.institutions.enumerated()), id: \.element.id) { index, inst in
                            Button { Task { await model.connect(institutionId: inst.id) } } label: { actionRow("link", "Conectar \(inst.name)") }
                                .buttonStyle(.plain).disabled(model.isWorking).accessibilityIdentifier("openfinance.institution.\(inst.id)")
                            if index < model.institutions.count - 1 { RowSeparator(inset: 56) }
                        }
                    }
                }
            }
            if model.isWorking { ProgressView().accessibilityIdentifier("openfinance.working") }
        }
    }

    private func actionRow(_ symbol: String, _ title: String, color: Color = .brandPrimary) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28).accessibilityHidden(true)
            Text(title).font(.body).foregroundStyle(color == .danger ? Color.danger : Color.textPrimary)
            Spacer()
        }
        .padding(Space.lg).frame(minHeight: Space.rowMinHeight).contentShape(Rectangle())
    }

    private var rights: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Seus direitos")
            Text("Você pode revogar o consentimento a qualquer momento, apagar os dados importados (Ajustes > Apagar todos os dados) e exportar tudo em CSV. O app nunca guarda a senha do seu banco: a autorização acontece no ambiente do próprio banco.")
                .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
        }
    }
}

#Preview("Open Finance, sem provedor") {
    NavigationStack { OpenFinanceView() }.previewing(PreviewData.demo)
}

#Preview("Open Finance, sem provedor, escuro") {
    NavigationStack { OpenFinanceView() }.previewing(PreviewData.demo, dark: true)
}

#Preview("Open Finance, demonstração") {
    NavigationStack { OpenFinanceView() }.previewing(PreviewData.openFinanceMock)
}
