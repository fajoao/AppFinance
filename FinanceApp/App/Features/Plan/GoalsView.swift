import SwiftUI

/// plan.goals: uma meta por bloco, com progresso, aporte mensal sugerido e "Guardar dinheiro".
struct GoalsView: View {
    @Environment(AppStore.self) private var store
    @State private var contributing: Goal?
    @State private var showsNewGoal = false
    @State private var editing: Goal?
    @State private var historyOf: Goal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.goals.isEmpty {
                    EmptyState(symbol: "target", title: "Crie sua primeira meta",
                               message: "Reserva de emergência, viagem, compra: defina o valor e o prazo.",
                               actionTitle: "Nova meta", actionIdentifier: "plan.goals.add.empty") { showsNewGoal = true }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    ForEach(Array(store.goals.enumerated()), id: \.element.id) { index, goal in
                        GoalBlock(goal: goal, index: index, onContribute: { contributing = goal },
                                  onEdit: { editing = goal }, onHistory: { historyOf = goal })
                    }
                    Button { showsNewGoal = true } label: { Label("Nova meta", systemImage: "plus") }
                        .buttonStyle(.secondary).accessibilityIdentifier("plan.goals.add")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .sheet(item: $contributing) { goal in
            ContributeSheet(goalId: goal.id)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
        .sheet(isPresented: $showsNewGoal) {
            GoalEditSheet(goalId: nil)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: $editing) { goal in
            GoalEditSheet(goalId: goal.id)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: $historyOf) { goal in
            GoalHistorySheet(goalId: goal.id)
                .presentationDetents([.large])
                .presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("plan.goals")
    }
}

struct GoalBlock: View {
    @Environment(AppStore.self) private var store
    let goal: Goal
    let index: Int
    let onContribute: () -> Void
    var onEdit: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil

    var body: some View {
        let p = store.progress(of: goal)
        let projection = store.projection(of: goal)
        HighlightBlock {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).font(.headline).foregroundStyle(Color.textPrimary).lineLimit(2)
                    if let deadline = goal.deadline {
                        Text(verbatim: "Prazo: \(DateText.monthShort(YearMonth(deadline))) de \(FinanceCalendar.components(deadline).year)")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    if let m = goal.memberId, let member = store.lookup.members[m] {
                        Text(verbatim: "Meta de \(member.name)").font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer(minLength: Space.sm)
                Badge(text: p.isComplete ? "Concluída" : "\(NSDecimalNumber(decimal: p.percent.rounded(scale: 0)).intValue)%", tone: p.isComplete ? .ok : .brand)
                if onEdit != nil || onHistory != nil {
                    Menu {
                        if let onEdit { Button("Editar meta", systemImage: "pencil", action: onEdit) }
                        if let onHistory { Button("Histórico e projeção", systemImage: "clock.arrow.circlepath", action: onHistory) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Color.brandPrimary).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Opções da meta \(goal.name)")
                    .accessibilityIdentifier("plan.goals.menu.\(index)")
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                SplitAmount(value: goal.currentAmount, style: .large)
                Text("de \(store.money(goal.targetAmount))").font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
            }
            ProgressBar(fraction: NSDecimalNumber(decimal: p.fraction).doubleValue, tone: p.isComplete ? .ok : .brand)
            if !p.isComplete, let needed = p.monthlyContributionNeeded {
                Text(verbatim: "Guarde \(store.money(needed)) por mês" + ((p.monthsRemaining ?? 0) > 0 ? " durante \(p.monthsRemaining!) \(p.monthsRemaining == 1 ? "mês" : "meses")" : ""))
                    .font(.subheadline).foregroundStyle(Color.textSecondary).monospacedDigit()
            }
            if !p.isComplete, let when = projection.projectedCompletion {
                Text(verbatim: "No seu ritmo (\(store.money(projection.averageMonthlyContribution)) por mês), conclui em \(Fmt.monthYearShort(when))")
                    .font(.footnote).foregroundStyle(projection.onTrack == false ? Color.warning : Color.textSecondary).monospacedDigit()
                    .accessibilityIdentifier("plan.goals.projection.\(index)")
            }
            Button("Guardar dinheiro", action: onContribute)
                .buttonStyle(.secondary)
                .accessibilityIdentifier("plan.goals.contribute.\(index)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.goals.block")
    }
}

/// plan.goals.contribute: valores rápidos, conta de origem e confirmação.
struct ContributeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalId: UUID
    @State private var amountText = ""
    @State private var accountId: UUID?

    private var amount: Decimal? { Money.parse(amountText, style: .comma) }
    private static let quick: [Decimal] = [50, 100, 200, 500]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let goal = store.goals.first(where: { $0.id == goalId }) {
                        Text(goal.name).font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Valor")
                        FlowLayout {
                            ForEach(Self.quick, id: \.self) { v in
                                Chip(title: MoneyDisplay.text(v), isSelected: amount == v) { amountText = MoneyDisplay.number(v) }
                                    .accessibilityIdentifier("plan.goals.contribute.quick.\(NSDecimalNumber(decimal: v).intValue)")
                            }
                        }
                        LabeledField(label: "Outro valor", text: $amountText, prompt: "0,00", isDecimal: true,
                                     identifier: "plan.goals.contribute.amount")
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Sai de")
                        ListGroup {
                            SeparatedRows(items: store.activeAccounts) { a in
                                Button { accountId = a.id } label: {
                                    ListRow(title: a.name, subtitle: "Saldo \(store.money(store.balance(of: a)))") { EmptyView() } trailing: {
                                        if accountId == a.id { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary) }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(accountId == a.id ? .isSelected : [])
                                .accessibilityIdentifier("plan.goals.contribute.account.\(a.name)")
                            }
                        }
                    }
                    Button("Guardar \(amount.map { MoneyDisplay.text($0) } ?? "R$\u{00A0}0,00")") { save() }
                        .buttonStyle(.primary)
                        .disabled((amount ?? 0) <= 0 || accountId == nil)
                        .accessibilityIdentifier("plan.goals.contribute.save")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Guardar dinheiro")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear { accountId = accountId ?? store.activeAccounts.first?.id }
        .toastHost()
        .accessibilityIdentifier("plan.goals.contribute")
    }

    private func save() {
        guard let amount, let accountId else { return }
        if store.attempt({ try store.contribute(goalId: goalId, amount: amount, from: accountId) }) {
            Haptics.success()
            store.show("Valor guardado na meta.")
            dismiss()
        }
    }
}

/// plan.goals.new / plan.goals.edit: criar ou editar nome, valor e prazo (e, ao criar, de quem é a meta).
struct GoalEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalId: UUID?
    var memberId: UUID? = nil
    @State private var draft = GoalDraft(today: FinanceCalendar.normalize(Date()))
    @State private var owner: UUID?
    @State private var showErrors = false
    @State private var confirmDelete = false
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome da meta", text: $draft.name, prompt: "Ex.: Reserva de emergência",
                                 error: showErrors ? draft.nameError : nil, identifier: "plan.goals.new.name")
                    LabeledField(label: "Valor da meta", text: $draft.targetText, prompt: "0,00",
                                 error: showErrors ? draft.targetError : nil, isDecimal: true, identifier: "plan.goals.new.target")
                    Toggle("Definir prazo", isOn: $draft.hasDeadline).accessibilityIdentifier("plan.goals.new.hasDeadline")
                    if draft.hasDeadline {
                        DatePicker("Prazo", selection: $draft.deadline, displayedComponents: .date)
                            .accessibilityIdentifier("plan.goals.new.deadline")
                    }
                    if goalId == nil, memberId == nil, !store.dependents.isEmpty {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader("Meta de")
                            FlowLayout {
                                Chip(title: "Minha", isSelected: owner == nil) { owner = nil }
                                ForEach(store.dependents) { m in Chip(title: m.name, isSelected: owner == m.id) { owner = m.id } }
                            }
                        }
                    }
                    Button(goalId == nil ? "Criar meta" : "Salvar alterações") { save() }
                        .buttonStyle(.primary).accessibilityIdentifier("plan.goals.new.save")
                    if goalId != nil {
                        Button("Excluir meta") { confirmDelete = true }
                            .buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("plan.goals.edit.delete")
                    }
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle(goalId == nil ? "Nova meta" : "Editar meta")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .confirmationDialog("Excluir esta meta e o histórico de aportes?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let goalId, store.attempt({ try store.deleteGoal(id: goalId) }) { store.show("Meta excluída."); dismiss() }
                }
            } message: { Text("O dinheiro já guardado continua nas contas de origem como saída. Isso não pode ser desfeito.") }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            owner = memberId
            if let goalId, let g = store.goals.first(where: { $0.id == goalId }) { draft = GoalDraft(editing: g, today: store.today) }
            else { draft = GoalDraft(today: store.today) }
        }
        .toastHost()
        .accessibilityIdentifier(goalId == nil ? "plan.goals.new" : "plan.goals.edit")
    }

    private func save() {
        guard draft.isValid, let target = draft.target else { showErrors = true; return }
        if let goalId {
            if store.attempt({ try store.updateGoal(id: goalId, draft) }) { store.show("Meta atualizada."); dismiss() }
        } else if store.attempt({ try store.addGoal(name: draft.name, target: target, deadline: draft.effectiveDeadline, memberId: owner) }) {
            store.show("Meta criada."); dismiss()
        }
    }
}

/// plan.goals.history: aportes (com opção de desfazer) e projeção de conclusão.
struct GoalHistorySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalId: UUID

    var body: some View {
        NavigationStack {
            Group {
                if let goal = store.goals.first(where: { $0.id == goalId }) {
                    content(goal)
                } else {
                    EmptyState(symbol: "questionmark.circle", title: "Meta não encontrada")
                }
            }
            .background(Color.canvas)
            .navigationTitle("Histórico")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .toastHost()
        .accessibilityIdentifier("plan.goals.history")
    }

    private func content(_ goal: Goal) -> some View {
        let projection = store.projection(of: goal)
        let entries = store.history(of: goal)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(goal.name).font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
                    SplitAmount(value: goal.currentAmount, style: .large)
                    Text("de \(store.money(goal.targetAmount))").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Projeção")
                    ListGroup {
                        row("Ritmo dos últimos 3 meses", "\(store.money(projection.averageMonthlyContribution)) por mês")
                        RowSeparator()
                        row("Conclusão prevista", projection.projectedCompletion.map(Fmt.monthYearShort) ?? "Sem aportes recentes")
                        if let onTrack = projection.onTrack {
                            RowSeparator()
                            row("Prazo", onTrack ? "No caminho" : "Atrasada", color: onTrack ? .income : .warning)
                        }
                        if let extra = projection.extraPerMonthNeeded, extra > 0 {
                            RowSeparator()
                            row("Faltam por mês", store.money(extra), color: .warning)
                        }
                    }
                    .accessibilityIdentifier("plan.goals.history.projection")
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Aportes")
                    if entries.isEmpty {
                        Text("Nenhum aporte ainda.").font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                    } else {
                        ListGroup {
                            SeparatedRows(items: entries) { e in
                                ListRow(title: DateText.full(e.date), subtitle: e.accountId.flatMap { store.lookup.accounts[$0]?.name }.map { "Saiu de \($0)" }) { EmptyView() } trailing: {
                                    HStack(spacing: Space.sm) {
                                        AmountText(e.amount.magnitude, sign: e.amount < 0 ? .expense : .income, role: e.amount < 0 ? .expense : .income)
                                        Button { store.attempt { try store.revertContribution(id: e.id) } } label: {
                                            Image(systemName: "arrow.uturn.backward").foregroundStyle(Color.brandPrimary).frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Desfazer aporte de \(DateText.full(e.date))")
                                        .accessibilityIdentifier("plan.goals.history.revert")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.screenMargin)
        }
    }

    private func row(_ label: String, _ value: String, color: Color = .textSecondary) -> some View {
        ListRow(title: label) { EmptyView() } trailing: { Text(value).font(.body).foregroundStyle(color).monospacedDigit().multilineTextAlignment(.trailing) }
    }
}

#Preview("Metas") {
    NavigationStack { GoalsView() }.previewing(PreviewData.demo)
}

#Preview("Metas vazio") {
    NavigationStack { GoalsView() }.previewing(PreviewData.empty)
}

#Preview("Metas, escuro, texto grande") {
    NavigationStack { GoalsView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Guardar dinheiro") {
    let store = PreviewData.demo
    ContributeSheet(goalId: store.goals[0].id).previewing(store)
}

#Preview("Nova meta") {
    GoalEditSheet(goalId: nil).previewing(PreviewData.demo, dark: true)
}

#Preview("Editar meta") {
    let store = PreviewData.demo
    GoalEditSheet(goalId: store.goals[0].id).previewing(store)
}

#Preview("Histórico da meta") {
    let store = PreviewData.demo
    GoalHistorySheet(goalId: store.goals[0].id).previewing(store)
}
