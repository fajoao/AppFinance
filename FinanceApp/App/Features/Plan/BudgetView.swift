import SwiftUI

/// plan.budget: disponível no mês e uma linha por categoria com barra, marca de 80% e status.
struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: BudgetEditTarget?

    var body: some View {
        let month = store.viewedMonth
        let statuses = store.budgetStatuses(for: month)
        let totals = store.budgetTotals(for: month)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                MonthPicker(inset: false)   // dentro da rolagem: acompanha o gesto de puxar e o título grande
                if statuses.isEmpty {
                    EmptyState(symbol: "chart.pie", title: "Defina quanto quer gastar",
                               message: store.isViewingCurrentMonth
                                   ? "Crie um limite mensal por categoria e acompanhe o quanto já usou."
                                   : "Sem orçamento em \(DateText.monthNameLower(month)). Crie limites para esse mês ou copie os do mês anterior.",
                               actionTitle: "Criar orçamento", actionIdentifier: "plan.budget.add.empty") { editing = .new }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    copyButton
                } else {
                    summary(totals: totals, month: month)
                    ListGroup {
                        ForEach(Array(statuses.enumerated()), id: \.element.budget.id) { index, status in
                            Button { editing = .edit(status.budget.id) } label: { BudgetRow(status: status) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("plan.budget.row.\(store.lookup.categoryName(status.budget.categoryId))")
                            if index < statuses.count - 1 { RowSeparator(inset: 64) }
                        }
                    }
                    actions
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .sheet(item: $editing) { target in
            BudgetEditSheet(target: target)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("plan.budget")
    }

    private func summary(totals: (limit: Decimal, spent: Decimal), month: YearMonth) -> some View {
        let available = totals.limit - totals.spent
        let fraction = totals.limit > 0 ? min(max(NSDecimalNumber(decimal: totals.spent / totals.limit).doubleValue, 0), 1) : 0
        let alert = BudgetEngine.alert(spent: totals.spent, limit: totals.limit)
        return VStack(alignment: .leading, spacing: Space.sm) {
            Text(available < 0 ? "Acima do orçamento em \(DateText.monthNameLower(month))" : "Disponível em \(DateText.monthNameLower(month))")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
            SplitAmount(value: available, style: .large).accessibilityIdentifier("plan.budget.available")
            ProgressBar(fraction: fraction, tone: alert.tone, marker: 0.8)
            Text("Gasto \(store.money(totals.spent)) de \(store.money(totals.limit))")
                .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
        }
    }

    private var actions: some View {
        VStack(spacing: Space.sm) {
            Button { editing = .new } label: { Label("Adicionar orçamento", systemImage: "plus") }
                .buttonStyle(.secondary).accessibilityIdentifier("plan.budget.add")
            copyButton
        }
    }

    /// Copia do mês anterior ao visualizado para o visualizado (não para o mês de hoje).
    @ViewBuilder
    private var copyButton: some View {
        if store.budgets.contains(where: { $0.month == store.viewedMonth.previous }) {
            Button("Copiar do mês anterior") {
                store.attempt {
                    let n = try store.copyBudgetsFromPreviousMonth()
                    store.show(n == 0 ? "Nada novo para copiar." : "\(n) \(n == 1 ? "orçamento copiado" : "orçamentos copiados").")
                }
            }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("plan.budget.copy")
        }
    }
}

struct BudgetRow: View {
    @Environment(AppStore.self) private var store
    let status: BudgetStatus

    var body: some View {
        let category = store.lookup.categories[status.budget.categoryId]
        let frac = min(max(NSDecimalNumber(decimal: status.percentUsed / 100).doubleValue, 0), 1)
        HStack(alignment: .top, spacing: Space.md) {
            CategoryIcon(category: category, lookup: store.lookup)
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category?.name ?? "Categoria").font(.body).foregroundStyle(Color.textPrimary)
                    Spacer(minLength: Space.sm)
                    badge
                }
                ProgressBar(fraction: frac, tone: status.alert.tone, marker: 0.8)
                HStack {
                    Text("Gasto \(store.money(status.spent))").lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text("de \(store.money(status.limit))").lineLimit(1)
                }
                .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
            }
        }
        .padding(Space.lg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch status.alert {
        case .exceeded: Badge(text: "Estourou \(store.money(-status.remaining))", tone: .danger)
        case .warning: Badge(text: "\(store.percentText(status.percentUsed)) usado", tone: .warning)
        case .none: Badge(text: "Restam \(store.money(status.remaining))", tone: .brand)
        }
    }
}

enum BudgetEditTarget: Identifiable, Hashable {
    case new
    case edit(UUID)
    var id: String { switch self { case .new: return "new"; case .edit(let id): return id.uuidString } }
}

/// plan.budget.edit: cria ou ajusta o limite mensal de uma categoria.
struct BudgetEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: BudgetEditTarget
    @State private var categoryId: UUID?
    @State private var limitText = ""
    @State private var showError = false

    private var existing: Budget? {
        if case .edit(let id) = target { return store.budgets.first { $0.id == id } }
        return nil
    }

    private var available: [Category] {
        let used = Set(store.budgets.filter { $0.month == store.viewedMonth }.map(\.categoryId))
        return store.expenseCategories.filter { !used.contains($0.id) }
    }

    private var limit: Decimal? { Money.parse(limitText, style: .comma) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let existing {
                        HStack(spacing: Space.md) {
                            CategoryIcon(category: store.lookup.categories[existing.categoryId], lookup: store.lookup)
                            Text(store.lookup.categoryName(existing.categoryId)).font(.title3.weight(.semibold))
                        }
                    } else if available.isEmpty {
                        EmptyState(symbol: "checkmark.circle", title: "Todas as categorias já têm orçamento")
                    } else {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader("Categoria")
                            FlowLayout {
                                ForEach(available) { c in
                                    Chip(title: c.name, systemImage: c.icon, isSelected: categoryId == c.id) { categoryId = c.id }
                                        .accessibilityIdentifier("plan.budget.edit.category.\(c.name)")
                                }
                            }
                        }
                    }
                    LabeledField(label: "Limite do mês", text: $limitText, prompt: "0,00",
                                 error: showError && (limit ?? 0) <= 0 ? "Informe um valor maior que zero." : nil,
                                 isDecimal: true, identifier: "plan.budget.limit")
                    Button("Salvar orçamento") { save() }
                        .buttonStyle(.primary)
                        .disabled(existing == nil && (categoryId == nil || available.isEmpty))
                        .accessibilityIdentifier("plan.budget.save")
                    if let existing {
                        Button("Remover orçamento") {
                            store.attempt { try store.removeBudget(id: existing.id) }
                            dismiss()
                        }
                        .buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("plan.budget.remove")
                    }
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle(existing == nil ? "Novo orçamento" : "Ajustar orçamento")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear {
            if let existing { categoryId = existing.categoryId; limitText = MoneyDisplay.number(existing.limit) }
        }
        .toastHost()
        .accessibilityIdentifier("plan.budget.edit")
    }

    private func save() {
        guard let categoryId = existing?.categoryId ?? categoryId, let limit, limit > 0 else { showError = true; return }
        if store.attempt({ try store.setBudget(categoryId: categoryId, limit: limit) }) {
            Haptics.success()
            store.show("Orçamento salvo.")
            dismiss()
        }
    }
}

#Preview("Orçamento") {
    NavigationStack { BudgetView() }.previewing(PreviewData.demo)
}

#Preview("Orçamento vazio") {
    NavigationStack { BudgetView() }.previewing(PreviewData.empty)
}

#Preview("Orçamento, escuro, texto grande") {
    NavigationStack { BudgetView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Linhas de orçamento") {
    let store = PreviewData.demo
    ListGroup {
        ForEach(store.budgetStatuses(for: store.viewedMonth), id: \.budget.id) { status in
            BudgetRow(status: status)
            RowSeparator(inset: 64)
        }
    }
    .padding()
    .background(Color.canvas)
    .previewing(store)
}

#Preview("Editar orçamento") {
    BudgetEditSheet(target: .new).previewing(PreviewData.demo)
}
