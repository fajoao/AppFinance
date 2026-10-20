import SwiftUI

/// family.settle: despesas divididas, saldo de cada pessoa e as transferências mínimas para acertar as contas.
struct SettlementView: View {
    @Environment(AppStore.self) private var store
    @State private var showsSplit = false

    private func name(_ id: UUID) -> String { store.lookup.memberName(id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                balances
                plan
                history
                Button { showsSplit = true } label: { Label("Dividir uma despesa", systemImage: "plus") }
                    .buttonStyle(.primary)
                    .disabled(store.members.count < 2 || !(store.activeMember.map { FamilyEngine.can($0.role, .splitExpenses) } ?? false))
                    .accessibilityIdentifier("family.split.add")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Acerto de contas")
        .inlineNavigationTitle()
        .sheet(isPresented: $showsSplit) { SplitExpenseSheet().presentationDetents([.large]).presentationCornerRadius(Radius.sheet) }
        .accessibilityIdentifier("family.settle")
    }

    private var balances: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Saldo de cada pessoa")
            ListGroup {
                SeparatedRows(items: store.members, inset: 56) { m in
                    let b = store.splitBalances[m.id] ?? 0
                    ListRow(title: m.name, subtitle: b > 0 ? "tem a receber" : (b < 0 ? "deve" : "em dia")) {
                        Image(systemName: m.role.symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                    } trailing: { AmountText(balance: b) }
                    .accessibilityIdentifier("family.settle.balance.\(m.name)")
                }
            }
        }
    }

    private var plan: some View {
        let transfers = store.settlementPlan
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Para zerar as contas")
            if transfers.isEmpty {
                Label("Tudo acertado.", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Color.income)
                    .padding(.horizontal, Space.xs).accessibilityIdentifier("family.settle.allClear")
            } else {
                ListGroup {
                    ForEach(Array(transfers.enumerated()), id: \.offset) { index, t in
                        ListRow(title: "\(name(t.from)) paga \(store.money(t.amount)) a \(name(t.to))") {
                            Image(systemName: "arrow.right.circle").foregroundStyle(Color.transfer).frame(width: 28).accessibilityHidden(true)
                        } trailing: {
                            Button("Já paguei") { store.attempt { try store.settle(t) } }
                                .buttonStyle(LinkButtonStyle())
                                .accessibilityIdentifier("family.settle.paid.\(index)")
                        }
                        if index < transfers.count - 1 { RowSeparator(inset: 56) }
                    }
                }
                Text("São \(transfers.count) \(transfers.count == 1 ? "transferência" : "transferências") no total, o menor número que o método garante.")
                    .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Despesas divididas")
            if store.splits.isEmpty {
                Text("Nenhuma despesa dividida ainda.").font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            } else {
                ListGroup {
                    SeparatedRows(items: store.splits) { s in
                        ListRow(title: s.title, subtitle: "\(Fmt.date(s.date)), pago por \(name(s.paidBy)), \(s.mode.displayName.lowercased())") { EmptyView() } trailing: {
                            Text(store.money(s.total)).font(.body).monospacedDigit().foregroundStyle(Color.textPrimary)
                        }
                        .contextMenu {
                            Button("Excluir divisão", role: .destructive) { store.attempt { try store.deleteSplit(id: s.id) } }
                        }
                        .accessibilityIdentifier("family.settle.split.\(s.title)")
                    }
                }
            }
        }
    }
}

/// family.split: dividir uma despesa entre membros (igual ou percentual).
struct SplitExpenseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SplitDraft(date: FinanceCalendar.normalize(Date()))
    @State private var showErrors = false
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "O que foi", text: $draft.title, prompt: "Ex.: Mercado do mês",
                                 error: showErrors ? draft.titleError : nil, identifier: "family.split.title")
                    LabeledField(label: "Valor total", text: $draft.totalText, prompt: "0,00",
                                 error: showErrors ? draft.totalError : nil, isDecimal: true, identifier: "family.split.total")
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Quem pagou")
                        FlowLayout {
                            ForEach(store.members) { m in
                                Chip(title: m.name, isSelected: draft.paidBy == m.id) { draft.paidBy = m.id }
                                    .accessibilityIdentifier("family.split.paidBy.\(m.name)")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Quem divide")
                        FlowLayout {
                            ForEach(store.members) { m in
                                Chip(title: m.name, isSelected: draft.participants.contains(m.id)) {
                                    if draft.participants.contains(m.id) { draft.participants.remove(m.id) } else { draft.participants.insert(m.id) }
                                    if draft.mode == .percentage { draft.fillEvenPercentages(store.members) }
                                }
                                .accessibilityIdentifier("family.split.with.\(m.name)")
                            }
                        }
                        if showErrors, let e = draft.participantsError {
                            Label(e, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger)
                        }
                    }
                    Picker("Divisão", selection: Binding(get: { draft.mode }, set: { m in
                        draft.mode = m
                        if m == .percentage { draft.fillEvenPercentages(store.members) }
                    })) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("family.split.mode")
                    if draft.mode == .percentage { percentFields }
                    preview
                    Toggle("Lançar também como despesa", isOn: $draft.createsTransaction).accessibilityIdentifier("family.split.createTx")
                    if draft.createsTransaction {
                        FlowLayout {
                            ForEach(store.activeAccounts) { a in
                                Chip(title: a.name, isSelected: draft.accountId == a.id) { draft.accountId = a.id }
                            }
                        }
                    }
                    Button("Dividir") { save() }.buttonStyle(.primary).accessibilityIdentifier("family.split.save")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Dividir despesa")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            draft = SplitDraft(date: store.today, members: store.members, paidBy: store.activeMember?.id)
            draft.accountId = store.activeAccounts.first?.id
        }
        .toastHost()
        .accessibilityIdentifier("family.split")
    }

    private var percentFields: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Percentual de cada um")
            ForEach(store.members.filter { draft.participants.contains($0.id) }) { m in
                LabeledField(label: m.name, text: Binding(get: { draft.percentTexts[m.id] ?? "" }, set: { draft.percentTexts[m.id] = $0 }),
                             prompt: "0", isDecimal: true, identifier: "family.split.percent.\(m.name)")
            }
            let sum = draft.percentSum(store.members)
            Text("Soma: \(Fmt.percent(sum, scale: 2))").font(.footnote).foregroundStyle(sum == 100 ? Color.textSecondary : Color.danger).monospacedDigit()
                .accessibilityIdentifier("family.split.percentSum")
        }
    }

    @ViewBuilder
    private var preview: some View {
        let shares = draft.preview(members: store.members)
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Cada um paga")
                ListGroup {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, s in
                        ListRow(title: store.lookup.memberName(s.memberId)) { EmptyView() } trailing: {
                            Text(store.money(s.amount)).font(.body).monospacedDigit().foregroundStyle(Color.textPrimary)
                        }
                        if index < shares.count - 1 { RowSeparator() }
                    }
                }
            }
            .accessibilityIdentifier("family.split.preview")
        }
    }

    private func save() {
        guard draft.titleError == nil, draft.totalError == nil, draft.participantsError == nil else { showErrors = true; return }
        if store.attempt({ _ = try store.addSplit(draft) }) { Haptics.success(); store.show("Despesa dividida."); dismiss() }
    }
}

/// family.allowance: mesadas dos dependentes.
struct AllowanceView: View {
    @Environment(AppStore.self) private var store
    @State private var showsNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if store.allowances.isEmpty {
                    EmptyState(symbol: "calendar.badge.clock", title: "Nenhuma mesada",
                               message: "A mesada é transferida todo mês da sua conta para a conta do dependente, no dia combinado.")
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    ListGroup {
                        SeparatedRows(items: store.allowances) { a in
                            ListRow(title: store.lookup.memberName(a.memberId),
                                    subtitle: "Todo dia \(a.dayOfMonth), de \(store.lookup.accounts[a.fromAccountId]?.name ?? "conta") para \(store.lookup.accounts[a.toAccountId]?.name ?? "conta")") {
                                Image(systemName: "calendar.badge.clock").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                            } trailing: { Text(store.money(a.amount)).font(.body).monospacedDigit().foregroundStyle(Color.textPrimary) }
                            .contextMenu { Button("Encerrar mesada", role: .destructive) { store.attempt { try store.removeAllowance(id: a.id) } } }
                            .accessibilityIdentifier("family.allowance.row.\(store.lookup.memberName(a.memberId))")
                        }
                    }
                }
                Button { showsNew = true } label: { Label("Nova mesada", systemImage: "plus") }
                    .buttonStyle(.primary)
                    .disabled(store.dependents.isEmpty || !(store.activeMember.map { FamilyEngine.can($0.role, .manageAllowances) } ?? false))
                    .accessibilityIdentifier("family.allowance.add")
                if store.dependents.isEmpty {
                    Text("Adicione um dependente para criar a mesada.").font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Mesada")
        .inlineNavigationTitle()
        .sheet(isPresented: $showsNew) { AllowanceFormSheet().presentationDetents([.large]).presentationCornerRadius(Radius.sheet) }
        .accessibilityIdentifier("family.allowance")
    }
}

struct AllowanceFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AllowanceDraft()
    @State private var showErrors = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Para quem")
                        FlowLayout {
                            ForEach(store.dependents) { m in
                                Chip(title: m.name, isSelected: draft.memberId == m.id) { draft.memberId = m.id }
                                    .accessibilityIdentifier("family.allowance.form.member.\(m.name)")
                            }
                        }
                    }
                    LabeledField(label: "Valor por mês", text: $draft.amountText, prompt: "0,00",
                                 error: showErrors ? draft.amountError : nil, isDecimal: true, identifier: "family.allowance.form.amount")
                    LabeledField(label: "Dia do mês", text: $draft.dayText, prompt: "5",
                                 error: showErrors ? draft.dayError : nil, isDecimal: true, identifier: "family.allowance.form.day")
                    accountPicker("Sai de", selection: $draft.fromAccountId, id: "from")
                    accountPicker("Cai em", selection: $draft.toAccountId, id: "to")
                    if showErrors, let e = draft.accountsError { Label(e, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger) }
                    Button("Criar mesada") {
                        guard draft.isValid else { showErrors = true; return }
                        if store.attempt({ try store.addAllowance(draft) }) { store.show("Mesada criada."); dismiss() }
                    }
                    .buttonStyle(.primary).accessibilityIdentifier("family.allowance.form.save")
                }
                .padding(Space.screenMargin)
            }
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Nova mesada")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear { draft.memberId = draft.memberId ?? store.dependents.first?.id; draft.fromAccountId = draft.fromAccountId ?? store.activeAccounts.first?.id }
        .toastHost()
        .accessibilityIdentifier("family.allowance.form")
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            FlowLayout {
                ForEach(store.accounts.filter { !$0.isArchived }) { a in
                    Chip(title: a.name, isSelected: selection.wrappedValue == a.id) { selection.wrappedValue = a.id }
                        .accessibilityIdentifier("family.allowance.form.\(id).\(a.name)")
                }
            }
        }
    }
}

/// family.approvals: gastos de dependentes acima do limite, aguardando decisão.
struct ApprovalsView: View {
    @Environment(AppStore.self) private var store

    private var canDecide: Bool { store.activeMember.map { FamilyEngine.can($0.role, .approveSpending) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                let pending = store.pendingApprovals
                if pending.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "Nada para aprovar",
                               message: "Quando um dependente passar do limite mensal, o gasto aparece aqui.")
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
                ForEach(pending) { r in
                    HighlightBlock {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.headline).foregroundStyle(Color.textPrimary)
                                Text("\(store.lookup.memberName(r.memberId)), \(Fmt.date(r.date))").font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text(store.money(r.amount)).font(.headline).monospacedDigit().foregroundStyle(Color.textPrimary)
                        }
                        if canDecide {
                            HStack(spacing: Space.sm) {
                                Button("Recusar") { store.attempt { try store.reject(requestId: r.id) } }
                                    .buttonStyle(.secondary).accessibilityIdentifier("family.approvals.reject.\(r.title)")
                                Button("Aprovar") { store.attempt { try store.approve(requestId: r.id) }; store.show("Gasto aprovado.") }
                                    .buttonStyle(.primary).accessibilityIdentifier("family.approvals.approve.\(r.title)")
                            }
                        } else {
                            Label("Aguardando um responsável", systemImage: "hourglass").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                let decided = store.approvals.filter { $0.status != .pending }
                if !decided.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Decididos")
                        ListGroup {
                            SeparatedRows(items: decided) { r in
                                ListRow(title: r.title, subtitle: "\(store.lookup.memberName(r.memberId)), \(r.status.displayName.lowercased())") { EmptyView() } trailing: {
                                    Text(store.money(r.amount)).font(.body).monospacedDigit().foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Aprovações")
        .inlineNavigationTitle()
        .accessibilityIdentifier("family.approvals")
    }
}

#Preview("Acerto de contas") {
    NavigationStack { SettlementView() }.previewing(PreviewData.family)
}

#Preview("Dividir despesa") {
    SplitExpenseSheet().previewing(PreviewData.family)
}

#Preview("Mesada") {
    NavigationStack { AllowanceView() }.previewing(PreviewData.family)
}

#Preview("Aprovações") {
    NavigationStack { ApprovalsView() }.previewing(PreviewData.family, dark: true)
}
