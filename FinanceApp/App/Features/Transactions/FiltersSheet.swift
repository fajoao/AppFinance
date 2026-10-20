import SwiftUI

/// transactions.filters: período, tipo, contas e cartões, categorias, valor e tag, com contagem ao vivo.
struct FiltersSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TransactionFilter
    @State private var minText = ""
    @State private var maxText = ""

    private var matchCount: Int {
        filter.apply(to: store.scopedTransactions, lookup: store.lookup, today: store.today).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    section("Período") {
                        FlowLayout {
                            ForEach(FilterPeriod.allCases) { p in
                                Chip(title: p.title(viewed: store.viewedMonth, today: store.today), isSelected: filter.period == p) { filter.period = p }
                                    .accessibilityIdentifier("transactions.filters.period.\(p.rawValue)")
                            }
                        }
                    }
                    section("Tipo") {
                        FlowLayout {
                            ForEach(TypeFilter.allCases) { t in
                                Chip(title: t.title, isSelected: filter.type == t) { filter.type = t }
                                    .accessibilityIdentifier("transactions.filters.type.\(t.rawValue)")
                            }
                        }
                    }
                    section("Contas e cartões") {
                        FlowLayout {
                            ForEach(store.activeAccounts) { a in toggleChip(a.name, id: a.id, set: \.sourceIds) }
                            ForEach(store.activeCards) { c in toggleChip(c.name, id: c.id, set: \.sourceIds) }
                        }
                    }
                    section("Categorias") {
                        FlowLayout {
                            ForEach(store.expenseCategories + store.incomeCategories) { c in
                                toggleChip(c.name + (c.kind == .income ? " (receita)" : ""), id: c.id, set: \.categoryIds)
                            }
                        }
                    }
                    section("Valor") {
                        HStack(spacing: Space.md) {
                            LabeledField(label: "Mínimo", text: $minText, prompt: "0,00", isDecimal: true, identifier: "transactions.filters.min")
                            LabeledField(label: "Máximo", text: $maxText, prompt: "0,00", isDecimal: true, identifier: "transactions.filters.max")
                        }
                    }
                    if !store.tags.isEmpty {
                        section("Tag") {
                            FlowLayout {
                                ForEach(store.tags) { tag in
                                    Chip(title: "#" + tag.name, isSelected: filter.tagId == tag.id) {
                                        filter.tagId = filter.tagId == tag.id ? nil : tag.id
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Filtros")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpar") { filter.reset(); minText = ""; maxText = "" }
                        .accessibilityIdentifier("transactions.filters.clear")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.accessibilityIdentifier("transactions.filters.ok")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Mostrar \(matchCount) \(matchCount == 1 ? "lançamento" : "lançamentos")") { dismiss() }
                    .buttonStyle(.primary)
                    .padding(Space.screenMargin)
                    .background(.bar)
                    .accessibilityIdentifier("transactions.filters.show")
            }
        }
        .onAppear {
            minText = filter.minAmount.map { MoneyDisplay.number($0) } ?? ""
            maxText = filter.maxAmount.map { MoneyDisplay.number($0) } ?? ""
        }
        .onChange(of: minText) { _, t in filter.minAmount = t.isEmpty ? nil : Money.parse(t, style: .comma) }
        .onChange(of: maxText) { _, t in filter.maxAmount = t.isEmpty ? nil : Money.parse(t, style: .comma) }
        .accessibilityIdentifier("transactions.filters.sheet")
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            content()
        }
    }

    private func toggleChip(_ title: String, id: UUID, set keyPath: WritableKeyPath<TransactionFilter, Set<UUID>>) -> some View {
        Chip(title: title, isSelected: filter[keyPath: keyPath].contains(id)) {
            if filter[keyPath: keyPath].contains(id) { filter[keyPath: keyPath].remove(id) } else { filter[keyPath: keyPath].insert(id) }
        }
    }
}

#Preview("Filtros") {
    FiltersSheet(filter: .constant(TransactionFilter())).previewing(PreviewData.demo)
}

#Preview("Filtros ativos, escuro") {
    let active: TransactionFilter = {
        var f = TransactionFilter()
        f.type = .expense; f.minAmount = dec("100"); f.period = .all
        return f
    }()
    FiltersSheet(filter: .constant(active)).previewing(PreviewData.demo, dark: true)
}

#Preview("Filtros sem dados") {
    FiltersSheet(filter: .constant(TransactionFilter())).previewing(PreviewData.empty)
}
