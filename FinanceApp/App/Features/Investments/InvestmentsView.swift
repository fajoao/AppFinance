import SwiftUI
import Charts

extension AssetClass {
    var symbol: String {
        switch self {
        case .fixedIncome: return "banknote"
        case .stock: return "chart.bar"
        case .reit: return "building.2"
        case .crypto: return "bitcoinsign.circle"
        }
    }
    /// Cor da fatia (tokens de categoria do Asset Catalog).
    var color: Color {
        switch self {
        case .fixedIncome: return Color.category("catMoradia")
        case .stock: return Color.category("catTransporte")
        case .reit: return Color.category("catMercado")
        case .crypto: return Color.category("catLazer")
        }
    }
}

enum InvestmentTarget: Identifiable, Hashable {
    case new, detail(UUID)
    var id: String { switch self { case .new: return "new"; case .detail(let id): return id.uuidString } }
}

/// wallet.investments: carteira manual, alocação por classe, rentabilidade simples.
struct InvestmentsView: View {
    @Environment(AppStore.self) private var store
    @State private var target: InvestmentTarget?

    var body: some View {
        let totals = store.portfolio
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Valor da carteira").font(.subheadline).foregroundStyle(Color.textSecondary)
                    SplitAmount(value: totals.value, style: .large).accessibilityIdentifier("wallet.investments.total")
                    if let pct = totals.returnPercent {
                        Text("Rentabilidade \(Fmt.signedPercent(pct)), \(store.money(totals.gain)) sobre \(store.money(totals.cost)) investidos")
                            .font(.subheadline).foregroundStyle(totals.gain >= 0 ? Color.income : Color.danger).monospacedDigit()
                            .accessibilityIdentifier("wallet.investments.return")
                    }
                }
                NavigationLink { NetWorthView() } label: {
                    ListGroup {
                        ListRow(title: "Patrimônio líquido", subtitle: "Ativos menos dívidas e faturas") {
                            Image(systemName: "scalemass").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                        } trailing: { AmountText(balance: store.netWorth.netWorth) }
                    }
                }
                .buttonStyle(.plain).accessibilityIdentifier("wallet.investments.networth")
                if store.visibleInvestments.isEmpty {
                    EmptyState(symbol: "chart.pie", title: "Nenhum investimento cadastrado",
                               message: "Cadastre renda fixa, ações, FIIs e cripto à mão. As cotações são atualizadas por você.",
                               actionTitle: "Adicionar ativo", actionIdentifier: "wallet.investments.add.empty") { target = .new }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    allocation
                    ForEach(AssetClass.allCases, id: \.self) { cls in
                        let list = store.visibleInvestments.filter { $0.assetClass == cls }
                        if !list.isEmpty { section(cls, list) }
                    }
                    Button { target = .new } label: { Label("Adicionar ativo", systemImage: "plus") }
                        .buttonStyle(.secondary).accessibilityIdentifier("wallet.investments.add")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .sheet(item: $target) { t in
            switch t {
            case .new: InvestmentFormSheet(investmentId: nil).presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
            case .detail(let id): InvestmentDetailSheet(investmentId: id).presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
            }
        }
        .accessibilityIdentifier("wallet.investments")
    }

    private var allocation: some View {
        let slices = store.allocation
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Alocação por classe")
            HStack(alignment: .center, spacing: Space.lg) {
                Chart(slices, id: \.assetClass) { s in
                    SectorMark(angle: .value("Valor", NSDecimalNumber(decimal: s.value).doubleValue), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(s.assetClass.color)
                }
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(slices, id: \.assetClass) { s in
                        HStack(spacing: Space.sm) {
                            Circle().fill(s.assetClass.color).frame(width: 10, height: 10).accessibilityHidden(true)
                            Text(s.assetClass.displayName).font(.subheadline).foregroundStyle(Color.textPrimary)
                            Spacer(minLength: Space.xs)
                            Text(Fmt.percent(s.percent, scale: 1)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Color.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .accessibilityIdentifier("wallet.investments.allocation")
        }
    }

    private func section(_ cls: AssetClass, _ list: [Investment]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: cls.displayName) {
                Text(store.money(list.reduce(Decimal(0)) { $0 + InvestmentEngine.marketValue($1) }))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).monospacedDigit()
            }
            ListGroup {
                SeparatedRows(items: list, inset: 56) { i in
                    Button { target = .detail(i.id) } label: {
                        ListRow(title: i.ticker ?? i.name, subtitle: subtitle(i)) {
                            Image(systemName: cls.symbol).foregroundStyle(cls.color).frame(width: 28).accessibilityHidden(true)
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(store.money(InvestmentEngine.marketValue(i))).font(.body.weight(.medium)).foregroundStyle(Color.textPrimary).monospacedDigit()
                                if let r = InvestmentEngine.returnPercent(i) {
                                    Text(Fmt.signedPercent(r)).font(.footnote).foregroundStyle(r >= 0 ? Color.income : Color.danger).monospacedDigit()
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wallet.investments.row.\(i.ticker ?? i.name)")
                }
            }
        }
    }

    private func subtitle(_ i: Investment) -> String {
        if i.assetClass == .fixedIncome { return "Aplicado \(store.money(i.averagePrice))" }
        let base = "\(Fmt.quantity(i.quantity)) × \(store.money(i.averagePrice))"
        return i.ticker == nil ? base : "\(i.name), \(base)"
    }
}

/// wallet.investments.form: cadastro/edição de ativo.
struct InvestmentFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let investmentId: UUID?
    @State private var draft = InvestmentDraft()
    @State private var showErrors = false
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Classe")
                        FlowLayout {
                            ForEach(AssetClass.allCases, id: \.self) { c in
                                Chip(title: c.displayName, systemImage: c.symbol, isSelected: draft.assetClass == c) { draft.assetClass = c }
                                    .accessibilityIdentifier("wallet.investments.form.class.\(c.rawValue)")
                            }
                        }
                    }
                    LabeledField(label: "Nome", text: $draft.name, prompt: draft.assetClass == .fixedIncome ? "Ex.: CDB 110% CDI" : "Ex.: Petrobras",
                                 error: showErrors ? draft.nameError : nil, identifier: "wallet.investments.form.name")
                    if !draft.usesAmountOnly {
                        LabeledField(label: "Código (opcional)", text: $draft.ticker, prompt: "Ex.: PETR4", identifier: "wallet.investments.form.ticker")
                        LabeledField(label: "Quantidade", text: $draft.quantityText, prompt: "0",
                                     error: showErrors ? draft.quantityError : nil, isDecimal: true, identifier: "wallet.investments.form.quantity")
                    }
                    LabeledField(label: draft.priceLabel, text: $draft.priceText, prompt: "0,00",
                                 error: showErrors ? draft.priceError : nil, isDecimal: true, identifier: "wallet.investments.form.price")
                    LabeledField(label: draft.quoteLabel, text: $draft.quoteText, prompt: "0,00",
                                 error: showErrors ? draft.quoteError : nil, isDecimal: true, identifier: "wallet.investments.form.quote")
                    Text("Você atualiza a cotação manualmente. O app não consulta preços na internet.")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                    Button(investmentId == nil ? "Adicionar ativo" : "Salvar alterações") { save() }
                        .buttonStyle(.primary).accessibilityIdentifier("wallet.investments.form.save")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle(investmentId == nil ? "Novo ativo" : "Editar ativo")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            if let investmentId, let i = store.investments.first(where: { $0.id == investmentId }) { draft = InvestmentDraft(editing: i) }
        }
        .toastHost()
        .accessibilityIdentifier("wallet.investments.form")
    }

    private func save() {
        guard draft.isValid else { showErrors = true; return }
        if store.attempt({ try store.saveInvestment(draft) }) { store.show("Ativo salvo."); dismiss() }
    }
}

/// wallet.investments.detail: posição, compra, venda, cotação manual e exclusão.
struct InvestmentDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let investmentId: UUID
    @State private var quoteText = ""
    @State private var change = PositionChangeDraft(kind: .buy)
    @State private var showsChange = false
    @State private var showsEdit = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let i = store.investments.first(where: { $0.id == investmentId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xl) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(i.name).font(.title2.weight(.semibold)).foregroundStyle(Color.textPrimary)
                                SplitAmount(value: InvestmentEngine.marketValue(i), style: .large)
                            }
                            ListGroup {
                                row("Classe", i.assetClass.displayName)
                                RowSeparator()
                                if i.assetClass != .fixedIncome { row("Quantidade", Fmt.quantity(i.quantity)); RowSeparator() }
                                row(i.assetClass == .fixedIncome ? "Valor aplicado" : "Preço médio", store.money(i.averagePrice))
                                RowSeparator()
                                row("Custo total", store.money(InvestmentEngine.cost(i)))
                                RowSeparator()
                                row("Ganho ou perda", store.money(InvestmentEngine.gain(i)),
                                    color: InvestmentEngine.gain(i) >= 0 ? .income : .danger)
                                RowSeparator()
                                row("Rentabilidade simples", InvestmentEngine.returnPercent(i).map(Fmt.signedPercent) ?? "—")
                                if i.realizedProfit != 0 { RowSeparator(); row("Lucro já realizado", store.money(i.realizedProfit)) }
                                if let d = i.quoteDate { RowSeparator(); row("Cotação de", Fmt.date(d)) }
                            }
                            VStack(alignment: .leading, spacing: Space.sm) {
                                LabeledField(label: i.assetClass == .fixedIncome ? "Novo valor atual" : "Nova cotação", text: $quoteText,
                                             prompt: "0,00", isDecimal: true, identifier: "wallet.investments.detail.quote")
                                Button("Atualizar cotação") {
                                    if store.attempt({ try store.updateQuote(investmentId: i.id, quoteText: quoteText) }) {
                                        quoteText = ""; store.show("Cotação atualizada.")
                                    }
                                }
                                .buttonStyle(.secondary).disabled(quoteText.isEmpty).accessibilityIdentifier("wallet.investments.detail.updateQuote")
                            }
                            if i.assetClass != .fixedIncome {
                                HStack(spacing: Space.sm) {
                                    Button("Comprar mais") { change = PositionChangeDraft(kind: .buy); showsChange = true }
                                        .buttonStyle(.secondary).accessibilityIdentifier("wallet.investments.detail.buy")
                                    Button("Vender") { change = PositionChangeDraft(kind: .sell); showsChange = true }
                                        .buttonStyle(.secondary).accessibilityIdentifier("wallet.investments.detail.sell")
                                }
                            }
                            Button("Editar dados") { showsEdit = true }.buttonStyle(LinkButtonStyle()).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("wallet.investments.detail.edit")
                            Button("Excluir ativo") { confirmDelete = true }.buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("wallet.investments.detail.delete")
                        }
                        .padding(Space.screenMargin)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .dismissesKeyboardOnTap()
                } else {
                    EmptyState(symbol: "questionmark.circle", title: "Ativo não encontrado")
                }
            }
            .background(Color.canvas)
            .navigationTitle("Posição")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(isPresented: $showsChange) {
                PositionChangeSheet(investmentId: investmentId, change: change).presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
            }
            .sheet(isPresented: $showsEdit) {
                InvestmentFormSheet(investmentId: investmentId).presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
            }
            .confirmationDialog("Excluir este ativo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { if store.attempt({ try store.deleteInvestment(id: investmentId) }) { dismiss() } }
            }
        }
        .toastHost()
        .accessibilityIdentifier("wallet.investments.detail")
    }

    private func row(_ label: String, _ value: String, color: Color = .textSecondary) -> some View {
        ListRow(title: label) { EmptyView() } trailing: { Text(value).font(.body).foregroundStyle(color).monospacedDigit() }
    }
}

struct PositionChangeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let investmentId: UUID
    @State var change: PositionChangeDraft

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Quantidade", text: $change.quantityText, prompt: "0", isDecimal: true, identifier: "wallet.investments.change.quantity")
                    LabeledField(label: change.kind == .buy ? "Preço pago por unidade" : "Preço de venda por unidade", text: $change.priceText,
                                 prompt: "0,00", isDecimal: true, identifier: "wallet.investments.change.price")
                    Text(change.kind == .buy ? "O preço médio é recalculado." : "O lucro ou prejuízo da venda é calculado sobre o preço médio.")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                    Button(change.kind == .buy ? "Registrar compra" : "Registrar venda") {
                        if store.attempt({ try store.applyPositionChange(investmentId: investmentId, change) }) { store.show("Posição atualizada."); dismiss() }
                    }
                    .buttonStyle(.primary).disabled(!change.isValid).accessibilityIdentifier("wallet.investments.change.save")
                }
                .padding(Space.screenMargin)
            }
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle(change.kind == .buy ? "Comprar" : "Vender")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .toastHost()
    }
}

/// wallet.networth: ativos − passivos e evolução mensal.
struct NetWorthView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let nw = store.netWorth
        let series = store.netWorthEvolution(months: 12)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Patrimônio líquido").font(.subheadline).foregroundStyle(Color.textSecondary)
                    SplitAmount(value: nw.netWorth).accessibilityIdentifier("wallet.networth.total")
                    if let delta = NetWorthEngine.change(series) {
                        Text("\(delta >= 0 ? "Subiu" : "Caiu") \(store.money(delta.magnitude)) desde o primeiro registro")
                            .font(.subheadline).foregroundStyle(delta >= 0 ? Color.income : Color.danger)
                    }
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Ativos") {
                        Text(store.money(nw.assets)).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).monospacedDigit()
                    }
                    ListGroup {
                        line("Contas", nw.accountsAssets)
                        RowSeparator()
                        line("Investimentos", nw.investmentsValue)
                    }
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Passivos") {
                        Text(store.money(nw.liabilities)).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).monospacedDigit()
                    }
                    ListGroup {
                        line("Dívidas", nw.debts)
                        RowSeparator()
                        line("Faturas e parcelas no cartão", nw.cardBalances)
                        RowSeparator()
                        line("Saldo negativo em contas", nw.overdraft)
                    }
                    Text("Faturas e parcelas contam pelo total ainda não pago, inclusive parcelas futuras.")
                        .font(.footnote).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                }
                evolution(series)
                Button("Registrar patrimônio agora") {
                    if store.attempt({ _ = try store.recordNetWorthSnapshot() }) { store.show("Patrimônio do mês registrado.") }
                }
                .buttonStyle(.secondary).accessibilityIdentifier("wallet.networth.record")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Patrimônio")
        .inlineNavigationTitle()
        .onAppear { store.attempt { _ = try store.recordNetWorthSnapshot() } }
        .accessibilityIdentifier("wallet.networth")
    }

    private func line(_ label: String, _ value: Decimal) -> some View {
        ListRow(title: label) { EmptyView() } trailing: {
            Text(store.money(value)).font(.body).foregroundStyle(Color.textSecondary).monospacedDigit()
        }
    }

    @ViewBuilder
    private func evolution(_ series: [NetWorthPoint]) -> some View {
        let known = series.filter { $0.netWorth != nil }
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Evolução mensal")
            if known.count < 2 {
                Text("O app registra o patrimônio a cada mês em que você o abre. A evolução aparece a partir do segundo mês.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            } else {
                Chart(known, id: \.month) { p in
                    BarMark(x: .value("Mês", DateText.monthShort(p.month)), y: .value("Patrimônio", NSDecimalNumber(decimal: p.netWorth ?? 0).doubleValue))
                        .foregroundStyle(Color.brandPrimary)
                }
                .chartYAxis(.hidden)
                .frame(height: 160)
                .padding(Space.md)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gráfico do patrimônio líquido nos últimos \(known.count) meses registrados.")
                .accessibilityIdentifier("wallet.networth.chart")
            }
        }
    }
}

#Preview("Investimentos") {
    NavigationStack { InvestmentsView() }.previewing(PreviewData.demo)
}

#Preview("Investimentos vazio") {
    NavigationStack { InvestmentsView() }.previewing(PreviewData.empty)
}

#Preview("Investimentos, escuro, texto grande") {
    NavigationStack { InvestmentsView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Patrimônio") {
    NavigationStack { NetWorthView() }.previewing(PreviewData.demo)
}

#Preview("Novo ativo") {
    InvestmentFormSheet(investmentId: nil).previewing(PreviewData.demo)
}

#Preview("Detalhe do ativo") {
    let store = PreviewData.demo
    InvestmentDetailSheet(investmentId: store.investments[1].id).previewing(store)
}
