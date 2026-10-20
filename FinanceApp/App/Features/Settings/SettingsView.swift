import SwiftUI
import UniformTypeIdentifiers

/// Documento CSV para `fileExporter` ("Salvar em Arquivos").
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// settings: segurança, aparência, lembretes, exportar/importar e privacidade.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var exportURL: URL?
    @State private var exportDocument = CSVDocument(data: Data())
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var importSource: ImportSource?
    @State private var confirmErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                security
                appearance
                reminders
                familyAndPlanning
                data
                widgetsAndSiri
                privacy
                #if DEBUG
                NavigationLink { ComponentGallery() } label: {
                    Label("Galeria de componentes", systemImage: "square.grid.2x2")
                }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("settings.gallery")
                #endif
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Ajustes")
        .inlineNavigationTitle()
        .accessibilityIdentifier("settings")
        .task { refreshExport() }
        .onDisappear { if let exportURL { try? FileManager.default.removeItem(at: exportURL) }; exportURL = nil }
        .fileExporter(isPresented: $showsExporter, document: exportDocument, contentType: .commaSeparatedText,
                      defaultFilename: "lancamentos") { result in
            if case .failure(let e) = result { store.show("Não foi possível salvar: \(e.localizedDescription)", warning: true) }
            else { store.show("Arquivo salvo.") }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            handleImport(result)
        }
        .sheet(item: $importSource) { source in
            ImportPreviewSheet(source: source)
                .presentationDetents([.large])
                .presentationCornerRadius(Radius.sheet)
        }
        .confirmationDialog("Apagar todos os dados?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Apagar tudo", role: .destructive) { store.attempt { try store.eraseAllData() } }
        } message: {
            Text("Contas, lançamentos, cartões, orçamentos e metas serão removidos deste aparelho. Isso não pode ser desfeito.")
        }
    }

    // MARK: Seções

    private var security: some View {
        group("Segurança") {
            Toggle(isOn: Binding(get: { store.preferences.faceIDEnabled }, set: { setFaceID($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bloquear com \(BiometricAuth.displayName)").font(.body).foregroundStyle(Color.textPrimary)
                    Text("Usa o código do aparelho se a biometria falhar.").font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
            .accessibilityIdentifier("settings.faceid")
            RowSeparator()
            NavigationLink { PinSettingsView() } label: {
                settingsRow(store.preferences.pinEnabled ? "Código do app: ativo" : "Código próprio do app (opcional)", "number.square")
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings.pin.link")
            if store.appLockEnabled {
                RowSeparator()
                HStack {
                    Text("Bloquear após").font(.body).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("Bloquear após", selection: store.binding(\.lockDelay)) {
                        ForEach(LockDelay.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.lockDelay")
                }
                .padding(.horizontal, Space.lg).frame(minHeight: Space.rowMinHeight)
                RowSeparator()
                Button { store.lockNow() } label: {
                    Label("Bloquear agora", systemImage: "lock").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(LinkButtonStyle())
                .padding(.horizontal, Space.lg)
                .accessibilityIdentifier("settings.lockNow")
            }
        }
    }

    private var appearance: some View {
        group("Aparência") {
            Picker("Aparência", selection: store.binding(\.appearance)) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Space.lg)
            .accessibilityIdentifier("settings.appearance")
        }
    }

    private var reminders: some View {
        group("Lembretes") {
            Toggle(isOn: Binding(get: { store.preferences.remindersEnabled }, set: { setReminders($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lembrar de contas a pagar").font(.body).foregroundStyle(Color.textPrimary)
                    Text("Notificação às 9h.").font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
            .accessibilityIdentifier("settings.reminders")
            if store.preferences.remindersEnabled {
                RowSeparator()
                HStack {
                    Text("Avisar").font(.body).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("Antecedência", selection: Binding(get: { store.preferences.reminderDaysBefore }, set: { v in
                        store.updatePreferences { $0.reminderDaysBefore = v }
                        Task { await store.rescheduleReminders() }
                    })) {
                        Text("No dia").tag(0); Text("1 dia antes").tag(1); Text("2 dias antes").tag(2); Text("3 dias antes").tag(3)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.reminderDays")
                }
                .padding(.horizontal, Space.lg).frame(minHeight: Space.rowMinHeight)
            }
        }
    }

    private var familyAndPlanning: some View {
        group("Família e dados") {
            NavigationLink { FamilyView() } label: { settingsRow(store.hasHousehold ? "Família: \(store.household?.name ?? "")" : "Grupo familiar", "person.2") }
                .buttonStyle(.plain).accessibilityIdentifier("settings.family")
            RowSeparator()
            NavigationLink { CategoriesView() } label: { settingsRow("Categorias e despesas dedutíveis", "tag") }
                .buttonStyle(.plain).accessibilityIdentifier("settings.categories.link")
            RowSeparator()
            NavigationLink { SyncSettingsView() } label: {
                settingsRow(store.preferences.syncEnabled ? "Sincronização com o iCloud: ligada" : "Sincronização com o iCloud: desligada", "icloud")
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings.sync.link")
            RowSeparator()
            NavigationLink { OpenFinanceView() } label: {
                settingsRow(store.preferences.openFinanceEnabled ? "Open Finance: autorizado" : "Open Finance: desligado", "building.columns")
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings.openfinance.link")
        }
    }

    private var widgetsAndSiri: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Widgets e Siri")
            Text("Adicione os widgets Saldo, Gastos do dia e Próximo vencimento na tela de início. No app Atalhos ou com a Siri, use \"Adicionar despesa no Finanças\". Com o bloqueio ligado, o widget respeita Ocultar valores.")
                .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                .accessibilityIdentifier("settings.widgetsSiri")
        }
    }

    private var data: some View {
        group("Dados") {
            if let exportURL {
                ShareLink(item: exportURL) { settingsRow("Exportar CSV", "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.exportCSV")
            } else {
                settingsRow("Exportar CSV", "square.and.arrow.up")
            }
            RowSeparator()
            Button { prepareExporter() } label: { settingsRow("Salvar CSV em Arquivos", "folder") }
                .buttonStyle(.plain).accessibilityIdentifier("settings.exportFile")
            RowSeparator()
            Button { showsImporter = true } label: { settingsRow("Importar extrato (OFX ou CSV)", "square.and.arrow.down") }
                .buttonStyle(.plain).accessibilityIdentifier("settings.import")
            RowSeparator()
            Button {
                importSource = ImportSource(fileName: "extrato-exemplo.ofx", data: Data(SampleStatement.ofx.utf8))
            } label: { settingsRow("Usar extrato de exemplo", "doc.text") }
                .buttonStyle(.plain).accessibilityIdentifier("settings.importSample")
            RowSeparator()
            Button { confirmErase = true } label: {
                Label("Apagar todos os dados", systemImage: "trash").foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings.eraseAll")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Privacidade")
            Text(store.preferences.syncEnabled
                 ? "Seus dados ficam neste aparelho e, com a sincronização ligada, no seu banco privado do iCloud. O app não envia informações a servidores próprios, não usa rastreamento e não vende dados. Você pode exportar ou apagar tudo a qualquer momento, em linha com a LGPD."
                 : "Seus dados ficam apenas neste aparelho. O app não envia informações a servidores, não usa rastreamento e não vende dados. Você pode exportar ou apagar tudo a qualquer momento, em linha com a LGPD.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Space.xs)
                .accessibilityIdentifier("settings.privacy")
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            ListGroup { content() }
        }
    }

    private func settingsRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
            Text(title).font(.body).foregroundStyle(Color.textPrimary).multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(Space.lg).frame(minHeight: Space.rowMinHeight)
        .contentShape(Rectangle())
    }

    // MARK: Ações

    private func setFaceID(_ on: Bool) {
        guard on, !store.isUITesting else { store.updatePreferences { $0.faceIDEnabled = on }; return }
        Task {
            let ok = await BiometricAuth.authenticate(reason: "Ativar o bloqueio do app", biometricsOnly: false)
            if ok { store.updatePreferences { $0.faceIDEnabled = true } }
            else { store.show("Não foi possível ativar o bloqueio.", warning: true) }
        }
    }

    private func setReminders(_ on: Bool) {
        guard on, !store.isUITesting else {
            store.updatePreferences { $0.remindersEnabled = on }
            Task { await store.rescheduleReminders() }
            return
        }
        Task {
            let granted = await store.reminders.requestAuthorization()
            store.updatePreferences { $0.remindersEnabled = granted }
            if !granted { store.show("Ative as notificações do app em Ajustes do iPhone.", warning: true) }
            await store.rescheduleReminders()
        }
    }

    private func refreshExport() {
        exportURL = try? store.writeCSVExport()
    }

    private func prepareExporter() {
        exportDocument = CSVDocument(data: Data(store.csvText().utf8))
        showsExporter = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): store.show("Não foi possível abrir o arquivo: \(e.localizedDescription)", warning: true)
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { store.show("Não foi possível ler o arquivo.", warning: true); return }
            importSource = ImportSource(fileName: url.lastPathComponent, data: data)
        }
    }
}

/// Arquivo escolhido para importação (bytes + nome), antes de escolher a conta.
struct ImportSource: Identifiable {
    let id = UUID()
    let fileName: String
    let data: Data
}

/// settings.import.preview: revisa o que será importado, escolhe a conta e confirma.
struct ImportPreviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: ImportSource
    @State private var preview: ImportPreview?
    @State private var accountId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(source.fileName).font(.headline).foregroundStyle(Color.textPrimary).lineLimit(2)
                        if let preview {
                            Text(preview.summaryText).font(.subheadline).foregroundStyle(Color.textSecondary)
                                .accessibilityIdentifier("settings.import.summary")
                        }
                    }
                    if store.activeAccounts.isEmpty {
                        EmptyState(symbol: "building.columns", title: "Crie uma conta antes de importar")
                    } else {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader("Importar para")
                            FlowLayout {
                                ForEach(store.activeAccounts) { a in
                                    Chip(title: a.name, isSelected: accountId == a.id) { accountId = a.id }
                                        .accessibilityIdentifier("settings.import.account.\(a.name)")
                                }
                            }
                        }
                    }
                    if let preview {
                        if preview.isEmpty {
                            EmptyState(symbol: "doc.questionmark", title: "Nenhum lançamento encontrado no arquivo",
                                       message: preview.issues.first?.message)
                        } else {
                            candidatesList(preview)
                        }
                        Button("Importar \(preview.newCount) \(preview.newCount == 1 ? "lançamento" : "lançamentos")") { commit(preview) }
                            .buttonStyle(.primary)
                            .disabled(preview.newCount == 0 || accountId == nil)
                            .accessibilityIdentifier("settings.import.confirm")
                    }
                }
                .padding(Space.screenMargin)
            }
            .background(Color.canvas)
            .navigationTitle("Importar extrato")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear {
            accountId = accountId ?? store.activeAccounts.first?.id
            refresh()
        }
        .onChange(of: accountId) { _, _ in refresh() }
        .toastHost()
        .accessibilityIdentifier("settings.import.preview")
    }

    /// A detecção de duplicadas depende da conta escolhida.
    private func refresh() {
        preview = store.prepareImport(fileName: source.fileName, data: source.data, accountId: accountId)
    }

    private func candidatesList(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ListGroup {
                ForEach(Array(preview.candidates.enumerated()), id: \.offset) { index, c in
                    ListRow(title: c.title, subtitle: DateText.dayMonthShort(c.date) + (c.isDuplicate ? " · Repetida, será ignorada" : "")) {
                        Image(systemName: c.isDuplicate ? "doc.on.doc" : "plus.circle")
                            .foregroundStyle(c.isDuplicate ? Color.textTertiary : Color.brandPrimary).frame(width: 28)
                            .accessibilityHidden(true)
                    } trailing: {
                        AmountText(c.amount.magnitude, sign: c.amount < 0 ? .expense : .income, role: c.amount < 0 ? .expense : .income)
                    }
                    .opacity(c.isDuplicate ? 0.55 : 1)
                    .accessibilityElement(children: .combine)
                    if index < preview.candidates.count - 1 { RowSeparator(inset: 56) }
                }
            }
            if !preview.issues.isEmpty {
                Text("\(preview.issues.count) \(preview.issues.count == 1 ? "linha ignorada" : "linhas ignoradas") por erro de formato.")
                    .font(.footnote).foregroundStyle(Color.warning)
            }
        }
    }

    private func commit(_ preview: ImportPreview) {
        guard let accountId else { return }
        if store.attempt({ _ = try store.commitImport(preview, accountId: accountId) }) {
            store.show(preview.summaryText + ".")
            dismiss()
        }
    }
}

#Preview("Ajustes") {
    NavigationStack { SettingsView() }.previewing(PreviewData.demo)
}

#Preview("Ajustes, escuro, bloqueio e lembretes ativos") {
    let store = PreviewData.demo
    NavigationStack { SettingsView() }.previewing(store, dark: true)
        .onAppear { store.updatePreferences { $0.faceIDEnabled = true; $0.remindersEnabled = true } }
}

#Preview("Ajustes sem dados, texto grande") {
    NavigationStack { SettingsView() }.previewing(PreviewData.empty).dynamicTypeSize(.accessibility2)
}

#Preview("Importar extrato") {
    ImportPreviewSheet(source: ImportSource(fileName: "extrato.ofx", data: Data(SampleStatement.ofx.utf8)))
        .previewing(PreviewData.empty)
}

#Preview("Importar extrato vazio") {
    ImportPreviewSheet(source: ImportSource(fileName: "vazio.csv", data: Data("foo;bar\n".utf8)))
        .previewing(PreviewData.empty, dark: true)
}
