import SwiftUI

/// transactions.list: busca, filtros rápidos e lista agrupada por dia.
struct TransactionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.valuesHidden) private var hidden
    @State private var filter = TransactionFilter()
    @State private var showsFilters = false
    @State private var selected: Transaction?
    @State private var installmentDelete: Transaction?

    var body: some View {
        // O período padrão ("mês") é o mês visualizado; os filtros avançados continuam valendo por cima.
        let list = filter.apply(to: store.scopedTransactions, lookup: store.lookup, today: store.today, month: store.viewedMonth)
        let groups = TransactionFilter.groupByDay(list)
        VStack(spacing: 0) {
            MonthPicker()
            controls(count: list.count, result: TransactionFilter.result(of: list))
            if list.isEmpty {
                ScrollView {
                    if filter.isDefault {
                        EmptyState(symbol: "list.bullet.rectangle", title: "Nenhum lançamento em \(DateText.monthNameLower(store.viewedMonth))",
                                   message: "Registre uma despesa ou receita para vê-la aqui.",
                                   actionTitle: "Novo lançamento", actionIdentifier: "transactions.empty.new") { router.presentNew() }
                    } else {
                        EmptyState(symbol: "magnifyingglass", title: "Nenhum lançamento encontrado",
                                   message: "Nada combina com a busca e os filtros atuais.",
                                   actionTitle: "Limpar busca e filtros", actionIdentifier: "transactions.clearFilters") { filter.reset() }
                    }
                }
                .refreshableStore()
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { tx in
                                Button { selected = tx } label: { TransactionRow(transaction: tx, lookup: store.lookup) }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.surface)
                                    .listRowSeparatorTint(Color.separator)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if !tx.isInvoicePayment {
                                            if tx.installment != nil {
                                                Button("Excluir…", role: .destructive) { installmentDelete = tx }
                                            } else {
                                                Button("Excluir", role: .destructive) { store.attempt { try store.deleteTransaction(id: tx.id) } }
                                            }
                                        }
                                    }
                                    .accessibilityIdentifier("transactions.row")
                            }
                        } header: {
                            HStack {
                                Text(TransactionFilter.dayTitle(group.date, today: store.today))
                                Spacer()
                                Text(MoneyDisplay.text(group.total, hidden: hidden)).monospacedDigit()
                            }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                            .textCase(nil)
                            // O cabeçalho do dia fica fixo no topo ao rolar: precisa de fundo opaco, senão as linhas
                            // que passam por baixo aparecem através dele e os textos e valores se sobrepõem.
                            .padding(.horizontal, Space.screenMargin).padding(.vertical, Space.sm)
                            .frame(maxWidth: .infinity)
                            .background(Color.canvas)
                            .listRowInsets(EdgeInsets())
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshableStore()
            }
        }
        .background(Color.canvas)
        .navigationTitle("Lançamentos")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .trailingBar) { RefreshButton() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transactions.list")
        .sheet(isPresented: $showsFilters) {
            FiltersSheet(filter: $filter)
                .presentationDetents([.large])
                .presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: $selected) { tx in
            TransactionDetailSheet(transactionId: tx.id)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Radius.sheet)
        }
        .installmentDeleteDialog(for: $installmentDelete)
    }

    private func controls(count: Int, result: Decimal) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.textTertiary).accessibilityHidden(true)
                TextField("Buscar por nome, categoria, tag ou conta", text: $filter.query)
                    .noAutocapitalization()
                    .accessibilityIdentifier("transactions.search")
                if !filter.query.isEmpty {
                    Button { filter.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textTertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: Space.minTouchTarget)
            .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(title: "Filtros", systemImage: "line.3.horizontal.decrease", isSelected: filter.advancedCount > 0,
                         badgeCount: filter.advancedCount) { showsFilters = true }
                        .accessibilityIdentifier("transactions.filters")
                    Menu {
                        Picker("Período", selection: $filter.period) {
                            ForEach(FilterPeriod.allCases) { Text($0.title(viewed: store.viewedMonth, today: store.today)).tag($0) }
                        }
                    } label: {
                        ChipLabel(title: filter.period.title(viewed: store.viewedMonth, today: store.today), systemImage: "calendar")
                    }
                    .accessibilityIdentifier("transactions.period")
                    Chip(title: "Despesas", isSelected: filter.type == .expense) { filter.type = filter.type == .expense ? .all : .expense }
                        .accessibilityIdentifier("transactions.filter.expense")
                    Chip(title: "Receitas", isSelected: filter.type == .income) { filter.type = filter.type == .income ? .all : .income }
                        .accessibilityIdentifier("transactions.filter.income")
                }
            }
            HStack {
                Text("\(count) \(count == 1 ? "lançamento" : "lançamentos")")
                Spacer()
                Text("Resultado \(MoneyDisplay.text(result, hidden: hidden))").monospacedDigit()
            }
            .font(.footnote).foregroundStyle(Color.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("transactions.summary")
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.vertical, Space.sm)
    }
}

/// Detalhe do lançamento: informações, marcar como pago e excluir.
struct TransactionDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transactionId: UUID
    @State private var confirmDelete = false
    @State private var installmentDelete: Transaction?
    @State private var showsEdit = false

    var body: some View {
        NavigationStack {
            Group {
                if let tx = store.transactions.first(where: { $0.id == transactionId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xl) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(tx.title).font(.title2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                                AmountText(transaction: tx)
                            }
                            ListGroup {
                                detail("Data", DateText.full(tx.date))
                                RowSeparator()
                                detail(tx.type == .transfer ? "Contas" : "Conta ou cartão", store.lookup.accountLabel(of: tx))
                                if tx.type != .transfer {
                                    RowSeparator()
                                    detail("Categoria", store.lookup.categoryName(tx.categoryId))
                                }
                                if let i = tx.installment { RowSeparator(); detail("Parcela", i.label) }
                                if tx.recurrence != nil { RowSeparator(); detail("Repete", tx.recurrence?.frequency == .weekly ? "Toda semana" : "Todo mês") }
                                if !tx.tagIds.isEmpty { RowSeparator(); detail("Tags", store.lookup.tagNames(of: tx).joined(separator: ", ")) }
                                if tx.memberId != nil { RowSeparator(); detail("Quem", store.lookup.memberName(tx.memberId)) }
                                if let note = tx.note { RowSeparator(); detail("Observação", note) }
                                RowSeparator()
                                detail("Situação", tx.status == .paid ? "Pago" : "Pendente")
                            }
                            if let path = tx.attachmentPath, let data = store.attachmentData(path) {
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    SectionHeader("Comprovante")
                                    DataImage(data: data).frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                        .accessibilityLabel("Foto do comprovante")
                                }
                                .accessibilityIdentifier("transaction.detail.attachment")
                            }
                            if tx.status == .pending && !tx.isCardPurchase {
                                Button("Marcar como pago") { store.attempt { try store.markPaid(transactionId: tx.id) }; dismiss() }
                                    .buttonStyle(.primary).accessibilityIdentifier("transaction.detail.markPaid")
                            }
                            if !tx.isInvoicePayment {
                                Button("Editar lançamento") { showsEdit = true }
                                    .buttonStyle(.secondary).accessibilityIdentifier("transaction.detail.edit")
                                Button(tx.installment == nil ? "Excluir lançamento" : "Excluir parcelas…") {
                                    if tx.installment == nil { confirmDelete = true } else { installmentDelete = tx }
                                }
                                    .buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("transaction.detail.delete")
                            }
                        }
                        .padding(Space.screenMargin)
                    }
                } else {
                    EmptyState(symbol: "questionmark.circle", title: "Lançamento não encontrado")
                }
            }
            .background(Color.canvas)
            .navigationTitle("Lançamento")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .confirmationDialog("Excluir este lançamento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    store.attempt { try store.deleteTransaction(id: transactionId) }
                    dismiss()
                }
            }
            .installmentDeleteDialog(for: $installmentDelete) { dismiss() }
            .sheet(isPresented: $showsEdit) {
                NewTransactionView(editing: transactionId)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Radius.sheet)
            }
        }
        .toastHost()
        .accessibilityIdentifier("transaction.detail")
    }

    private func detail(_ label: String, _ value: String) -> some View {
        ListRow(title: label) { EmptyView() } trailing: {
            Text(value).font(.body).foregroundStyle(Color.textSecondary).multilineTextAlignment(.trailing)
        }
    }
}

#Preview("Lançamentos com dados") {
    NavigationStack { TransactionsView() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("Lançamentos vazio") {
    NavigationStack { TransactionsView() }.previewing(PreviewData.empty).environment(Router())
}

#Preview("Lançamentos, escuro, texto grande") {
    NavigationStack { TransactionsView() }.previewing(PreviewData.demo, dark: true).environment(Router())
        .dynamicTypeSize(.accessibility2)
}

#Preview("Detalhe do lançamento") {
    let store = PreviewData.demo
    TransactionDetailSheet(transactionId: store.transactions.first(where: { $0.status == .pending })?.id ?? UUID()).previewing(store)
}
