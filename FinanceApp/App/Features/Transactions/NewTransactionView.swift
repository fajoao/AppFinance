import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// transaction.new: lançamento em poucos toques, com teclado numérico próprio e painéis para conta/cartão,
/// destino, data, repetição e tag.
struct NewTransactionView: View {
    enum Panel: String { case account, destination, date, repeatRule, tag, member, attachment }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    let initialType: TransactionType
    let initialDate: Date?
    /// Id do lançamento em edição (nil = novo).
    let editingId: UUID?

    @State private var draft = TransactionDraft(date: FinanceCalendar.normalize(Date()))
    @State private var didSetup = false
    @State private var panel: Panel?
    @State private var errorText: String?
    @State private var newTagName = ""
    @State private var attachmentError: String?
    @State private var showsScan = false
    #if canImport(PhotosUI)
    @State private var pickedPhoto: PhotosPickerItem?
    #endif
    @FocusState private var titleFocused: Bool

    init(type: TransactionType = .expense, date: Date? = nil, editing id: UUID? = nil) {
        self.initialType = type
        self.initialDate = date
        self.editingId = id
    }

    private var isEditing: Bool { editingId != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    amountBlock
                    titleField
                    if draft.type != .transfer { categoryChips }
                    pills
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote).foregroundStyle(Color.danger)
                            .accessibilityIdentifier("transaction.new.error")
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            Button(draft.saveTitle, action: save)
                .buttonStyle(.primary)
                .disabled(!draft.canSave)
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.sm)
                .accessibilityIdentifier("transaction.new.save")
            bottomArea
        }
        .background(Color.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear(perform: setup)
        .sheet(isPresented: $showsScan) {
            ScanReceiptView { prefill in
                draft = store.makeDraft(applying: prefill)
                if store.isAlreadyRecorded(externalId: prefill.externalId) { store.show("Este documento já foi lançado antes.", warning: true) }
            }
            .presentationDetents([.large])
        }
        .onChange(of: draft.title) { _, _ in
            let kind: CategoryKind = draft.type == .income ? .income : .expense
            draft.descriptionChanged(suggester: store.suggester(for: draft.type)) { store.lookup.categories[$0]?.kind == kind }
        }
        .accessibilityElement(children: .contain)
        .toastHost()
        .accessibilityIdentifier(isEditing ? "transaction.edit" : "transaction.new")
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let editingId {
            if let d = try? store.draft(editing: editingId) { draft = d } else { store.show("Lançamento não encontrado.", warning: true); dismiss() }
        } else {
            draft = store.makeDraft(type: initialType, date: initialDate)
            if router.opensScanner { router.opensScanner = false; showsScan = true }
        }
    }

    // MARK: Partes

    private var topBar: some View {
        HStack(spacing: Space.md) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Fechar")
                .accessibilityIdentifier("transaction.new.close")
            if isEditing {
                Text("Editar lançamento").font(.headline).foregroundStyle(Color.textPrimary).frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Color.clear.frame(width: 44, height: 44)
            } else {
                Picker("Tipo", selection: Binding(get: { draft.type }, set: { draft.changeType($0); panel = nil })) {
                    Text("Despesa").tag(TransactionType.expense)
                    Text("Receita").tag(TransactionType.income)
                    Text("Transferência").tag(TransactionType.transfer)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transaction.new.type")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.sm)
    }

    private var amountColor: Color {
        switch draft.type {
        case .expense: return .textPrimary
        case .income: return .income
        case .transfer: return .transfer
        }
    }

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(draft.type == .income ? "Valor recebido" : (draft.type == .transfer ? "Valor transferido" : "Valor gasto"))
                .font(.subheadline).foregroundStyle(Color.textSecondary)
            AmountEntryDisplay(keypad: draft.keypad, color: amountColor)
            if let summary = draft.installmentSummary() {
                Text(summary).font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
                    .accessibilityIdentifier("transaction.new.installmentSummary")
            }
        }
        .padding(.top, Space.sm)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField(draft.type == .transfer ? "Descrição (opcional)" : "Descrição (ex.: Padaria)", text: $draft.title)
                .font(.body)
                .sentenceCapitalization()
                .submitLabel(.done)
                .focused($titleFocused)
                .onSubmit { titleFocused = false }
                .padding(.horizontal, Space.md)
                .frame(minHeight: Space.minTouchTarget)
                .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .accessibilityIdentifier("transaction.new.title")
            if draft.categoryIsSuggested, let id = draft.categoryId {
                Label("Categoria sugerida: \(store.lookup.categoryName(id))", systemImage: "sparkles")
                    .font(.footnote).foregroundStyle(Color.brandPrimary)
                    .accessibilityIdentifier("transaction.new.suggestion")
            }
        }
    }

    private var categories: [Category] { draft.type == .income ? store.incomeCategories : store.expenseCategories }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(categories) { c in
                    Chip(title: c.name, systemImage: c.icon, isSelected: draft.categoryId == c.id) {
                        draft.chooseCategory(draft.categoryId == c.id ? nil : c.id)
                    }
                    .accessibilityIdentifier("transaction.new.category.\(c.name)")
                }
            }
        }
        .accessibilityIdentifier("transaction.new.categories")
    }

    private var pills: some View {
        FlowLayout(spacing: Space.sm) {
            pill(.account, systemImage: sourceIsCard ? "creditcard" : "building.columns",
                 title: draft.type == .transfer ? "De: \(sourceName)" : sourceName, id: "account")
            if draft.type == .transfer {
                pill(.destination, systemImage: "arrow.right", title: "Para: \(destinationName)", id: "destination")
            }
            pill(.date, systemImage: "calendar", title: dateLabel, id: "date")
            if !isEditing {
                pill(.repeatRule, systemImage: "repeat", title: draft.repeatRule.title, id: "repeat")
            }
            pill(.tag, systemImage: "tag", title: tagLabel, id: "tag")
            if showsMemberPill {
                pill(.member, systemImage: "person", title: memberLabel, id: "member")
            }
            pill(.attachment, systemImage: "paperclip", title: draft.attachmentPath == nil ? "Comprovante" : "Comprovante anexado", id: "attachment")
            if !isEditing {
                Chip(title: "Ler nota", systemImage: "doc.viewfinder", isSelected: false) { titleFocused = false; showsScan = true }
                    .accessibilityIdentifier("transaction.new.scan")
            }
        }
    }

    private func pill(_ p: Panel, systemImage: String, title: String, id: String) -> some View {
        Chip(title: title, systemImage: systemImage, isSelected: panel == p) {
            titleFocused = false
            panel = panel == p ? nil : p
        }
        .accessibilityIdentifier("transaction.new.pill.\(id)")
    }

    // MARK: Rótulos

    private var sourceIsCard: Bool { if case .card = draft.source { return true } else { return false } }

    private var sourceName: String {
        switch draft.source {
        case .account(let id)?: return store.lookup.accounts[id]?.name ?? "Conta"
        case .card(let id)?: return store.lookup.cards[id]?.name ?? "Cartão"
        case nil: return "Escolher conta"
        }
    }

    private var destinationName: String {
        draft.destinationAccountId.flatMap { store.lookup.accounts[$0]?.name } ?? "Escolher"
    }

    private var dateLabel: String {
        switch FinanceCalendar.daysBetween(draft.date, store.today) {
        case 0: return "Hoje"
        case 1: return "Ontem"
        case -1: return "Amanhã"
        default: return DateText.dayMonthShort(draft.date)
        }
    }

    private var showsMemberPill: Bool {
        store.hasHousehold && draft.type != .transfer && (store.activeMember.map { $0.role != .dependent } ?? false)
    }

    private var memberLabel: String { store.lookup.memberName(draft.memberId) == "Sem membro" ? "Quem" : store.lookup.memberName(draft.memberId) }

    private var tagLabel: String {
        let names = draft.tagIds.compactMap { store.lookup.tags[$0]?.name }
        return names.isEmpty ? "Tag" : names.map { "#\($0)" }.joined(separator: " ")
    }

    // MARK: Parte de baixo: teclado ou painel

    @ViewBuilder
    private var bottomArea: some View {
        if let panel {
            VStack(spacing: 0) {
                HStack {
                    Text(panelTitle(panel)).font(.headline).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button("Concluir") { self.panel = nil }
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("transaction.new.panel.done")
                }
                .padding(.horizontal, Space.screenMargin)
                ScrollView { panelContent(panel).padding(Space.screenMargin) }
                    .frame(maxHeight: 340)
            }
            .padding(.top, Space.sm)
            .background(Color.surfaceRaised)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transaction.new.panel.\(panel.rawValue)")
        } else if !titleFocused {
            NumericKeypad { key in
                draft.keypad.press(key)
                errorText = nil
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transaction.new.keypad")
        }
    }

    private func panelTitle(_ p: Panel) -> String {
        switch p {
        case .account: return draft.type == .expense ? "Conta ou cartão" : "Conta"
        case .destination: return "Conta de destino"
        case .date: return "Data"
        case .repeatRule: return "Repetir"
        case .tag: return "Tags"
        case .member: return "Quem gastou ou recebeu"
        case .attachment: return "Comprovante"
        }
    }

    @ViewBuilder
    private func panelContent(_ p: Panel) -> some View {
        switch p {
        case .account: accountPanel
        case .destination: destinationPanel
        case .date: datePanel
        case .repeatRule: repeatPanel
        case .tag: tagPanel
        case .member: memberPanel
        case .attachment: attachmentPanel
        }
    }

    private var accountPanel: some View {
        ListGroup {
            SeparatedRows(items: store.activeAccounts) { a in
                optionRow(title: a.name, subtitle: "Saldo \(store.money(store.balance(of: a)))",
                          selected: draft.source == .account(a.id), id: "transaction.new.account.\(a.name)") {
                    draft.source = .account(a.id); panel = nil
                }
            }
            if draft.type == .expense && !store.activeCards.isEmpty {
                RowSeparator()
                SeparatedRows(items: store.activeCards) { c in
                    optionRow(title: c.name, subtitle: "Disponível \(store.money(store.cardOverview(c).available))",
                              selected: draft.source == .card(c.id), id: "transaction.new.card.\(c.name)") {
                        draft.source = .card(c.id); panel = nil
                    }
                }
            }
        }
    }

    private var destinationPanel: some View {
        let sourceId: UUID? = { if case .account(let id)? = draft.source { return id } else { return nil } }()
        return ListGroup {
            SeparatedRows(items: store.activeAccounts.filter { $0.id != sourceId }) { a in
                optionRow(title: a.name, subtitle: "Saldo \(store.money(store.balance(of: a)))",
                          selected: draft.destinationAccountId == a.id, id: "transaction.new.destination.\(a.name)") {
                    draft.destinationAccountId = a.id; panel = nil
                }
            }
        }
    }

    private var datePanel: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                ForEach([(0, "Hoje"), (1, "Ontem"), (2, "Anteontem")], id: \.0) { offset, title in
                    let date = FinanceCalendar.addDays(store.today, -offset)
                    Chip(title: title, isSelected: FinanceCalendar.isSameDay(draft.date, date)) { draft.date = date }
                        .accessibilityIdentifier("transaction.new.date.\(offset)")
                }
            }
            DatePicker("Data", selection: Binding(get: { draft.date }, set: { newValue in
                let c = FinanceCalendar.components(newValue)
                draft.date = FinanceCalendar.date(c.year, c.month, c.day)
            }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, FinanceCalendar.calendar)
                .environment(\.timeZone, FinanceCalendar.calendar.timeZone)
                .accessibilityIdentifier("transaction.new.date.picker")
            if FinanceCalendar.isBeforeDay(store.today, draft.date) {
                Label("Data futura: entra em Contas a pagar como pendente.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var repeatPanel: some View {
        let installments: Int = { if case .installments(let n) = draft.repeatRule { return n }; return 2 }()
        return VStack(alignment: .leading, spacing: Space.md) {
            ListGroup {
                optionRow(title: "Não repete", subtitle: nil, selected: draft.repeatRule == .none, id: "transaction.new.repeat.none") {
                    draft.repeatRule = .none
                }
                RowSeparator()
                optionRow(title: "Todo mês", subtitle: "Gera os próximos meses como pendentes", selected: draft.repeatRule == .monthly,
                          id: "transaction.new.repeat.monthly") { draft.repeatRule = .monthly }
                RowSeparator()
                optionRow(title: "Toda semana", subtitle: nil, selected: draft.repeatRule == .weekly, id: "transaction.new.repeat.weekly") {
                    draft.repeatRule = .weekly
                }
                if draft.type == .expense {
                    RowSeparator()
                    optionRow(title: "Parcelado", subtitle: draft.installmentSummary() ?? "De 2 a 24 parcelas",
                              selected: { if case .installments = draft.repeatRule { return true } else { return false } }(),
                              id: "transaction.new.repeat.installments") { draft.repeatRule = .installments(installments) }
                }
            }
            if case .installments = draft.repeatRule {
                Stepper(value: Binding(get: { installments }, set: { draft.repeatRule = .installments($0) }),
                        in: TransactionDraft.Repeat.installmentRange) {
                    Text("\(installments) parcelas").font(.body).monospacedDigit()
                }
                .accessibilityIdentifier("transaction.new.repeat.stepper")
            }
        }
    }

    private var tagPanel: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if !store.tags.isEmpty {
                FlowLayout {
                    ForEach(store.tags) { tag in
                        Chip(title: "#" + tag.name, isSelected: draft.tagIds.contains(tag.id)) {
                            if let i = draft.tagIds.firstIndex(of: tag.id) { draft.tagIds.remove(at: i) } else { draft.tagIds.append(tag.id) }
                        }
                    }
                }
            }
            HStack(spacing: Space.sm) {
                TextField("Nova tag", text: $newTagName)
                    .noAutocapitalization()
                    .padding(.horizontal, Space.md)
                    .frame(minHeight: Space.minTouchTarget)
                    .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityIdentifier("transaction.new.tag.field")
                Button("Adicionar") {
                    store.attempt {
                        let tag = try store.createTag(named: newTagName)
                        if !draft.tagIds.contains(tag.id) { draft.tagIds.append(tag.id) }
                        newTagName = ""
                    }
                }
                .buttonStyle(LinkButtonStyle())
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("transaction.new.tag.add")
            }
        }
    }

    private var memberPanel: some View {
        ListGroup {
            SeparatedRows(items: store.members) { m in
                optionRow(title: m.name, subtitle: m.role.title, selected: draft.memberId == m.id, id: "transaction.new.member.\(m.name)") {
                    draft.memberId = m.id; panel = nil
                }
            }
        }
    }

    private var attachmentPanel: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let path = draft.attachmentPath, let data = store.attachmentData(path) {
                DataImage(data: data).frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .accessibilityLabel("Comprovante anexado")
                Button("Remover comprovante") { draft.attachmentPath = nil }
                    .buttonStyle(LinkButtonStyle(tone: .danger)).accessibilityIdentifier("transaction.new.attachment.remove")
            }
            #if canImport(PhotosUI)
            let pickTitle = draft.attachmentPath == nil ? "Escolher foto do comprovante" : "Trocar foto"
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label(pickTitle, systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("transaction.new.attachment.pick")
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        do { draft.attachmentPath = try store.attachImage(data); attachmentError = nil }
                        catch { attachmentError = "Não foi possível salvar a foto." }
                    } else { attachmentError = "Não foi possível ler a foto." }
                    pickedPhoto = nil
                }
            }
            #else
            Text("Anexar fotos não está disponível nesta plataforma.").font(.footnote).foregroundStyle(Color.textSecondary)
            #endif
            if let attachmentError { Label(attachmentError, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger) }
            Text("A foto fica só neste aparelho, dentro do app.").font(.footnote).foregroundStyle(Color.textSecondary)
        }
    }

    private func optionRow(title: String, subtitle: String?, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(title: title, subtitle: subtitle) { EmptyView() } trailing: {
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary).accessibilityHidden(true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: Salvar

    private func save() {
        errorText = nil
        if let e = draft.validate() { errorText = e.message; return }
        if isEditing {
            if store.attempt({ try store.update(draft) }) {
                Haptics.success()
                store.show("Lançamento atualizado.")
                dismiss()
            }
            return
        }
        var outcome: SubmitOutcome?
        if store.attempt({ outcome = try store.submit(draft) }) {
            Haptics.success()
            switch outcome {
            case .awaitingApproval: store.show("Passou do seu limite. Enviado para aprovação.", warning: true)
            case .saved(let events)?: if events.isEmpty { store.show("Lançamento salvo.") }
            case nil: break
            }
            dismiss()
        }
    }
}

#Preview("Novo lançamento") {
    NewTransactionView().previewing(PreviewData.demo).environment(Router())
}

#Preview("Novo lançamento, escuro, transferência") {
    NewTransactionView(type: .transfer).previewing(PreviewData.demo, dark: true).environment(Router())
}

#Preview("Novo lançamento sem dados") {
    NewTransactionView(type: .income).previewing(PreviewData.empty).environment(Router())
}

#Preview("Editar lançamento") {
    let store = PreviewData.demo
    NewTransactionView(editing: store.transactions.first(where: { $0.type == .expense && !$0.isInvoicePayment })?.id).previewing(store).environment(Router())
}

#Preview("Novo lançamento, texto grande") {
    NewTransactionView().previewing(PreviewData.demo).environment(Router()).dynamicTypeSize(.accessibility2)
}
